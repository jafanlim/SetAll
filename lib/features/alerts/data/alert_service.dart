import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../data/repositories/setall_repository.dart';

// ---------------------------------------------------------------------------
// ProactiveAlertService
//
// Runs two checks client-side (Supabase-direct on web):
//   1. Anomaly: latest expense > k × category mean over N months.
//   2. Budget threshold: current-period spend ≥ 80 % or 100 % of budget limit.
//
// Deduplicates via alert_log so each alert fires at most once per event.
// ---------------------------------------------------------------------------

enum AlertType { anomaly, budget80, budget100 }

class ProactiveAlert {
  const ProactiveAlert({
    required this.type,
    required this.title,
    required this.body,
    required this.refKey,
    this.expenseGroupId,
    this.payload,
  });
  final AlertType type;
  final String title;
  final String body;
  /// Expense ID (for anomaly alerts) or budget ref key.
  final String refKey;
  /// Non-null when the anomaly expense belongs to a group — used for
  /// tap-through navigation to the correct detail screen.
  final String? expenseGroupId;
  /// Optional expense data for deep-link navigation to detail screen.
  /// Keys: id, amount, currency, description, category, isIncome, createdAt.
  final Map<String, dynamic>? payload;
}

class AlertPrefs {
  const AlertPrefs({
    this.anomalyEnabled = true,
    this.budget80Enabled = true,
    this.budget100Enabled = true,
    this.anomalyK = 2.0,
    this.anomalyMonths = 3,
  });

  final bool anomalyEnabled;
  final bool budget80Enabled;
  final bool budget100Enabled;
  final double anomalyK;
  final int anomalyMonths;

  AlertPrefs copyWith({
    bool? anomalyEnabled,
    bool? budget80Enabled,
    bool? budget100Enabled,
    double? anomalyK,
    int? anomalyMonths,
  }) =>
      AlertPrefs(
        anomalyEnabled: anomalyEnabled ?? this.anomalyEnabled,
        budget80Enabled: budget80Enabled ?? this.budget80Enabled,
        budget100Enabled: budget100Enabled ?? this.budget100Enabled,
        anomalyK: anomalyK ?? this.anomalyK,
        anomalyMonths: anomalyMonths ?? this.anomalyMonths,
      );

  factory AlertPrefs.fromRow(Map<String, dynamic> row) => AlertPrefs(
        anomalyEnabled: _parseBool(row['anomaly_enabled'], def: true),
        budget80Enabled: _parseBool(row['budget_80_enabled'], def: true),
        budget100Enabled: _parseBool(row['budget_100_enabled'], def: true),
        anomalyK: double.tryParse(row['anomaly_k']?.toString() ?? '') ?? 2.0,
        anomalyMonths: int.tryParse(row['anomaly_months']?.toString() ?? '') ?? 3,
      );

  Map<String, dynamic> toRow() => {
        'anomaly_enabled': anomalyEnabled,
        'budget_80_enabled': budget80Enabled,
        'budget_100_enabled': budget100Enabled,
        'anomaly_k': anomalyK,
        'anomaly_months': anomalyMonths,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };

  static bool _parseBool(dynamic v, {bool def = true}) {
    if (v is bool) return v;
    if (v is int) return v != 0;
    return def;
  }
}

class ProactiveAlertService {
  const ProactiveAlertService(this._repo);
  final SetAllRepository _repo;

  // ---------------------------------------------------------------------------
  // Prefs CRUD
  // ---------------------------------------------------------------------------

  Future<AlertPrefs> getPrefs() async {
    final row = await _repo.getAlertPrefs();
    if (row == null) return const AlertPrefs();
    return AlertPrefs.fromRow(row);
  }

  Future<void> savePrefs(AlertPrefs prefs) => _repo.upsertAlertPrefs(prefs.toRow());

  // ---------------------------------------------------------------------------
  // Anomaly check
  //
  // For the most-recent personal expense: compare its base-currency amount
  // to the historical mean for that category over [prefs.anomalyMonths] months
  // (excluding the current month so the new expense doesn't inflate the mean).
  // ---------------------------------------------------------------------------
  Future<List<ProactiveAlert>> checkAnomaly({
    required AlertPrefs prefs,
    required Map<String, Decimal> categorySpendThisMonth,
    required Map<String, Decimal> categorySpendHistory,
    // category → historical mean (caller computes over N months)
    required Map<String, Decimal> categoryMean,
    required String latestExpenseId,
    required String latestCategory,
    required Decimal latestAmountBase,
    String? expenseGroupId,
    Map<String, dynamic>? payload,
  }) async {
    if (!prefs.anomalyEnabled) return [];
    if (latestAmountBase <= Decimal.zero) return [];

    final mean = categoryMean[latestCategory] ?? Decimal.zero;
    if (mean <= Decimal.zero) return [];

    final threshold = Decimal.parse((mean.toDouble() * prefs.anomalyK).toStringAsFixed(6));
    if (latestAmountBase <= threshold) return [];

    // Dedup check
    final refKey = latestExpenseId;
    final alreadyFired = await _repo.alertLogContains(
        alertType: 'anomaly', refKey: refKey);
    if (alreadyFired) return [];

    await _repo.insertAlertLog(alertType: 'anomaly', refKey: refKey);

    debugPrint('[AlertService] anomaly fired: $latestCategory '
        '${latestAmountBase.toStringAsFixed(2)} > '
        '${threshold.toStringAsFixed(2)} (k=${prefs.anomalyK})');

    return [
      ProactiveAlert(
        type: AlertType.anomaly,
        title: 'alerts.anomaly_title',
        body: 'alerts.anomaly_body',
        refKey: refKey,
        expenseGroupId: expenseGroupId,
        payload: payload,
      ),
    ];
  }

  // ---------------------------------------------------------------------------
  // Budget threshold check
  //
  // Compares current-period spend to each budget limit.
  // Fires budget_80 once when spend crosses 80 %, budget_100 once at 100 %.
  // ---------------------------------------------------------------------------
  Future<List<ProactiveAlert>> checkBudgets({
    required AlertPrefs prefs,
    required List<Map<String, dynamic>> budgets,
    required Map<String, Decimal> categorySpend,
    required Decimal totalSpend,
  }) async {
    final alerts = <ProactiveAlert>[];
    if (!prefs.budget80Enabled && !prefs.budget100Enabled) return alerts;

    for (final b in budgets) {
      final id = b['id'] as String? ?? '';
      final category = b['category'] as String?; // null = Overall
      final limitRaw = double.tryParse(b['amount']?.toString() ?? '') ?? 0.0;
      if (limitRaw <= 0) continue;

      final spend = category == null ? totalSpend : (categorySpend[category] ?? Decimal.zero);
      if (spend <= Decimal.zero) continue;

      final pct = spend.toDouble() / limitRaw;

      if (prefs.budget100Enabled && pct >= 1.0) {
        final refKey = 'budget:$id:100';
        final fired = await _repo.alertLogContains(alertType: 'budget_100', refKey: refKey);
        if (!fired) {
          await _repo.insertAlertLog(alertType: 'budget_100', refKey: refKey);
          alerts.add(ProactiveAlert(
            type: AlertType.budget100,
            title: 'alerts.budget100_title',
            body: 'alerts.budget100_body',
            refKey: refKey,
          ));
        }
      } else if (prefs.budget80Enabled && pct >= 0.8) {
        final refKey = 'budget:$id:80';
        final fired = await _repo.alertLogContains(alertType: 'budget_80', refKey: refKey);
        if (!fired) {
          await _repo.insertAlertLog(alertType: 'budget_80', refKey: refKey);
          alerts.add(ProactiveAlert(
            type: AlertType.budget80,
            title: 'alerts.budget80_title',
            body: 'alerts.budget80_body',
            refKey: refKey,
          ));
        }
      }
    }
    return alerts;
  }
}

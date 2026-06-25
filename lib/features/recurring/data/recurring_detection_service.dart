import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../../../data/models/expense_model.dart';
import 'recurring_candidate.dart';

// ---------------------------------------------------------------------------
// RecurringDetectionService
//
// Heuristic: fuzzy description match (normalised) + amount within ±10% +
// 28–32-day spacing between occurrences.
//
// Consumes the raw [getPersonalExpenses()] list — same source as
// getCategorySpend / setall-budgets. No network calls.
// ---------------------------------------------------------------------------
class RecurringDetectionService {
  RecurringDetectionService._();

  static const int _kMinOccurrences = 2;
  static const int _kMinIntervalDays = 27;
  static const int _kMaxIntervalDays = 33;
  static const double _kAmountTolerancePct = 0.10;

  /// Detect recurring candidates from a raw expense list.
  /// Only expenses that are NOT income are considered.
  static List<RecurringCandidate> detect(List<ExpenseModel> expenses) {
    final candidates = <RecurringCandidate>[];

    final eligible = expenses
        .where((e) =>
            !e.isIncome &&
            e.createdAt != null)
        .toList(); // description can be empty — fall back to category for grouping

    debugPrint('[RecurringDetect] total expenses: ${expenses.length}, '
        'eligible (non-income + has date + has desc): ${eligible.length}');
    // Debug: show WHY each expense was filtered in or out.
    for (final e in expenses) {
      final reasons = <String>[];
      if (e.isIncome) reasons.add('isIncome');
      if (e.createdAt == null) reasons.add('no-date');
      if (e.description.trim().isEmpty) reasons.add('no-desc');
      final status = reasons.isEmpty ? 'ELIGIBLE' : 'FILTERED(${reasons.join(",")})';
      debugPrint('[RecurringDetect]   $status cat="${e.category}" desc="${e.description}" '
          'date=${e.createdAt} amt=${e.amount} ${e.currency}');
    }

    if (eligible.length < _kMinOccurrences) {
      debugPrint('[RecurringDetect] too few eligible entries (< $_kMinOccurrences), returning empty');
      return candidates;
    }

    // Group by normalised description key (fall back to category when empty).
    final groups = <String, List<ExpenseModel>>{};
    for (final e in eligible) {
      final raw = e.description.trim().isEmpty ? e.category : e.description;
      final key = _normalise(raw);
      groups.putIfAbsent(key, () => []).add(e);
    }

    debugPrint('[RecurringDetect] description groups: ${groups.length}');
    for (final entry in groups.entries) {
      final group = entry.value;
      debugPrint('[RecurringDetect]   "${entry.key}": ${group.length} entries');
      if (group.length < _kMinOccurrences) continue;

      // Sort ascending by date.
      group.sort((a, b) {
        final da = DateTime.tryParse(a.createdAt!) ?? DateTime(2000);
        final db = DateTime.tryParse(b.createdAt!) ?? DateTime(2000);
        return da.compareTo(db);
      });

      // Debug: print each entry's parsed date and amount
      for (final e in group) {
        final d = DateTime.tryParse(e.createdAt!);
        debugPrint('[RecurringDetect]     date=$d amount=${e.amount} ${e.currency} '
            'desc="${e.description}" groupId=${e.groupId ?? "null"}');
      }

      // Find the modal amount (within tolerance) and detect spacing.
      final result = _analyseCandidates(group);
      if (result != null) {
        candidates.add(result);
      } else {
        debugPrint('[RecurringDetect]   _analyseCandidates returned null for "${entry.key}"');
      }
    }

    // Also check cross-description groups with identical amount (catch e.g.
    // bank fees labelled slightly differently each month).
    final amountGroups = <String, List<ExpenseModel>>{};
    for (final e in eligible) {
      final amtKey =
          '${e.currency}:${_roundAmount(double.tryParse(e.amount) ?? 0)}';
      amountGroups.putIfAbsent(amtKey, () => []).add(e);
    }

    for (final entry in amountGroups.entries) {
      final group = entry.value;
      if (group.length < _kMinOccurrences) continue;

      // Skip if already covered by description grouping.
      final descKeys = group.map((e) => _normalise(e.description)).toSet();
      if (descKeys.length == 1) continue; // already handled above

      group.sort((a, b) {
        final da = DateTime.tryParse(a.createdAt!) ?? DateTime(2000);
        final db = DateTime.tryParse(b.createdAt!) ?? DateTime(2000);
        return da.compareTo(db);
      });

      final result = _analyseCandidates(group, descOverride: entry.key);
      if (result != null) candidates.add(result);
    }

    // Third pass: group by category (currency) — catches entries with different
    // descriptions but same category that repeat on a ~monthly cadence.
    // Example: two "автомойка" and "car wash" entries both in "Transport" with
    // similar amounts ~30 days apart.
    final categoryGroups = <String, List<ExpenseModel>>{};
    for (final e in eligible) {
      final cat = e.category.isEmpty ? 'General' : e.category;
      final catKey = '${cat.toLowerCase().trim()}:${e.currency}';
      categoryGroups.putIfAbsent(catKey, () => []).add(e);
    }
    debugPrint('[RecurringDetect] category+currency groups: ${categoryGroups.length}');
    for (final entry in categoryGroups.entries) {
      final group = entry.value;
      if (group.length < _kMinOccurrences) continue;
      debugPrint('[RecurringDetect]   category "${entry.key}": ${group.length} entries');

      // Skip if already covered by description or amount grouping.
      final descKeys = group.map((e) => _normalise(e.description)).toSet();
      if (descKeys.length == 1) continue; // already handled

      group.sort((a, b) {
        final da = DateTime.tryParse(a.createdAt!) ?? DateTime(2000);
        final db = DateTime.tryParse(b.createdAt!) ?? DateTime(2000);
        return da.compareTo(db);
      });

      // Debug: print each entry
      for (final e in group) {
        final d = DateTime.tryParse(e.createdAt!);
        debugPrint('[RecurringDetect]     cat-date=$d amount=${e.amount} ${e.currency} '
            'desc="${e.description}"');
      }

      final result = _analyseCandidates(group,
          descOverride: '${entry.key} (category)');
      if (result != null) {
        candidates.add(result);
      } else {
        debugPrint('[RecurringDetect]   category _analyseCandidates null for "${entry.key}"');
      }
    }

    // Deduplicate: remove candidates fully subsumed by a higher-confidence one.
    candidates.sort((a, b) => b.confidence.compareTo(a.confidence));

    final seen = <String>{};
    final deduped = <RecurringCandidate>[];
    for (final c in candidates) {
      final key = '${_normalise(c.description)}:${c.currency}';
      if (!seen.contains(key)) {
        seen.add(key);
        deduped.add(c);
      }
    }

    debugPrint('[RecurringDetect] detected ${deduped.length} candidates');
    for (final c in deduped) {
      debugPrint('[RecurringDetect]   candidate: "${c.description}" ${c.currency} ${c.amount} '
          'every ${c.intervalDays}d confidence=${c.confidence}');
    }
    return deduped;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static RecurringCandidate? _analyseCandidates(
    List<ExpenseModel> group, {
    String? descOverride,
  }) {
    // Find the most common amount (mode within ±tolerance).
    final amounts = group
        .map((e) => double.tryParse(e.amount) ?? 0.0)
        .where((a) => a > 0)
        .toList();
    if (amounts.isEmpty) return null;

    final modalAmount = _modalAmount(amounts);
    if (modalAmount <= 0) return null;

    // Filter to expenses whose amount is within tolerance of modal.
    final matched = group.where((e) {
      final a = double.tryParse(e.amount) ?? 0.0;
      return (a - modalAmount).abs() / modalAmount <= _kAmountTolerancePct;
    }).toList();

    if (matched.length < _kMinOccurrences) return null;

    // Check intervals between consecutive matched occurrences.
    final dates = matched
        .map((e) => DateTime.tryParse(e.createdAt!))
        .whereType<DateTime>()
        .toList();
    if (dates.length < _kMinOccurrences) {
      debugPrint('[RecurringDetect]   reject: only ${dates.length} matched-dates (< $_kMinOccurrences)');
      return null;
    }

    final intervals = <int>[];
    for (var i = 1; i < dates.length; i++) {
      intervals.add(dates[i].difference(dates[i - 1]).inDays);
    }

    debugPrint('[RecurringDetect]   intervals: $intervals days (range $_kMinIntervalDays–$_kMaxIntervalDays)');

    final inRangeCount = intervals
        .where((d) => d >= _kMinIntervalDays && d <= _kMaxIntervalDays)
        .length;
    if (inRangeCount == 0) {
      debugPrint('[RecurringDetect]   reject: 0 intervals in range $_kMinIntervalDays–$_kMaxIntervalDays');
      return null;
    }

    final confidence = inRangeCount / math.max(intervals.length, 1);
    if (confidence < 0.5) return null;

    final avgInterval = intervals.fold(0, (a, b) => a + b) ~/ intervals.length;
    final effectiveInterval =
        avgInterval.clamp(_kMinIntervalDays, _kMaxIntervalDays);

    // Pick the expense whose parsed amount is closest to the modal
    // as the representative — use its real amount string (Decimal), not the float.
    ExpenseModel? representative = matched.last;
    double bestDiff = double.infinity;
    for (final e in matched) {
      final a = double.tryParse(e.amount) ?? 0.0;
      final diff = (a - modalAmount).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        representative = e;
      }
    }

    return RecurringCandidate(
      description: descOverride != null
          ? matched
              .map((e) => e.description)
              .reduce((a, b) => a.length <= b.length ? a : b)
          : representative!.description,
      amount: Decimal.parse(representative!.amount),
      currency: representative.currency,
      category: representative.category,
      intervalDays: effectiveInterval,
      lastSeenAt: dates.last,
      confidence: confidence.clamp(0.0, 1.0),
      occurrences: dates,
    );
  }

  /// Returns the modal amount — most-common value within ±10% clustering.
  static double _modalAmount(List<double> amounts) {
    if (amounts.isEmpty) return 0;
    double best = amounts.first;
    int bestCount = 0;
    for (final pivot in amounts) {
      final count = amounts
          .where((a) => (a - pivot).abs() / pivot <= _kAmountTolerancePct)
          .length;
      if (count > bestCount) {
        bestCount = count;
        best = pivot;
      }
    }
    return best;
  }

  /// Normalise a description to a stable grouping key.
  /// Lowercases, strips leading numbers/dates, collapses whitespace.
  static String _normalise(String desc) {
    var s = desc.toLowerCase().trim();
    // Strip leading date/ref tokens (common in bank statements).
    s = s.replaceAll(RegExp(r'^[\d\s\-/]+'), '');
    // Strip trailing reference numbers.
    s = s.replaceAll(RegExp(r'\s+\d{4,}$'), '');
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    return s;
  }

  /// Round to 2 significant figures for amount grouping key.
  static double _roundAmount(double a) => (a * 100).round() / 100;
}

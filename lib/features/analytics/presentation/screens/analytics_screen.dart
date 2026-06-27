import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/category_utils.dart';
import '../../../../data/models/expense_model.dart';
import '../../../../data/models/wallet_entry_model.dart';
import '../../../settings/services/pdf_export_service.dart';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const _teal   = Color(0xFF14B8A6); // LOOKBOOK Brand Teal
const _gold   = Color(0xFFD4AF37);
const _rose   = Color(0xFFF43F5E);
const _violet = Color(0xFF8B5CF6);
const _sky    = Color(0xFF0EA5E9);
const _orange = Color(0xFFF97316);
const _lime   = Color(0xFF84CC16);
const _pink   = Color(0xFFEC4899);

const _kPaletteColors = [
  _teal, _gold, _rose, _violet, _sky, _orange, _lime, _pink,
  Color(0xFF14B8A6), Color(0xFFEAB308), Color(0xFF6366F1),
];

const _kSubtitle = Color(0xFF64748B);
const _kLabel    = Color(0xFF94A3B8);

// ---------------------------------------------------------------------------
// Filter state
// ---------------------------------------------------------------------------
enum _Source   { all, wallet, groups }
enum _ChartType { donut, pie, bar }
enum _DataMode  { spending, income, balance }

class _DateRange {
  const _DateRange({required this.days, this.from, this.to});
  final int days;        // 0 = custom
  final DateTime? from;
  final DateTime? to;

  DateTime get cutoff {
    if (days == 0 && from != null) return from!;
    return DateTime.now().subtract(Duration(days: days));
  }

  String label() {
    if (days == 7)   return '7d';
    if (days == 30)  return '30d';
    if (days == 90)  return '90d';
    if (days == 365) return '1y';
    if (days == 0 && from != null && to != null) {
      final fmt = DateFormat('dd/MM/yyyy');
      return '${fmt.format(from!)} – ${fmt.format(to!)}';
    }
    return 'Custom'; // analytics.date_custom
  }
}

class _AnalyticsFilter {
  const _AnalyticsFilter({
    this.source    = _Source.all,
    this.dateRange = const _DateRange(days: 30),
    this.groupId,
    this.chartType = _ChartType.donut,
    this.dataMode  = _DataMode.spending,
  });
  final _Source      source;
  final _DateRange   dateRange;
  final String?      groupId;
  final _ChartType   chartType;
  final _DataMode    dataMode;

  _AnalyticsFilter copyWith({
    _Source? source,
    _DateRange? dateRange,
    String? groupId,
    bool clearGroup = false,
    _ChartType? chartType,
    _DataMode? dataMode,
  }) => _AnalyticsFilter(
    source:    source    ?? this.source,
    dateRange: dateRange ?? this.dateRange,
    groupId:   clearGroup ? null : (groupId ?? this.groupId),
    chartType: chartType ?? this.chartType,
    dataMode:  dataMode  ?? this.dataMode,
  );
}

final _analyticsFilterProvider =
    StateProvider<_AnalyticsFilter>((_) => const _AnalyticsFilter());

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------
class IvEPeriod {
  const IvEPeriod(this.label, this.income, this.expense);
  final String label;
  final Decimal income;
  final Decimal expense;
}

/// Unified row for the analytics drill-down list.
/// Sourced from either [ExpenseModel] (group) or [WalletEntryModel] (wallet).
class AnalyticsRow {
  const AnalyticsRow({
    required this.isIncome,
    required this.amount,
    this.originalAmount,
    this.originalCurrency,
    required this.currency,
    required this.category,
    required this.description,
    this.createdAt,
    this.universalUsdAmount = '0',
    this.groupId,
  });

  final bool    isIncome;
  final String  amount;
  final String? originalAmount;
  final String? originalCurrency;
  final String  currency;
  final String  category;
  final String  description;
  final String? createdAt;
  final String  universalUsdAmount;
  final String? groupId;

  factory AnalyticsRow.fromExpense(ExpenseModel e) => AnalyticsRow(
    isIncome:          e.isIncome,
    amount:            e.amount,
    originalAmount:    e.originalAmount,
    originalCurrency:  e.originalCurrency,
    currency:          e.currency,
    category:          e.category,
    description:       e.description,
    createdAt:         e.createdAt,
    universalUsdAmount: e.universalUsdAmount ?? '0',
    groupId:           e.groupId,
  );

  factory AnalyticsRow.fromWalletEntry(WalletEntryModel e) => AnalyticsRow(
    isIncome:          e.isIncome,
    amount:            e.amount,
    originalAmount:    e.originalAmount,
    originalCurrency:  e.originalCurrency,
    currency:          e.currency,
    category:          e.category,
    description:       e.description,
    createdAt:         e.createdAt,
    universalUsdAmount: e.universalUsdAmount,
    groupId:           null,
  );
}

class AnalyticsData {
  const AnalyticsData({
    required this.categoryTotals,
    required this.netTrend,
    required this.totalSpend,
    required this.totalIncome,
    required this.currency,
    required this.currencyBreakdown,
    required this.netFlow,
    required this.netFlowPct,
    required this.burnRate,
    required this.topCategory,
    required this.topCategoryPct,
    required this.ivePeriods,
    required this.incomeCategoryTotals,
    required this.allExpenses,
  });
  final Map<String, Decimal> categoryTotals;
  final List<FlSpot>         netTrend;
  final Decimal              totalSpend;
  final Decimal              totalIncome;
  final String               currency;
  final Map<String, Decimal> currencyBreakdown;
  // Vital signs
  final Decimal netFlow;         // income - spend (Decimal, exact)
  final double  netFlowPct;      // % vs previous period (0 if unavailable)
  final double  burnRate;        // avg daily spend (derived from Decimal sum)
  final String  topCategory;
  final double  topCategoryPct;
  // Income vs Expense chart periods
  final List<IvEPeriod> ivePeriods;
  // Income breakdown by category (mirrors categoryTotals but for income)
  final Map<String, Decimal> incomeCategoryTotals;
  // Raw filtered rows for drill-down list
  final List<AnalyticsRow> allExpenses;
}

// ---------------------------------------------------------------------------
// Provider (parameterized by filter)
// ---------------------------------------------------------------------------
final analyticsDataProvider = FutureProvider<AnalyticsData>((ref) async {
  final baseCurrency = await ref.watch(baseCurrencyProvider.future);
  final filter       = ref.watch(_analyticsFilterProvider);

  // Fetch the USD → baseCurrency rate once for the whole computation.
  // If baseCurrency IS USD this returns 1 (no network call).
  final usdToBaseRate = await ref
      .watch(exchangeRateProvider(baseCurrency).future)
      .then((s) => Decimal.tryParse(s) ?? Decimal.one);

  // Pull raw rows based on source
  List<AnalyticsRow> all = [];
  if (filter.source == _Source.wallet || filter.source == _Source.all) {
    final walletEntries = await ref.watch(walletEntriesProvider.future);
    all.addAll(walletEntries.map(AnalyticsRow.fromWalletEntry));
  }
  if (filter.source == _Source.groups || filter.source == _Source.all) {
    final recent = await ref.watch(recentExpensesProvider.future);
    all.addAll(recent.map(AnalyticsRow.fromExpense));
  }

  // De-duplicate by description+amount+date (rows have no shared id)
  final seen  = <String>{};
  final dedup = <AnalyticsRow>[];
  for (final e in all) {
    final key = '${e.createdAt}_${e.amount}_${e.description}';
    if (seen.add(key)) dedup.add(e);
  }

  // Group filter
  final List<AnalyticsRow> filtered = filter.groupId != null
      ? dedup.where((e) => e.groupId == filter.groupId).toList()
      : dedup;

  // Amount normalization: convert to baseCurrency.
  // 1. If the expense was originally recorded in baseCurrency, use originalAmount directly.
  // 2. Otherwise multiply the stored universalUsdAmount by the live USD→base rate.
  Decimal normalizedAmt(AnalyticsRow e) {
    final rawUsd   = Decimal.tryParse(e.universalUsdAmount) ?? Decimal.zero;
    final entryCcy = e.originalCurrency ?? e.currency;
    if (entryCcy == baseCurrency && e.originalAmount != null) {
      return Decimal.tryParse(e.originalAmount!) ?? rawUsd;
    }
    return rawUsd * usdToBaseRate;
  }

  // Date window
  final now    = DateTime.now();
  final cutoff = filter.dateRange.cutoff;
  final to     = filter.dateRange.days == 0 && filter.dateRange.to != null
      ? filter.dateRange.to!.add(const Duration(days: 1))
      : now.add(const Duration(days: 1));

  // Category totals + currency breakdown + income (within window)
  final categoryMap        = <String, Decimal>{};
  final incomeMap          = <String, Decimal>{};
  final currencyBreakdown  = <String, Decimal>{};
  Decimal totalIncome      = Decimal.zero;
  final windowExpenses     = <AnalyticsRow>[];   // for drill-down list

  for (final e in filtered) {
    final dateStr = e.createdAt;
    if (dateStr == null) continue;
    final date = DateTime.tryParse(dateStr);
    if (date == null || date.isBefore(cutoff) || date.isAfter(to)) continue;

    final amt = normalizedAmt(e);
    windowExpenses.add(e);

    if (e.isIncome) {
      totalIncome += amt;
      final cat = e.category.isNotEmpty ? e.category : 'Income';
      incomeMap[cat] = (incomeMap[cat] ?? Decimal.zero) + amt;
      continue;
    }

    final cat = e.category.isNotEmpty ? e.category : 'Other';
    categoryMap[cat] = (categoryMap[cat] ?? Decimal.zero) + amt;

    // Original currency tally for the right panel
    final ccy = e.originalCurrency ?? e.currency;
    if (ccy.isNotEmpty && ccy != baseCurrency) {
      final origAmt = Decimal.tryParse(e.originalAmount ?? e.amount) ?? Decimal.zero;
      currencyBreakdown[ccy] = (currencyBreakdown[ccy] ?? Decimal.zero) + origAmt;
    }
  }

  // Top-8 + bucket rest
  final sorted = categoryMap.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final Map<String, Decimal> topCats = {};
  Decimal otherTotal = Decimal.zero;
  for (int i = 0; i < sorted.length; i++) {
    if (i < 8) {
      topCats[sorted[i].key] = sorted[i].value;
    } else {
      otherTotal += sorted[i].value;
    }
  }
  if (otherTotal > Decimal.zero) topCats['Other'] = otherTotal;

  final totalSpend = topCats.values.fold(Decimal.zero, (a, b) => a + b);

  // Span must be declared before vital signs and trend sections
  final spanDays = now.difference(cutoff).inDays.clamp(1, 365);

  // ── Vital signs ───────────────────────────────────────────────────────────
  final netFlow   = totalIncome - totalSpend;
  final burnRate  = spanDays > 0 ? totalSpend.toDouble() / spanDays : 0.0;

  // Previous period for % change comparison
  final prevCutoff = cutoff.subtract(Duration(days: spanDays));
  Decimal prevSpend = Decimal.zero;
  Decimal prevIncome = Decimal.zero;
  for (final e in filtered) {
    final dateStr = e.createdAt;
    if (dateStr == null) continue;
    final date = DateTime.tryParse(dateStr);
    if (date == null || !date.isAfter(prevCutoff) || !date.isBefore(cutoff)) continue;
    final amt = normalizedAmt(e);
    if (e.isIncome) { prevIncome += amt; } else { prevSpend += amt; }
  }
  final prevNet   = prevIncome - prevSpend;
  final netFlowPct = prevNet != Decimal.zero
      ? ((netFlow - prevNet).toDouble() / prevNet.abs().toDouble() * 100)
      : 0.0;

  final topCatEntry = topCats.isNotEmpty
      ? (topCats.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).first
      : null;
  final topCategory    = topCatEntry?.key    ?? '';
  final topCategoryPct = totalSpend > Decimal.zero && topCatEntry != null
      ? topCatEntry.value.toDouble() / totalSpend.toDouble() * 100
      : 0.0;

  // ── Income vs Expense grouped bars ────────────────────────────────────────
  // Choose granularity: weekly for ≤90d windows, monthly otherwise
  final List<IvEPeriod> ivePeriods = [];
  if (spanDays <= 90) {
    // Weekly buckets
    final weeks = (spanDays / 7).ceil().clamp(1, 13);
    for (int w = weeks - 1; w >= 0; w--) {
      final wStart = cutoff.add(Duration(days: w * 7));
      final wEnd   = wStart.add(const Duration(days: 7));
      Decimal inc = Decimal.zero, exp = Decimal.zero;
      for (final e in windowExpenses) {
        final date = DateTime.tryParse(e.createdAt ?? '');
        if (date == null || !date.isAfter(wStart) || !date.isBefore(wEnd)) continue;
        final amt = normalizedAmt(e);
        if (e.isIncome) { inc += amt; } else { exp += amt; }
      }
      final label = 'W${weeks - w}';
      ivePeriods.add(IvEPeriod(label, inc, exp));
    }
  } else {
    // Monthly buckets
    final months = (spanDays / 30).ceil().clamp(1, 13);
    for (int m = months - 1; m >= 0; m--) {
      final mStart = DateTime(now.year, now.month - m, 1);
      final mEnd   = DateTime(now.year, now.month - m + 1, 1);
      Decimal inc = Decimal.zero, exp = Decimal.zero;
      for (final e in windowExpenses) {
        final date = DateTime.tryParse(e.createdAt ?? '');
        if (date == null || !date.isAfter(mStart) || !date.isBefore(mEnd)) continue;
        final amt = normalizedAmt(e);
        if (e.isIncome) { inc += amt; } else { exp += amt; }
      }
      final label = DateFormat('MMM').format(mStart);
      ivePeriods.add(IvEPeriod(label, inc, exp));
    }
  }

  // Net trend over selected window
  final dailyNet = List<Decimal>.filled(spanDays, Decimal.zero);
  for (final e in filtered) {
    final dateStr = e.createdAt;
    if (dateStr == null) continue;
    final date = DateTime.tryParse(dateStr);
    if (date == null || date.isBefore(cutoff) || date.isAfter(to)) continue;
    final daysAgo = now.difference(date).inDays;
    if (daysAgo < 0 || daysAgo >= spanDays) continue;
    final idx = spanDays - 1 - daysAgo;
    final amt = normalizedAmt(e);
    dailyNet[idx] += e.isIncome ? amt : -amt;
  }

  Decimal running = Decimal.zero;
  final spots = <FlSpot>[];
  for (int i = 0; i < spanDays; i++) {
    running += dailyNet[i];
    spots.add(FlSpot(i.toDouble(), running.toDouble()));
  }

  return AnalyticsData(
    categoryTotals:    topCats,
    netTrend:          spots,
    totalSpend:        totalSpend,
    totalIncome:       totalIncome,
    currency:          baseCurrency,
    currencyBreakdown: currencyBreakdown,
    netFlow:           netFlow,
    netFlowPct:        netFlowPct,
    burnRate:          burnRate,
    topCategory:       topCategory,
    topCategoryPct:    topCategoryPct,
    ivePeriods:            ivePeriods,
    incomeCategoryTotals:  incomeMap,
    allExpenses:           windowExpenses,
  );
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int?    _touchedIndex;
  String? _drillCategory; // null = show all

  @override
  Widget build(BuildContext context) {
    final theme          = Theme.of(context);
    final analyticsAsync = ref.watch(analyticsDataProvider);
    final filter         = ref.watch(_analyticsFilterProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'analytics.title'.tr(),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        automaticallyImplyLeading: false,
        actions: [
          analyticsAsync.whenOrNull(
            data: (data) => IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Download report',
              onPressed: () => PdfExportService().exportAnalyticsPdf(
                income:   data.totalIncome.toDouble(),
                expenses: data.totalSpend.toDouble(),
                entries:  data.allExpenses,
                currency: data.currency,
              ),
            ),
          ) ?? const SizedBox.shrink(),
        ],
      ),
      body: Column(
        children: [
          // ── Filter bar ───────────────────────────────────────────────────
          _FilterBar(
            filter: filter,
            onFilterChanged: (f) {
              ref.read(_analyticsFilterProvider.notifier).state = f;
              setState(() => _touchedIndex = null);
            },
          ),
          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: analyticsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(
                child: Text('common.error'.tr(),
                  style: TextStyle(color: theme.colorScheme.error)),
              ),
              data: (data) {
                if (data.totalSpend == Decimal.zero &&
                    data.netTrend.every((s) => s.y == 0)) {
                  return _EmptyState();
                }
                return _AnalyticsBody(
                  data:          data,
                  filter:        filter,
                  touchedIndex:  _touchedIndex,
                  drillCategory: _drillCategory,
                  onTouch: (i) => setState(() {
                    _touchedIndex = i;
                    if (i == null) {
                      _drillCategory = null;
                    } else {
                      final keys = filter.dataMode == _DataMode.income
                          ? data.incomeCategoryTotals.keys
                          : data.categoryTotals.keys;
                      _drillCategory = i < keys.length
                          ? keys.elementAt(i)
                          : null;
                    }
                  }),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter bar
// ---------------------------------------------------------------------------
class _FilterBar extends ConsumerWidget {
  const _FilterBar({required this.filter, required this.onFilterChanged});
  final _AnalyticsFilter          filter;
  final ValueChanged<_AnalyticsFilter> onFilterChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(myGroupsProvider).valueOrNull ?? [];

    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: Source + Date
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // Source chips
                _FilterChip(
                  label: 'analytics.filter_all'.tr(),
                  active: filter.source == _Source.all,
                  onTap: () => onFilterChanged(
                    filter.copyWith(source: _Source.all, clearGroup: true)),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'analytics.wallet'.tr(),
                  active: filter.source == _Source.wallet,
                  onTap: () => onFilterChanged(
                    filter.copyWith(source: _Source.wallet, clearGroup: true)),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'analytics.groups'.tr(),
                  active: filter.source == _Source.groups,
                  onTap: () => onFilterChanged(
                    filter.copyWith(source: _Source.groups)),
                ),
                const SizedBox(width: 14),
                // Date chips
                for (final d in [7, 30, 90, 365])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _FilterChip(
                      label: _DateRange(days: d).label(),
                      active: filter.dateRange.days == d,
                      onTap: () => onFilterChanged(
                        filter.copyWith(dateRange: _DateRange(days: d))),
                    ),
                  ),
                _FilterChip(
                  label: filter.dateRange.days == 0
                      ? filter.dateRange.label()
                      : 'analytics.date_custom'.tr(),
                  active: filter.dateRange.days == 0,
                  icon: Icons.calendar_today_outlined,
                  onTap: () => _pickDateRange(context),
                ),
              ],
            ),
          ),
          // Row 2: Data mode (Spending / Income / Balance Sheet)
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'analytics.mode_spending'.tr(),
                  active: filter.dataMode == _DataMode.spending,
                  onTap: () => onFilterChanged(
                    filter.copyWith(dataMode: _DataMode.spending)),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'analytics.mode_income'.tr(),
                  active: filter.dataMode == _DataMode.income,
                  onTap: () => onFilterChanged(
                    filter.copyWith(dataMode: _DataMode.income)),
                ),
                const SizedBox(width: 6),
                _FilterChip(
                  label: 'analytics.mode_balance'.tr(),
                  active: filter.dataMode == _DataMode.balance,
                  onTap: () => onFilterChanged(
                    filter.copyWith(dataMode: _DataMode.balance)),
                ),
              ],
            ),
          ),
          // Row 3: Group picker (only when Groups source active)
          if ((filter.source == _Source.groups ||
               filter.source == _Source.all) &&
              groups.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterChip(
                      label: 'analytics.all_groups'.tr(),
                      active: filter.groupId == null,
                      onTap: () => onFilterChanged(
                        filter.copyWith(clearGroup: true)),
                    ),
                    const SizedBox(width: 6),
                    ...groups.map((g) => Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: _FilterChip(
                        label: g.name,
                        active: filter.groupId == g.id,
                        onTap: () => onFilterChanged(
                          filter.copyWith(groupId: g.id)),
                      ),
                    )),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365 * 3)),
      lastDate: now,
      initialDateRange: filter.dateRange.days == 0 && filter.dateRange.from != null
          ? DateTimeRange(
              start: filter.dateRange.from!,
              end: filter.dateRange.to ?? now)
          : DateTimeRange(
              start: now.subtract(const Duration(days: 30)),
              end: now),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: _teal),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      onFilterChanged(filter.copyWith(
        dateRange: _DateRange(
          days: 0,
          from: picked.start,
          to: picked.end,
        ),
      ));
    }
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.active,
    required this.onTap,
    this.icon,
  });
  final String    label;
  final bool      active;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color:  active ? _teal.withValues(alpha: 0.15) : const Color(0xFF1A1A20),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? _teal : const Color(0xFF2D2D38),
            width: active ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 12,
                color: active ? _teal : _kSubtitle),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? _teal : _kLabel,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Analytics body
// ---------------------------------------------------------------------------
class _AnalyticsBody extends StatelessWidget {
  const _AnalyticsBody({
    required this.data,
    required this.filter,
    required this.touchedIndex,
    required this.drillCategory,
    required this.onTouch,
  });

  final AnalyticsData         data;
  final _AnalyticsFilter      filter;
  final int?                  touchedIndex;
  final String?               drillCategory;
  final ValueChanged<int?>    onTouch;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        // ── Vital Signs row (all modes) ──────────────────────────────
        _VitalSignsRow(data: data),
        const SizedBox(height: 16),

        if (filter.dataMode == _DataMode.balance) ...[
          // ── Balance Sheet ────────────────────────────────────
          _BalanceSheetCard(data: data),
          const SizedBox(height: 16),
          if (data.ivePeriods.isNotEmpty) ...[
            _SectionCard(
              title: 'analytics.income_vs_expense'.tr(),
              child: _IvEChart(
                  periods: data.ivePeriods, currency: data.currency),
            ),
            const SizedBox(height: 16),
          ],
          _SectionCard(
            title: 'analytics.net_position_trend'.tr(),
            child: data.netTrend.isEmpty
                ? _EmptyChartHint()
                : _NetTrendChart(
                    spots:    data.netTrend,
                    currency: data.currency,
                    spanDays: filter.dateRange.days == 0
                        ? data.netTrend.length
                        : filter.dateRange.days,
                  ),
          ),
        ] else if (filter.dataMode == _DataMode.income) ...[
          // ── Income breakdown card ──────────────────────────────
          _SpendingCard(
            data:         data,
            filter:       filter,
            touchedIndex: touchedIndex,
            onTouch:      onTouch,
            incomeMode:   true,
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'analytics.net_position_trend'.tr(),
            child: data.netTrend.isEmpty
                ? _EmptyChartHint()
                : _NetTrendChart(
                    spots:    data.netTrend,
                    currency: data.currency,
                    spanDays: filter.dateRange.days == 0
                        ? data.netTrend.length
                        : filter.dateRange.days,
                  ),
          ),
          const SizedBox(height: 16),
          _DrillDownList(
            expenses:      data.allExpenses,
            drillCategory: drillCategory,
            currency:      data.currency,
            incomeOnly:    true,
          ),
        ] else ...[
          // ── Spending breakdown card ──────────────────────────────
          _SpendingCard(
            data:         data,
            filter:       filter,
            touchedIndex: touchedIndex,
            onTouch:      onTouch,
            incomeMode:   false,
          ),
          const SizedBox(height: 16),
          if (data.ivePeriods.isNotEmpty) ...[
            _SectionCard(
              title: 'analytics.income_vs_expense'.tr(),
              child: _IvEChart(
                  periods: data.ivePeriods, currency: data.currency),
            ),
            const SizedBox(height: 16),
          ],
          _SectionCard(
            title: 'analytics.net_position_trend'.tr(),
            child: data.netTrend.isEmpty
                ? _EmptyChartHint()
                : _NetTrendChart(
                    spots:    data.netTrend,
                    currency: data.currency,
                    spanDays: filter.dateRange.days == 0
                        ? data.netTrend.length
                        : filter.dateRange.days,
                  ),
          ),
          const SizedBox(height: 16),
          _DrillDownList(
            expenses:      data.allExpenses,
            drillCategory: drillCategory,
            currency:      data.currency,
            incomeOnly:    false,
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Spending card — contains chart-type switcher + chart + side panels
// ---------------------------------------------------------------------------
class _SpendingCard extends StatelessWidget {
  const _SpendingCard({
    required this.data,
    required this.filter,
    required this.touchedIndex,
    required this.onTouch,
    this.incomeMode = false,
  });

  final AnalyticsData      data;
  final _AnalyticsFilter   filter;
  final int?               touchedIndex;
  final ValueChanged<int?> onTouch;
  final bool               incomeMode;

  @override
  Widget build(BuildContext context) {
    final totals = incomeMode ? data.incomeCategoryTotals : data.categoryTotals;
    final total  = incomeMode ? data.totalIncome : data.totalSpend;
    final title  = incomeMode
        ? 'analytics.income_breakdown'.tr()
        : 'analytics.spending_by_category'.tr();

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outlineVariant, width: 0.5),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row + chart type switcher
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    letterSpacing: 0.3, color: _kLabel,
                  ),
                ),
              ),
              _ChartTypeSwitcher(current: filter.chartType),
            ],
          ),
          const SizedBox(height: 16),

          // Chart
          if (totals.isEmpty)
            _EmptyChartHint()
          else
            _ChartArea(
              data:         data,
              chartType:    filter.chartType,
              touchedIndex: touchedIndex,
              onTouch:      onTouch,
              incomeMode:   incomeMode,
            ),

          // Legend
          if (totals.isNotEmpty) ...[
            const SizedBox(height: 16),
            _CategoryLegend(
              totals:       totals,
              total:        total,
              touchedIndex: touchedIndex,
            ),
          ],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chart-type switcher
// ---------------------------------------------------------------------------
class _ChartTypeSwitcher extends ConsumerWidget {
  const _ChartTypeSwitcher({required this.current});
  final _ChartType current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const types = [
      (_ChartType.donut, Icons.donut_large_outlined,  'Donut'),
      (_ChartType.pie,   Icons.pie_chart_outline,      'Pie'),
      (_ChartType.bar,   Icons.bar_chart_outlined,     'Bar'),
    ];
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A20),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2D2D38), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: types.map((t) {
          final isActive = current == t.$1;
          return GestureDetector(
            onTap: () {
              ref.read(_analyticsFilterProvider.notifier)
                  .update((f) => f.copyWith(chartType: t.$1));
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isActive ? _teal.withValues(alpha: 0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Icon(
                t.$2,
                size: 16,
                color: isActive ? _teal : _kSubtitle,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chart area — routes to the right chart type
// ---------------------------------------------------------------------------
class _ChartArea extends StatelessWidget {
  const _ChartArea({
    required this.data,
    required this.chartType,
    required this.touchedIndex,
    required this.onTouch,
    this.incomeMode = false,
  });

  final AnalyticsData      data;
  final _ChartType         chartType;
  final int?               touchedIndex;
  final ValueChanged<int?> onTouch;
  final bool               incomeMode;

  @override
  Widget build(BuildContext context) {
    switch (chartType) {
      case _ChartType.bar:
        return _BarChart(data: data, incomeMode: incomeMode);
      case _ChartType.pie:
        return _PieOrDonut(
          data: data, touchedIndex: touchedIndex,
          onTouch: onTouch, isDonut: false, incomeMode: incomeMode,
        );
      case _ChartType.donut:
        return _PieOrDonut(
          data: data, touchedIndex: touchedIndex,
          onTouch: onTouch, isDonut: true, incomeMode: incomeMode,
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Donut / Pie chart — thinner ring, side panels
// ---------------------------------------------------------------------------
class _PieOrDonut extends StatelessWidget {
  const _PieOrDonut({
    required this.data,
    required this.touchedIndex,
    required this.onTouch,
    required this.isDonut,
    this.incomeMode = false,
  });

  final AnalyticsData      data;
  final int?               touchedIndex;
  final ValueChanged<int?> onTouch;
  final bool               isDonut;
  final bool               incomeMode;

  @override
  Widget build(BuildContext context) {
    final entries  = (incomeMode
        ? data.incomeCategoryTotals
        : data.categoryTotals).entries.toList();
    final sections = List.generate(entries.length, (i) {
      final isTouched = i == touchedIndex;
      final color = _kPaletteColors[i % _kPaletteColors.length];
      final denom = incomeMode ? data.totalIncome : data.totalSpend;
      final pct = denom > Decimal.zero
          ? entries[i].value.toDouble() / denom.toDouble() * 100
          : 0.0;
      return PieChartSectionData(
        value:      entries[i].value.toDouble(),
        color:      color,
        radius:     isDonut ? (isTouched ? 46 : 38) : (isTouched ? 120 : 110),
        showTitle:  !isDonut && isTouched,
        title:      '${pct.toStringAsFixed(1)}%',
        titleStyle: const TextStyle(
          fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
        badgeWidget: null,
      );
    });

    final chart = PieChart(
      PieChartData(
        sections:        sections,
        centerSpaceRadius: isDonut ? 58 : 0,
        sectionsSpace:   isDonut ? 2 : 1,
        pieTouchData: PieTouchData(
          touchCallback: (event, response) {
            if (!event.isInterestedForInteractions ||
                response == null ||
                response.touchedSection == null) {
              onTouch(null);
              return;
            }
            final idx = response.touchedSection!.touchedSectionIndex;
            onTouch(idx < 0 ? null : idx);
          },
        ),
      ),
    );

    if (!isDonut) {
      return SizedBox(height: 220, child: chart);
    }

    // Donut layout: [Left panel] [Donut] [Right panel]
    final selectedEntry = (touchedIndex != null && touchedIndex! < entries.length)
        ? entries[touchedIndex!]
        : null;
    final denom2 = incomeMode ? data.totalIncome : data.totalSpend;

    return SizedBox(
      height: 200,
      child: Row(
        children: [
          // ── Left: total in base currency ────────────────────────────────
          Expanded(
            flex: 3,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  selectedEntry != null
                      ? categoryTr(selectedEntry.key)
                      : 'analytics.total'.tr(),
                  style: const TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: _kLabel,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  data.currency,
                  style: const TextStyle(
                    fontSize: 10, color: _kSubtitle),
                ),
                const SizedBox(height: 2),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    (selectedEntry?.value ?? denom2)
                        .toStringAsFixed(2),
                    style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.w800,
                      color: _teal,
                    ),
                  ),
                ),
                if (selectedEntry != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${denom2 > Decimal.zero ? (selectedEntry.value.toDouble() / denom2.toDouble() * 100).toStringAsFixed(1) : '0.0'}%',
                    style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: _kLabel,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // ── Donut ───────────────────────────────────────────────────────
          Expanded(
            flex: 4,
            child: chart,
          ),
          // ── Right: currency breakdown ────────────────────────────────────
          Expanded(
            flex: 3,
            child: data.currencyBreakdown.isEmpty
                ? const SizedBox.shrink()
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'analytics.currencies'.tr(),
                        style: const TextStyle(
                          fontSize: 10, color: _kSubtitle,
                          fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      ...data.currencyBreakdown.entries
                          .toList()
                          .take(4)
                          .map((e) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              e.key,
                              style: const TextStyle(
                                fontSize: 10, color: _kLabel,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              e.value.toStringAsFixed(2),
                              style: const TextStyle(
                                fontSize: 12, color: Colors.white70,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      )),
                      if (data.currencyBreakdown.length > 4)
                        Text(
                          '+${data.currencyBreakdown.length - 4} more',
                          style: const TextStyle(
                            fontSize: 10, color: _kSubtitle),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Bar chart
// ---------------------------------------------------------------------------
class _BarChart extends StatelessWidget {
  const _BarChart({required this.data, this.incomeMode = false});
  final AnalyticsData data;
  final bool          incomeMode;

  @override
  Widget build(BuildContext context) {
    final entries = (incomeMode
        ? data.incomeCategoryTotals
        : data.categoryTotals).entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return _EmptyChartHint();

    final maxVal = entries.first.value.toDouble();

    return Column(
      children: entries.asMap().entries.map((entry) {
        final i     = entry.key;
        final e     = entry.value;
        final color = _kPaletteColors[i % _kPaletteColors.length];
        final pct   = maxVal > 0 ? e.value.toDouble() / maxVal : 0.0;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: [
              SizedBox(
                width: 88,
                child: Text(
                  categoryTr(e.key),
                  style: const TextStyle(
                    fontSize: 11, color: _kLabel,
                    fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, constraints) => Stack(
                    children: [
                      Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        curve: Curves.easeOutCubic,
                        height: 20,
                        width: constraints.maxWidth * pct,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 60,
                child: Text(
                  e.value.toStringAsFixed(0),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    fontSize: 11, color: Colors.white70,
                    fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Category legend
// ---------------------------------------------------------------------------
class _CategoryLegend extends StatelessWidget {
  const _CategoryLegend({
    required this.totals,
    required this.total,
    required this.touchedIndex,
  });
  final Map<String, Decimal> totals;
  final Decimal              total;
  final int?                 touchedIndex;

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final entries = totals.entries.toList();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: List.generate(entries.length, (i) {
        final color    = _kPaletteColors[i % _kPaletteColors.length];
        final isActive = touchedIndex == null || touchedIndex == i;
        return AnimatedOpacity(
          opacity:  isActive ? 1.0 : 0.35,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: color.withValues(
                  alpha: touchedIndex == i ? 0.8 : 0.22)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7, height: 7,
                  decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(
                  categoryTr(entries[i].key),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Section card wrapper (for trend chart)
// ---------------------------------------------------------------------------
class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant, width: 0.5),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700,
              letterSpacing: 0.3, color: _kLabel,
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Net trend line chart
// ---------------------------------------------------------------------------
class _NetTrendChart extends StatelessWidget {
  const _NetTrendChart({
    required this.spots,
    required this.currency,
    required this.spanDays,
  });
  final List<FlSpot> spots;
  final String       currency;
  final int          spanDays;

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty) return const SizedBox.shrink();

    final maxY    = spots.map((s) => s.y).reduce(math.max);
    final minY    = spots.map((s) => s.y).reduce(math.min);
    final range   = (maxY - minY).abs();
    final padded  = (range * 0.15).clamp(1.0, double.infinity);

    // Smart x-axis interval
    final xInterval = spanDays <= 14 ? 1.0
        : spanDays <= 60  ? 7.0
        : spanDays <= 180 ? 14.0
        : 30.0;

    final todayLabel = 'analytics.today'.tr();
    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          minY: minY - padded,
          maxY: maxY + padded,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: range > 0 ? range / 4 : 1,
            getDrawingHorizontalLine: (_) => const FlLine(
              color: Color(0xFF1E293B), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                getTitlesWidget: (v, _) => Text(
                  _shortNum(v),
                  style: const TextStyle(
                    fontSize: 9, color: _kSubtitle),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: xInterval,
                getTitlesWidget: (v, _) {
                  final daysAgo = (spots.length - 1 - v.toInt());
                  if (daysAgo == 0) {
                    return Text(todayLabel,
                      style: const TextStyle(fontSize: 9, color: _kSubtitle));
                  }
                  return Text('${daysAgo}d',
                    style: const TextStyle(
                      fontSize: 9, color: _kSubtitle));
                },
              ),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1E293B),
              getTooltipItems: (spots) => spots.map((s) =>
                LineTooltipItem(
                  '$currency ${s.y.toStringAsFixed(2)}',
                  const TextStyle(
                    color: _teal, fontWeight: FontWeight.w700,
                    fontSize: 12),
                )).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots:              spots,
              isCurved:           true,
              curveSmoothness:    0.3,
              color:              _teal,
              barWidth:           2.5,
              isStrokeCapRound:   true,
              dotData:            const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    _teal.withValues(alpha: 0.2),
                    _teal.withValues(alpha: 0.0),
                  ],
                  begin: Alignment.topCenter,
                  end:   Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortNum(double v) {
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v.abs() >= 1000)    return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }
}

// ---------------------------------------------------------------------------
// Vital Signs row — Net Flow · Burn Rate · Top Category
// ---------------------------------------------------------------------------
class _VitalSignsRow extends StatelessWidget {
  const _VitalSignsRow({required this.data});
  final AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final isPositive = data.netFlow >= Decimal.zero;
    final flowColor  = isPositive ? _teal : _rose;
    final pctAbs     = data.netFlowPct.abs();
    final pctLabel   = pctAbs > 0
        ? 'analytics.vs_prev_pct'.tr(namedArgs: {'sign': isPositive ? '+' : '', 'pct': data.netFlowPct.toStringAsFixed(1)})
        : 'analytics.vs_prev_period'.tr();

    return Row(
      children: [
        _VitalCard(
          flex: 4,
          label: 'analytics.net_flow'.tr(),
          icon: isPositive ? Icons.trending_up : Icons.trending_down,
          iconColor: flowColor,
          value: '${isPositive ? '+' : ''}${data.netFlow.toStringAsFixed(0)}',
          valueCurrency: data.currency,
          valueColor: flowColor,
          sub: pctLabel,
          subColor: pctAbs > 0
              ? (isPositive ? _teal : _rose)
              : _kSubtitle,
        ),
        const SizedBox(width: 8),
        _VitalCard(
          flex: 3,
          label: 'analytics.burn_rate'.tr(),
          icon: Icons.local_fire_department_outlined,
          iconColor: _orange,
          value: data.burnRate.toStringAsFixed(1),
          valueCurrency: data.currency,
          valueColor: _orange,
          sub: 'analytics.per_day'.tr(),
          subColor: _kSubtitle,
        ),
        const SizedBox(width: 8),
        _VitalCard(
          flex: 4,
          label: 'analytics.top_category'.tr(),
          icon: Icons.star_outline_rounded,
          iconColor: _gold,
          value: data.topCategory.isEmpty ? '—' : categoryTr(data.topCategory),
          valueCurrency: null,
          valueColor: Colors.white,
          sub: data.topCategoryPct > 0
              ? 'analytics.pct_of_spend'.tr(namedArgs: {'pct': data.topCategoryPct.toStringAsFixed(1)})
              : '',
          subColor: _kSubtitle,
        ),
      ],
    );
  }
}

class _VitalCard extends StatelessWidget {
  const _VitalCard({
    required this.flex,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.valueCurrency,
    required this.valueColor,
    required this.sub,
    required this.subColor,
  });
  final int     flex;
  final String  label;
  final IconData icon;
  final Color   iconColor;
  final String  value;
  final String? valueCurrency;
  final Color   valueColor;
  final String  sub;
  final Color   subColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      flex: flex,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.colorScheme.outlineVariant, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 13, color: iconColor),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w600,
                      color: _kSubtitle, letterSpacing: 0.3),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (valueCurrency != null)
              Text(
                valueCurrency!,
                style: const TextStyle(
                  fontSize: 9, color: _kLabel),
              ),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w800,
                  color: valueColor),
              ),
            ),
            if (sub.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                sub,
                style: TextStyle(fontSize: 9, color: subColor),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Income vs Expense grouped bar chart
// ---------------------------------------------------------------------------
class _IvEChart extends StatelessWidget {
  const _IvEChart({required this.periods, required this.currency});
  final List<IvEPeriod> periods;
  final String          currency;

  @override
  Widget build(BuildContext context) {
    if (periods.isEmpty) return _EmptyChartHint();

    final maxVal = periods
        .expand((p) => [p.income.toDouble(), p.expense.toDouble()])
        .fold(0.0, math.max);
    if (maxVal == 0) return _EmptyChartHint();

    final groups = periods.asMap().entries.map((entry) {
      final i = entry.key;
      final p = entry.value;
      return BarChartGroupData(
        x: i,
        barsSpace: 3,
        barRods: [
          BarChartRodData(
            toY: p.income.toDouble(),
            color: _teal,
            width: 8,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
          BarChartRodData(
            toY: p.expense.toDouble(),
            color: _violet,
            width: 8,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
          ),
        ],
      );
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Legend
        Row(
          children: [
            _IvELegendDot(color: _teal,   label: 'Income'),
            const SizedBox(width: 14),
            _IvELegendDot(color: _violet, label: 'Expense'),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              maxY: maxVal * 1.2,
              barGroups: groups,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => const FlLine(
                  color: Color(0xFF1E293B), strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (v, _) => Text(
                      _shortNum(v),
                      style: const TextStyle(
                        fontSize: 9, color: _kSubtitle),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, _) {
                      final idx = v.toInt();
                      if (idx < 0 || idx >= periods.length) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          periods[idx].label,
                          style: const TextStyle(
                            fontSize: 9, color: _kSubtitle),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF1E293B),
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final label = rodIndex == 0 ? 'Income' : 'Expense';
                    return BarTooltipItem(
                      '$label\n$currency ${rod.toY.toStringAsFixed(2)}',
                      TextStyle(
                        color: rodIndex == 0 ? _teal : _violet,
                        fontWeight: FontWeight.w700,
                        fontSize: 11,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _shortNum(double v) {
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v.abs() >= 1000)    return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }
}

class _IvELegendDot extends StatelessWidget {
  const _IvELegendDot({required this.color, required this.label});
  final Color  color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8, height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label,
          style: const TextStyle(fontSize: 11, color: _kLabel,
              fontWeight: FontWeight.w500)),
    ],
  );
}

// ---------------------------------------------------------------------------
// Category drill-down transaction list
// ---------------------------------------------------------------------------
class _DrillDownList extends StatelessWidget {
  const _DrillDownList({
    required this.expenses,
    required this.drillCategory,
    required this.currency,
    this.incomeOnly = false,
  });
  final List<AnalyticsRow> expenses;
  final String?            drillCategory;
  final String             currency;
  final bool               incomeOnly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Filter by mode first, then by drillCategory if set
    final modeFiltered = incomeOnly
        ? expenses.where((e) => e.isIncome).toList()
        : expenses.where((e) => !e.isIncome).toList();
    final shown = drillCategory != null
        ? modeFiltered.where((e) {
            final cat = e.category.isNotEmpty ? e.category : (incomeOnly ? 'Income' : 'Other');
            return cat == drillCategory;
          }).toList()
        : modeFiltered;

    if (shown.isEmpty) return const SizedBox.shrink();

    // Sort newest first
    final sorted = [...shown]..sort((a, b) {
        final da = DateTime.tryParse(a.createdAt ?? '') ?? DateTime(2000);
        final db = DateTime.tryParse(b.createdAt ?? '') ?? DateTime(2000);
        return db.compareTo(da);
      });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Row(
            children: [
              Text(
                drillCategory != null
                    ? drillCategory!
                    : 'analytics.all_transactions'.tr(),
                style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700,
                  color: _kLabel, letterSpacing: 0.3),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: _teal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${sorted.length}',
                  style: const TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, color: _teal),
                ),
              ),
            ],
          ),
        ),
        ...sorted.take(30).map((e) {
          final isIncome  = e.isIncome;
          final amtStr    = e.originalAmount ?? e.amount;
          final ccy       = e.originalCurrency ?? e.currency;
          final amt       = double.tryParse(amtStr) ?? 0;
          final sign      = isIncome ? '+' : '-';
          final color     = isIncome ? _teal : _rose;
          final cat       = e.category.isNotEmpty ? e.category : 'Other';
          final dateStr   = e.createdAt;
          final date      = dateStr != null ? DateTime.tryParse(dateStr) : null;
          final dateLabel = date != null
              ? DateFormat('d MMM').format(date.toLocal())
              : '';

          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: theme.colorScheme.outlineVariant, width: 0.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(
                    isIncome
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    size: 15, color: color,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.description.isNotEmpty ? e.description : cat,
                        style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600,
                          color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        cat,
                        style: const TextStyle(
                          fontSize: 11, color: _kSubtitle),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$sign$ccy ${amt.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700,
                        color: color),
                    ),
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontSize: 10, color: _kSubtitle),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
        if (sorted.length > 30)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 8),
            child: Text(
              '+${sorted.length - 30} more transactions',
              style: const TextStyle(fontSize: 12, color: _kSubtitle),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Balance Sheet card
// ---------------------------------------------------------------------------
class _BalanceSheetCard extends StatelessWidget {
  const _BalanceSheetCard({required this.data});
  final AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    final theme     = Theme.of(context);
    final isPos     = data.netFlow >= Decimal.zero;
    final netColor  = isPos ? _teal : _rose;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant, width: 0.5),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Balance Sheet',
            style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700,
              letterSpacing: 0.3, color: _kLabel),
          ),
          const SizedBox(height: 16),
          _BSRow(
            label: 'Total Income',
            value: data.totalIncome,
            currency: data.currency,
            color: _teal,
            icon: Icons.arrow_downward_rounded,
          ),
          const SizedBox(height: 8),
          _BSRow(
            label: 'Total Expenses',
            value: data.totalSpend,
            currency: data.currency,
            color: _rose,
            icon: Icons.arrow_upward_rounded,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Container(
              height: 1,
              color: theme.colorScheme.outlineVariant,
            ),
          ),
          _BSRow(
            label: 'Net Position',
            value: data.netFlow.abs(),
            currency: data.currency,
            color: netColor,
            icon: isPos ? Icons.trending_up : Icons.trending_down,
            prefix: isPos ? '+' : '-',
            bold: true,
          ),
          if (data.burnRate > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.local_fire_department_outlined,
                    size: 13, color: _orange),
                const SizedBox(width: 6),
                Text(
                  'analytics.burn_rate_detail'.tr(namedArgs: {'currency': data.currency, 'rate': data.burnRate.toStringAsFixed(2)}),
                  style: const TextStyle(
                    fontSize: 11, color: _kLabel),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _BSRow extends StatelessWidget {
  const _BSRow({
    required this.label,
    required this.value,
    required this.currency,
    required this.color,
    required this.icon,
    this.prefix = '',
    this.bold   = false,
  });
  final String  label;
  final Decimal value;
  final String  currency;
  final Color   color;
  final IconData icon;
  final String  prefix;
  final bool    bold;

  @override
  Widget build(BuildContext context) {
    final weight = bold ? FontWeight.w800 : FontWeight.w600;
    return Row(
      children: [
        Container(
          width: 28, height: 28,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: color),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13, fontWeight: weight, color: _kLabel),
          ),
        ),
        Text(
          '$prefix$currency ${value.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 14, fontWeight: weight, color: color),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------
class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        Opacity(
          opacity: 0.06,
          child: SvgPicture.asset('assets/icon_no_back.svg', width: 260),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bar_chart_outlined, size: 52, color: _teal),
            const SizedBox(height: 16),
            Text(
              'analytics.no_data'.tr(),
              style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700,
                color: _kLabel),
            ),
            const SizedBox(height: 8),
            Text(
              'Add expenses to see your spending insights.',
              style: const TextStyle(fontSize: 13, color: _kSubtitle),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => GoRouter.of(context).push('/add-expense'),
              icon:  const Icon(Icons.add, size: 18),
              label: Text('analytics.start_tracking'.tr()),
              style: FilledButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(
                  horizontal: 28, vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Empty chart hint
// ---------------------------------------------------------------------------
class _EmptyChartHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: Center(
        child: Text(
          'analytics.no_data'.tr(),
          style: const TextStyle(fontSize: 13, color: _kSubtitle),
        ),
      ),
    );
  }
}

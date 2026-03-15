import 'dart:math' as math;

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../data/models/expense_model.dart';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const _teal    = Color(0xFF00D9B0);
const _gold    = Color(0xFFD4AF37);
const _rose    = Color(0xFFF43F5E);
const _violet  = Color(0xFF8B5CF6);
const _sky     = Color(0xFF0EA5E9);
const _orange  = Color(0xFFF97316);
const _lime    = Color(0xFF84CC16);
const _pink    = Color(0xFFEC4899);

const _kPaletteColors = [
  _teal, _gold, _rose, _violet, _sky, _orange, _lime, _pink,
  Color(0xFF14B8A6), Color(0xFFEAB308), Color(0xFF6366F1),
];

// ---------------------------------------------------------------------------
// Data model
// ---------------------------------------------------------------------------
class AnalyticsData {
  const AnalyticsData({
    required this.categoryTotals,
    required this.netTrend,
    required this.totalSpend,
    required this.currency,
  });
  final Map<String, double> categoryTotals;  // category → amount (expenses only)
  final List<FlSpot>        netTrend;         // day offset → net position
  final double              totalSpend;
  final String              currency;
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------
final analyticsDataProvider = FutureProvider<AnalyticsData>((ref) async {
  final baseCurrency = await ref.watch(baseCurrencyProvider.future);

  // Pull all expenses
  final personal = await ref.watch(personalExpensesProvider.future);
  final recent   = await ref.watch(recentExpensesProvider.future);

  final all = [...personal, ...recent];

  // De-duplicate by ID
  final seen  = <String>{};
  final dedup = <ExpenseModel>[];
  for (final e in all) {
    if (seen.add(e.id)) dedup.add(e);
  }

  // ── Category totals (expenses only, last 30 days) ──────────────────────
  final now    = DateTime.now();
  final cutoff = now.subtract(const Duration(days: 30));

  final categoryMap = <String, double>{};
  for (final e in dedup) {
    if (e.isIncome) continue;
    final dateStr = e.createdAt;
    if (dateStr == null) continue;
    final date = DateTime.tryParse(dateStr);
    if (date == null || date.isBefore(cutoff)) continue;
    final amt = (Decimal.tryParse(e.amount) ?? Decimal.zero).toDouble();
    final cat = e.category.isNotEmpty ? e.category : 'Other';
    categoryMap[cat] = (categoryMap[cat] ?? 0) + amt;
  }

  // Sort descending, keep top 8 then bucket rest as "Other"
  final sorted = categoryMap.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final Map<String, double> topCats = {};
  double otherTotal = 0;
  for (int i = 0; i < sorted.length; i++) {
    if (i < 8) {
      topCats[sorted[i].key] = sorted[i].value;
    } else {
      otherTotal += sorted[i].value;
    }
  }
  if (otherTotal > 0) topCats['Other'] = otherTotal;

  final totalSpend = topCats.values.fold(0.0, (a, b) => a + b);

  // ── 30-day net trend ───────────────────────────────────────────────────
  // Build daily net balance (income − spend) rolling forward
  final dailyNet = List.filled(30, 0.0);
  for (final e in dedup) {
    final dateStr = e.createdAt;
    if (dateStr == null) continue;
    final date = DateTime.tryParse(dateStr);
    if (date == null || date.isBefore(cutoff)) continue;
    final daysAgo = now.difference(date).inDays;
    if (daysAgo < 0 || daysAgo >= 30) continue;
    final idx = 29 - daysAgo;
    final amt = (Decimal.tryParse(e.amount) ?? Decimal.zero).toDouble();
    dailyNet[idx] += e.isIncome ? amt : -amt;
  }

  // Convert to cumulative running total
  double running = 0;
  final spots = <FlSpot>[];
  for (int i = 0; i < 30; i++) {
    running += dailyNet[i];
    spots.add(FlSpot(i.toDouble(), running));
  }

  return AnalyticsData(
    categoryTotals: topCats,
    netTrend: spots,
    totalSpend: totalSpend,
    currency: baseCurrency,
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
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    final theme        = Theme.of(context);
    final analyticsAsync = ref.watch(analyticsDataProvider);

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
      ),
      body: analyticsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(
          child: Text('common.error'.tr(),
            style: TextStyle(color: theme.colorScheme.error)),
        ),
        data: (data) {
          if (data.totalSpend == 0 && data.netTrend.every((s) => s.y == 0)) {
            return _EmptyState();
          }
          return _AnalyticsBody(
            data: data,
            touchedIndex: _touchedIndex,
            onTouch: (i) => setState(() => _touchedIndex = i),
          );
        },
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
    required this.touchedIndex,
    required this.onTouch,
  });

  final AnalyticsData data;
  final int? touchedIndex;
  final ValueChanged<int?> onTouch;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        // ── Donut chart: spending by category ─────────────────────────────
        _SectionCard(
          title: 'analytics.spending_by_category'.tr(),
          child: data.categoryTotals.isEmpty
              ? _EmptyChartHint()
              : _DonutChart(
                  data: data,
                  touchedIndex: touchedIndex,
                  onTouch: onTouch,
                ),
        ),
        const SizedBox(height: 16),

        // ── Legend ─────────────────────────────────────────────────────────
        if (data.categoryTotals.isNotEmpty)
          _CategoryLegend(data: data, touchedIndex: touchedIndex),

        const SizedBox(height: 16),

        // ── Line chart: net position trend ─────────────────────────────────
        _SectionCard(
          title: 'analytics.net_position_trend'.tr(),
          child: data.netTrend.isEmpty
              ? _EmptyChartHint()
              : _NetTrendChart(spots: data.netTrend, currency: data.currency),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section card wrapper
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
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 0.5),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: Color(0xFF94A3B8),
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
// Donut chart
// ---------------------------------------------------------------------------
class _DonutChart extends StatelessWidget {
  const _DonutChart({
    required this.data,
    required this.touchedIndex,
    required this.onTouch,
  });

  final AnalyticsData data;
  final int? touchedIndex;
  final ValueChanged<int?> onTouch;

  @override
  Widget build(BuildContext context) {
    final entries = data.categoryTotals.entries.toList();
    final sections = List.generate(entries.length, (i) {
      final isTouched = i == touchedIndex;
      final color = _kPaletteColors[i % _kPaletteColors.length];
      final pct = data.totalSpend > 0
          ? (entries[i].value / data.totalSpend * 100)
          : 0.0;
      return PieChartSectionData(
        value: entries[i].value,
        color: color,
        radius: isTouched ? 72 : 58,
        showTitle: isTouched,
        title: '${pct.toStringAsFixed(1)}%',
        titleStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Colors.white,
        ),
        badgeWidget: null,
      );
    });

    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sections: sections,
              centerSpaceRadius: 55,
              sectionsSpace: 3,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  if (!event.isInterestedForInteractions ||
                      response == null ||
                      response.touchedSection == null) {
                    onTouch(null);
                    return;
                  }
                  onTouch(response.touchedSection!.touchedSectionIndex);
                },
              ),
            ),
          ),
          // Center label
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                touchedIndex != null
                    ? data.categoryTotals.keys.elementAt(touchedIndex!)
                    : 'analytics.total'.tr(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF94A3B8),
                ),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                touchedIndex != null
                    ? '${data.currency} ${data.categoryTotals.values.elementAt(touchedIndex!).toStringAsFixed(2)}'
                    : '${data.currency} ${data.totalSpend.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _teal,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category legend
// ---------------------------------------------------------------------------
class _CategoryLegend extends StatelessWidget {
  const _CategoryLegend({required this.data, required this.touchedIndex});
  final AnalyticsData data;
  final int? touchedIndex;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = data.categoryTotals.entries.toList();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List.generate(entries.length, (i) {
        final color = _kPaletteColors[i % _kPaletteColors.length];
        final isActive = touchedIndex == null || touchedIndex == i;
        return AnimatedOpacity(
          opacity: isActive ? 1.0 : 0.4,
          duration: const Duration(milliseconds: 200),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: color.withValues(alpha: touchedIndex == i ? 0.8 : 0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: BoxDecoration(
                    color: color, shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  entries[i].key,
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
// Net trend line chart
// ---------------------------------------------------------------------------
class _NetTrendChart extends StatelessWidget {
  const _NetTrendChart({required this.spots, required this.currency});
  final List<FlSpot> spots;
  final String currency;

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty) return const SizedBox.shrink();

    final maxY = spots.map((s) => s.y).reduce(math.max);
    final minY = spots.map((s) => s.y).reduce(math.min);
    final range = (maxY - minY).abs();
    final paddedMax = maxY + (range * 0.15).clamp(1, double.infinity);
    final paddedMin = minY - (range * 0.15).clamp(1, double.infinity);

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minX: 0, maxX: 29,
          minY: paddedMin, maxY: paddedMax,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: range > 0 ? range / 4 : 1,
            getDrawingHorizontalLine: (_) => FlLine(
              color: const Color(0xFF1E293B),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (v, meta) => Text(
                  v.toStringAsFixed(0),
                  style: const TextStyle(
                    fontSize: 9, color: Color(0xFF64748B),
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 7,
                getTitlesWidget: (v, meta) {
                  final daysAgo = (29 - v.toInt());
                  if (daysAgo == 0) return const Text('Today',
                    style: TextStyle(fontSize: 9, color: Color(0xFF64748B)));
                  if (daysAgo % 7 == 0) return Text('${daysAgo}d',
                    style: const TextStyle(fontSize: 9, color: Color(0xFF64748B)));
                  return const SizedBox.shrink();
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
              getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
                '$currency ${s.y.toStringAsFixed(2)}',
                const TextStyle(
                  color: _teal,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              )).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: _teal,
              barWidth: 2.5,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    _teal.withValues(alpha: 0.22),
                    _teal.withValues(alpha: 0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
        ),
      ),
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
        // Watermark
        Opacity(
          opacity: 0.06,
          child: SvgPicture.asset(
            'assets/icon_no_back.svg',
            width: 260,
          ),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.bar_chart_outlined, size: 52, color: _teal),
            const SizedBox(height: 16),
            Text(
              'analytics.no_data'.tr(),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF94A3B8),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add expenses to see your spending insights.',
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF64748B),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: () => GoRouter.of(context).push('/add-expense'),
              icon: const Icon(Icons.add, size: 18),
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
// Empty chart hint (when only one chart has no data)
// ---------------------------------------------------------------------------
class _EmptyChartHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 100,
      child: Center(
        child: Text(
          'analytics.no_data'.tr(),
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}

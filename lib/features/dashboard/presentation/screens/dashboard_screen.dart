import 'dart:math' as math;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/app_top_button.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../analytics/presentation/screens/analytics_screen.dart'
    show analyticsDataProvider, AnalyticsData;

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const _teal      = Color(0xFF00D9B0);
const _purple    = Color(0xFF8B5CF6);
const _orange    = Color(0xFFFF8C42);
const _tealDim   = Color(0x1800D9B0);
const _purpleDim = Color(0x188B5CF6);

// Analytics palette (matches analytics_screen.dart)
const _aTeal   = Color(0xFF14B8A6);
const _aGold   = Color(0xFFD4AF37);
const _aRose   = Color(0xFFF43F5E);
const _aViolet = Color(0xFF8B5CF6);
const _aSky    = Color(0xFF0EA5E9);
const _aOrange = Color(0xFFF97316);
const _aLime   = Color(0xFF84CC16);
const _aPink   = Color(0xFFEC4899);
const _kSubtitle = Color(0xFF64748B);
const _kLabel    = Color(0xFF94A3B8);

const _kPaletteColors = [
  _aTeal, _aGold, _aRose, _aViolet, _aSky, _aOrange, _aLime, _aPink,
];

// Sentinel values returned by _aiInsightProvider to distinguish UI states.
const _kAiEmpty   = '__empty__';   // no transactions yet
const _kAiOffline = '__offline__'; // no connectivity

// AI insight provider — cached result keyed to the current user session.
// Invalidate on manual refresh or app re-open.
final _aiInsightProvider = FutureProvider.autoDispose<String>((ref) async {
  final analyticsData = await ref.watch(analyticsDataProvider.future);

  // Empty state: no expenses and no income — skip the network call entirely.
  if (analyticsData.allExpenses.isEmpty &&
      analyticsData.totalIncome == 0 &&
      analyticsData.totalSpend  == 0) {
    return _kAiEmpty;
  }

  // Connectivity check: if offline return distinct sentinel immediately.
  if (!kIsWeb) {
    final conn = await Connectivity().checkConnectivity();
    if (conn.every((r) => r == ConnectivityResult.none)) {
      return _kAiOffline;
    }
  }

  final client = Supabase.instance.client;
  final topCats = analyticsData.categoryTotals.entries
      .toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final topCatsStr = topCats
      .take(5)
      .map((e) => '${e.key}: \$${e.value.toStringAsFixed(2)}')
      .join(', ');

  final recentRows = analyticsData.allExpenses
      .take(20)
      .map((e) =>
          '${e.createdAt?.substring(0, 10) ?? ''} ${e.category} ${e.currency} ${e.amount}')
      .join('\n');

  try {
    final res = await client.functions.invoke(
      'ai-analyst',
      body: {
        'message': 'Give me a concise 1-sentence financial insight about my spending this month.',
        'history': <Map<String, String>>[],
        'context': {
          'totalSpending':  analyticsData.totalSpend,
          'dailyBurn':      analyticsData.burnRate,
          'totalIncome':    analyticsData.totalIncome,
          'net':            analyticsData.netFlow,
          'topCategories':  topCatsStr,
          'recentRows':     recentRows,
        },
      },
    );
    final data = res.data as Map<String, dynamic>?;
    final structured = data?['structured'] as Map<String, dynamic>?;
    return (structured?['summary'] as String?)
        ?? (data?['reply'] as String?)
        ?? '';
  } catch (error, stackTrace) {
    // ACT-crash: structured breadcrumb — fatal:false means degraded UX, not a crash.
    await FirebaseCrashlytics.instance.recordError(
      error,
      stackTrace,
      reason: 'AI insight provider failure',
      information: [
        DiagnosticsProperty<String>('stage', 'supabase_edge_fn_invoke'),
        DiagnosticsProperty<String>('timestamp', DateTime.now().toIso8601String()),
      ],
      fatal: false,
    );
    // Network / Supabase error — return empty so the error state shows.
    rethrow;
  }
});

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncServiceProvider).performFullSync().then((_) {
        if (mounted) {
          ref.invalidate(masterBalanceProvider);
          ref.invalidate(walletBalanceProvider);
          ref.invalidate(balanceSummaryProvider);
          ref.invalidate(_aiInsightProvider);
        }
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme        = Theme.of(context);
    final masterAsync  = ref.watch(masterBalanceProvider);
    final groupsAsync  = ref.watch(myGroupsProvider);
    final walletAsync  = ref.watch(walletBalanceProvider);
    final analyticsAsync = ref.watch(analyticsDataProvider);
    final aiAsync      = ref.watch(_aiInsightProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'dashboard.title'.tr(),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.3),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        automaticallyImplyLeading: false,
        actions: [
          AppTopButton(
            tooltip: 'common.add_friend'.tr(),
            icon: Icons.person_add_outlined,
            onPressed: () {
              HapticUtils.lightTap();
              context.push(AppRouter.inviteFriend);
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        color: _teal,
        onRefresh: () async {
          HapticUtils.lightTap();
          await ref.read(syncServiceProvider).performFullSync();
          if (!mounted) return;
          ref.invalidate(masterBalanceProvider);
          ref.invalidate(walletBalanceProvider);
          ref.invalidate(balanceSummaryProvider);
          ref.invalidate(myGroupsProvider);
          ref.invalidate(_aiInsightProvider);
        },
        child: ListView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 96 + MediaQuery.of(context).padding.bottom),
          children: [
            // ── WIDGET 1: Master Net Worth Hero ─────────────────────────────
            masterAsync.when(
              skipLoadingOnReload: true,
              data:    (m) => _MasterNetWorthHero(master: m),
              loading: () => const _MasterNetWorthHero.loading(),
              error:   (_, _) => const _MasterNetWorthHero.error(),
            ),
            const SizedBox(height: 20),

            // ── Section header ───────────────────────────────────────────────
            Text(
              'dashboard.your_finances'.tr().toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),

            // ── WIDGET 2: Wallet Preview ────────────────────────────────────
            _NavCard(
              icon: Icons.account_balance_wallet_outlined,
              title: 'dashboard.personal_wallet'.tr(),
              subtitle: 'dashboard.cash_position'.tr(),
              accentColor: _purple,
              accentDim: _purpleDim,
              valueAsync: walletAsync,
              valuePrefix: '',
              onTap: () { HapticUtils.lightTap(); context.go('/wallet'); },
            ),
            const SizedBox(height: 10),

            // ── WIDGET 3: Groups Preview ─────────────────────────────────────
            _NavCard(
              icon: Icons.group_outlined,
              title: 'dashboard.shared_expenses'.tr(),
              subtitle: 'dashboard.net_group_position'.tr(),
              accentColor: _teal,
              accentDim: _tealDim,
              valueAsync: masterAsync.whenData((m) {
                final net = m.sharedNet;
                final sign = net >= Decimal.zero ? '+' : '-';
                return '$sign${m.currency} ${(net.abs()).toStringAsFixed(2)}';
              }),
              valuePrefix: '',
              groupCount: groupsAsync.valueOrNull?.length,
              onTap: () { HapticUtils.lightTap(); context.go('/groups'); },
            ),

            const SizedBox(height: 24),

            // ── Section header: Trends ───────────────────────────────────────
            Text(
              'dashboard.trends'.tr().toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),

            // ── WIDGET 4: SetAll AI Insight Card ─────────────────────────────
            _AiInsightCard(aiAsync: aiAsync),
            const SizedBox(height: 10),

            // ── WIDGET 5: Compact Analytics Summary ──────────────────────────
            analyticsAsync.when(
              skipLoadingOnReload: true,
              data: (data) => data.totalSpend == 0 && data.totalIncome == 0
                  ? const SizedBox.shrink()
                  : _CompactAnalyticsSection(data: data),
              loading: () => const _AnalyticsLoadingCard(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget 1 — Master Net Worth Hero
// ---------------------------------------------------------------------------
class _MasterNetWorthHero extends StatelessWidget {
  const _MasterNetWorthHero({required this.master})
      : _loading = false, _error = false;
  const _MasterNetWorthHero.loading()
      : master = null, _loading = true, _error = false;
  const _MasterNetWorthHero.error()
      : master = null, _loading = false, _error = true;

  final MasterBalance? master;
  final bool _loading;
  final bool _error;

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final isPos   = master?.netWorthPositive ?? true;
    final accent  = isPos ? _teal : _orange;
    final netStr  = master == null
        ? '—'
        : '${master!.currency} ${master!.netWorth.abs().toStringAsFixed(2)}';

    final isDark    = theme.brightness == Brightness.dark;
    final scaffold   = theme.scaffoldBackgroundColor;
    final isDesktop  = !isDark && (scaffold.r * 255.0).round() < 215 && (scaffold.g * 255.0).round() < 225 && (scaffold.b * 255.0).round() < 235;
    final gradStart  = isDark    ? theme.colorScheme.surfaceContainerHigh
                     : isDesktop ? const Color(0xFFFFFFFF)  // white — matches GlassCard
                     :             const Color(0xFFF8FAFC); // Slate-50 (mobile)
    final gradEnd    = isDark    ? theme.colorScheme.surfaceContainerHighest
                     : isDesktop ? const Color(0xFFF1F5F9)  // Slate-100 subtle gradient end
                     :             const Color(0xFFE2E8F0); // Slate-200 (mobile)

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [gradStart, gradEnd],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.18),
            blurRadius: 32,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(color: accent.withValues(alpha: 0.22), width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              width: 8, height: 8,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              'dashboard.net_worth_label'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: 0.4,
              ),
            ),
          ]),
          const SizedBox(height: 8),
          if (_loading)
            const SizedBox(height: 36, child: LinearProgressIndicator())
          else
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                _error ? '—' : (isPos ? netStr : '-$netStr'),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 32,
                  letterSpacing: -1,
                  color: _error ? theme.colorScheme.onSurfaceVariant : accent,
                ),
                maxLines: 1,
              ),
            ),
          const SizedBox(height: 4),
          Text(
            isPos ? 'dashboard.in_the_green'.tr() : 'dashboard.in_the_red'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 16),
          if (!_loading && !_error && master != null) ...[
            Row(children: [
              Expanded(child: _StatPill(
                label: 'dashboard.wallet_cash_label'.tr(),
                value: '${master!.currency} ${master!.walletCash.toStringAsFixed(2)}',
                color: _purple,
                bgColor: _purpleDim,
              )),
              const SizedBox(width: 8),
              Expanded(child: _StatPill(
                label: 'dashboard.shared_balance'.tr(),
                value: '${master!.sharedNet >= Decimal.zero ? '+' : ''}${master!.currency} ${master!.sharedNet.toStringAsFixed(2)}',
                color: _teal,
                bgColor: _tealDim,
              )),
            ]),
          ],
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.color,
    required this.bgColor,
  });

  final String label;
  final String value;
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color, fontWeight: FontWeight.w600, fontSize: 10),
            overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(value,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
            overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget 4 — SetAll AI Insight Card
// ---------------------------------------------------------------------------
class _AiInsightCard extends ConsumerStatefulWidget {
  const _AiInsightCard({required this.aiAsync});
  final AsyncValue<String> aiAsync;

  @override
  ConsumerState<_AiInsightCard> createState() => _AiInsightCardState();
}

class _AiInsightCardState extends ConsumerState<_AiInsightCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _alpha;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
    _alpha = Tween<double>(begin: 0.06, end: 0.22).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
    ref.listenManual(_aiInsightProvider, (prev, next) {
      if (next is AsyncData && next.value != null && next.value!.isNotEmpty &&
          prev is! AsyncData) {
        HapticUtils.success();
      }
    });
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final aiAsync = widget.aiAsync;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _aTeal.withValues(alpha: 0.12),
            _aViolet.withValues(alpha: 0.08),
          ],
        ),
        border: Border.all(color: _aTeal.withValues(alpha: 0.25), width: 1),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: _aTeal.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.auto_awesome, color: _aTeal, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SetAll AI',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _aTeal,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 4),
                // Pre-allocate a fixed content area (3 lines ≈ 56px) so the
                // card never changes height when transitioning loading → data.
                SizedBox(
                  // 3 lines at fontSize 13 * height 1.4 ≈ 55px
                  height: 55,
                  child: aiAsync.when(
                    skipLoadingOnReload: true,
                    data: (insight) {
                      // Distinct sentinel states
                      if (insight == _kAiEmpty) {
                        return Text(
                          'dashboard.ai_empty_state'.tr(),
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        );
                      }
                      if (insight == _kAiOffline) {
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.wifi_off_rounded,
                                size: 14,
                                color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'dashboard.ai_offline'.tr(),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.colorScheme.onSurfaceVariant,
                                  height: 1.4,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        );
                      }
                      if (insight.isEmpty) {
                        return Text(
                          'dashboard.ai_no_data'.tr(),
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        );
                      }
                      return Text(
                        insight,
                        style: TextStyle(
                          fontSize: 13,
                          color: theme.colorScheme.onSurface,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                    loading: () => AnimatedBuilder(
                      animation: _alpha,
                      builder: (_, child) => Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            height: 11, width: double.infinity,
                            decoration: BoxDecoration(
                              color: _aTeal.withValues(alpha: _alpha.value),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Container(
                            height: 11, width: double.infinity,
                            decoration: BoxDecoration(
                              color: _aTeal.withValues(alpha: _alpha.value * 0.8),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                          const SizedBox(height: 7),
                          Container(
                            height: 11, width: 140,
                            decoration: BoxDecoration(
                              color: _aTeal.withValues(alpha: _alpha.value * 0.55),
                              borderRadius: BorderRadius.circular(6),
                            ),
                          ),
                        ],
                      ),
                    ),
                    error: (_, e) => Text(
                      'dashboard.ai_unavailable'.tr(),
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
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
// Widget 5 — Compact Analytics Section (Charts merged into Dashboard)
// ---------------------------------------------------------------------------
class _CompactAnalyticsSection extends StatelessWidget {
  const _CompactAnalyticsSection({required this.data});
  final AnalyticsData data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Spending by Category ─────────────────────────────────────────
        if (data.categoryTotals.isNotEmpty) ...[
          _DashboardSectionCard(
            title: 'analytics.spending_by_category'.tr(),
            child: _DashboardDonutChart(
              categoryTotals: data.categoryTotals,
              totalSpend: data.totalSpend,
              currency: data.currency,
            ),
          ),
          const SizedBox(height: 10),
        ],

        // ── Net Trend ────────────────────────────────────────────────────
        if (data.netTrend.length > 1) ...[
          _DashboardSectionCard(
            title: 'analytics.net_position_trend'.tr(),
            child: _DashboardTrendChart(
              spots: data.netTrend,
              currency: data.currency,
              spanDays: 30,
            ),
          ),
          const SizedBox(height: 10),
        ],

        // ── Quick stats row ──────────────────────────────────────────────
        Row(
          children: [
            Expanded(
              child: _QuickStatTile(
                label: 'analytics.spending'.tr(),
                value: '${data.currency} ${data.totalSpend.toStringAsFixed(0)}',
                color: _aRose,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickStatTile(
                label: 'analytics.income'.tr(),
                value: '${data.currency} ${data.totalIncome.toStringAsFixed(0)}',
                color: _aTeal,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _QuickStatTile(
                label: 'analytics.daily_burn'.tr(),
                value: '${data.currency} ${data.burnRate.toStringAsFixed(1)}',
                color: _aOrange,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _DashboardSectionCard extends StatelessWidget {
  const _DashboardSectionCard({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 0.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: _kLabel,
            ),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _DashboardDonutChart extends StatelessWidget {
  const _DashboardDonutChart({
    required this.categoryTotals,
    required this.totalSpend,
    required this.currency,
  });
  final Map<String, double> categoryTotals;
  final double totalSpend;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final entries = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final sections = List.generate(entries.length, (i) {
      final color = _kPaletteColors[i % _kPaletteColors.length];
      return PieChartSectionData(
        value: entries[i].value,
        color: color,
        radius: 30,
        showTitle: false,
      );
    });

    return SizedBox(
      height: 160,
      child: Row(
        children: [
          // Donut
          SizedBox(
            width: 120,
            child: PieChart(
              PieChartData(
                sections: sections,
                centerSpaceRadius: 38,
                sectionsSpace: 2,
                pieTouchData: PieTouchData(enabled: false),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Legend (top 5)
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...entries.take(5).toList().asMap().entries.map((entry) {
                  final i = entry.key;
                  final e = entry.value;
                  final color = _kPaletteColors[i % _kPaletteColors.length];
                  final pct = totalSpend > 0 ? e.value / totalSpend * 100 : 0.0;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(
                      children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            e.key,
                            style: const TextStyle(fontSize: 11, color: _kLabel),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Text(
                          '${pct.toStringAsFixed(0)}%',
                          style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w700, color: _kLabel),
                        ),
                      ],
                    ),
                  );
                }),
                if (entries.length > 5)
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '+${entries.length - 5} ${'analytics.more'.tr()}',
                      style: const TextStyle(fontSize: 10, color: _kSubtitle),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardTrendChart extends StatelessWidget {
  const _DashboardTrendChart({
    required this.spots,
    required this.currency,
    required this.spanDays,
  });
  final List<FlSpot> spots;
  final String currency;
  final int spanDays;

  @override
  Widget build(BuildContext context) {
    if (spots.isEmpty) return const SizedBox.shrink();

    final maxY   = spots.map((s) => s.y).reduce(math.max);
    final minY   = spots.map((s) => s.y).reduce(math.min);
    final range  = (maxY - minY).abs();
    final padded = (range * 0.15).clamp(1.0, double.infinity);

    final xInterval = spanDays <= 14 ? 1.0
        : spanDays <= 60  ? 7.0
        : 14.0;

    return SizedBox(
      height: 140,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (spots.length - 1).toDouble(),
          minY: minY - padded,
          maxY: maxY + padded,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: range > 0 ? range / 3 : 1,
            getDrawingHorizontalLine: (_) => const FlLine(
              color: Color(0xFF1E293B), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 48,
                getTitlesWidget: (v, _) => Text(
                  _shortNum(v),
                  style: const TextStyle(fontSize: 9, color: _kSubtitle),
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
                    return Text('analytics.today'.tr(),
                      style: const TextStyle(fontSize: 9, color: _kSubtitle));
                  }
                  return Text('${daysAgo}d',
                    style: const TextStyle(fontSize: 9, color: _kSubtitle));
                },
              ),
            ),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => const Color(0xFF1E293B),
              getTooltipItems: (spots) => spots.map((s) =>
                LineTooltipItem(
                  '$currency ${s.y.toStringAsFixed(2)}',
                  const TextStyle(color: _aTeal, fontWeight: FontWeight.w700, fontSize: 11),
                )).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.3,
              color: _aTeal,
              barWidth: 2,
              isStrokeCapRound: true,
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [_aTeal.withValues(alpha: 0.18), _aTeal.withValues(alpha: 0.0)],
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

  static String _shortNum(double v) {
    if (v.abs() >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v.abs() >= 1000)    return '${(v / 1000).toStringAsFixed(1)}k';
    return v.toStringAsFixed(0);
  }
}

class _QuickStatTile extends StatelessWidget {
  const _QuickStatTile({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
            style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color),
            overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Text(value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: color),
            overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _AnalyticsLoadingCard extends StatelessWidget {
  const _AnalyticsLoadingCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant, width: 0.5),
      ),
      child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

// ---------------------------------------------------------------------------
// Widget 2 & 3 — Navigator Card (Wallet / Groups)
// ---------------------------------------------------------------------------
class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.accentDim,
    required this.valueAsync,
    required this.valuePrefix,
    required this.onTap,
    this.groupCount,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final Color accentDim;
  final AsyncValue<String> valueAsync;
  final String valuePrefix;
  final VoidCallback onTap;
  final int? groupCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: accentDim,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      groupCount != null
                          ? '$subtitle · ${groupCount == 1 ? 'dashboard.group_count_one'.tr(namedArgs: {'count': '1'}) : 'dashboard.group_count_other'.tr(namedArgs: {'count': groupCount.toString()})}'
                          : subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  valueAsync.when(
                    skipLoadingOnReload: true,
                    data: (v) => // ACT-overflow: FittedBox mirrors _MasterNetWorthHero pattern for long currency strings.
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerRight,
                          child: Text(
                            '$valuePrefix$v',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: accentColor,
                            ),
                          ),
                        ),
                    loading: () => SizedBox(
                      width: 60, height: 14,
                      child: LinearProgressIndicator(
                        color: accentColor, backgroundColor: accentDim),
                    ),
                    error: (_, _) => Text('—',
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  const SizedBox(height: 2),
                  Icon(Icons.chevron_right, size: 16, color: theme.colorScheme.onSurfaceVariant),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

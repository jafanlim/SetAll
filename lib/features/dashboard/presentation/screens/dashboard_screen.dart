import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/accent_text_style.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/app_top_button.dart';
import '../../../../core/widgets/glass_card.dart';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const _teal      = Color(0xFF00D9B0);
const _purple    = Color(0xFF8B5CF6);
const _orange    = Color(0xFFFF8C42);
const _tealDim   = Color(0x1800D9B0);
const _purpleDim = Color(0x188B5CF6);

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

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Overview',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.3),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        automaticallyImplyLeading: false,
        actions: [
          AppTopButton(
            tooltip: 'Add friend',
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
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
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
              'YOUR FINANCES',
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
              title: 'Personal Wallet',
              subtitle: 'Cash position',
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
              title: 'Shared Expenses',
              subtitle: 'Net group position',
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

    final isDark = theme.brightness == Brightness.dark;
    final gradStart = isDark ? theme.colorScheme.surfaceContainerHigh    : const Color(0xFFF1F5F9); // Slate-100
    final gradEnd   = isDark ? theme.colorScheme.surfaceContainerHighest : const Color(0xFFE2E8F0); // Slate-200

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
              'Net Worth',
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
            Text(
              _error ? '—' : (isPos ? netStr : '-$netStr'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 32,
                letterSpacing: -1,
                color: _error ? theme.colorScheme.onSurfaceVariant : accent,
              ).withAccentShadow(context, opacity: 0.28),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 4),
          Text(
            isPos ? 'You are in the green' : 'You are in the red',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 16),
          if (!_loading && !_error && master != null) ...[
            Row(children: [
              Expanded(child: _StatPill(
                label: 'Wallet cash',
                value: '${master!.currency} ${master!.walletCash.toStringAsFixed(2)}',
                color: _purple,
                bgColor: _purpleDim,
              )),
              const SizedBox(width: 8),
              Expanded(child: _StatPill(
                label: 'Shared balance',
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
              color: color, fontWeight: FontWeight.w600, fontSize: 10,
              shadows: accentShadows(context)),
            overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(value,
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)
                .withAccentShadow(context),
            overflow: TextOverflow.ellipsis),
        ],
      ),
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
                          ? '$subtitle · $groupCount group${groupCount == 1 ? '' : 's'}'
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
                    data: (v) => Text(
                      '$valuePrefix$v',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: accentColor,
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

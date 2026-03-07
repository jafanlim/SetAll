import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const _purple    = Color(0xFF8B5CF6);
const _purpleDim = Color(0x268B5CF6);
const _teal      = Color(0xFF00D9B0);
const _tealDim   = Color(0x2600D9B0);
const _orange    = Color(0xFFFF8C42);
const _orangeDim = Color(0x26FF8C42);

/// Standalone Wallet screen — personal cash balance, true net worth,
/// and spending breakdown by category.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme         = Theme.of(context);
    final walletAsync   = ref.watch(walletBalanceProvider);
    final personalAsync = ref.watch(personalExpensesProvider);
    final summaryAsync  = ref.watch(balanceSummaryProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Wallet',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -0.3,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticUtils.primaryTap();
          context.push(
            AppRouter.addExpense,
            extra: {'groupId': '', 'groupName': ''},
          );
        },
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text(
          'Add wallet entry',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      body: RefreshIndicator(
        color: _purple,
        onRefresh: () async {
          HapticUtils.lightTap();
          ref.invalidate(walletBalanceProvider);
          ref.invalidate(personalExpensesProvider);
          ref.invalidate(balanceSummaryProvider);
        },
        child: CustomScrollView(
          slivers: [
            // ── Wallet Hero ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: walletAsync.when(
                  skipLoadingOnReload: true,
                  data: (walletStr) {
                    final walletDec = Decimal.tryParse(walletStr) ?? Decimal.zero;
                    final summary   = summaryAsync.valueOrNull;
                    final owed = Decimal.tryParse(summary?.youAreOwed ?? '0') ?? Decimal.zero;
                    final owe  = Decimal.tryParse(summary?.youOwe     ?? '0') ?? Decimal.zero;
                    final netPos = walletDec + owed - owe;
                    return WalletHero(
                      walletBalance: walletDec,
                      netPosition: netPos,
                      currency: summary?.currency ?? 'USD',
                    );
                  },
                  loading: () => WalletHero.loading(),
                  error: (_, _) => WalletHero.error(),
                ),
              ),
            ),

            // ── Spending Breakdown ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Text(
                  'Spending breakdown',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    letterSpacing: 0.5,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            personalAsync.when(
              data: (expenses) {
                final spend = <String, Decimal>{};
                for (final e in expenses) {
                  if (e.isIncome) continue;
                  final cat = e.category.isEmpty ? 'General' : e.category;
                  final amt = Decimal.tryParse(e.universalUsdAmount ?? e.amount) ?? Decimal.zero;
                  spend[cat] = (spend[cat] ?? Decimal.zero) + amt;
                }
                if (spend.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.account_balance_wallet_outlined,
                                size: 48, color: theme.colorScheme.onSurfaceVariant),
                            const SizedBox(height: 16),
                            Text(
                              'No personal expenses yet',
                              style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Tap + to add your first wallet entry.',
                              style: TextStyle(
                                fontSize: 13, color: theme.colorScheme.onSurfaceVariant,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }
                final sorted = spend.entries.toList()
                  ..sort((a, b) => b.value.compareTo(a.value));
                final total = sorted.fold(Decimal.zero, (s, e) => s + e.value);
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _CategoryRow(
                      category: sorted[i].key,
                      amount: sorted[i].value,
                      total: total,
                    ),
                    childCount: sorted.length,
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wallet hero — cash balance + true net worth
// ---------------------------------------------------------------------------
class WalletHero extends StatelessWidget {
  const WalletHero({
    super.key,
    required this.walletBalance,
    required this.netPosition,
    required this.currency,
  }) : _loading = false, _error = false;

  static final _zero = Decimal.zero;

  WalletHero.loading()
      : walletBalance = _zero, netPosition = _zero,
        currency = '', _loading = true, _error = false;

  WalletHero.error()
      : walletBalance = _zero, netPosition = _zero,
        currency = '', _loading = false, _error = true;

  final Decimal walletBalance;
  final Decimal netPosition;
  final String  currency;
  final bool    _loading;
  final bool    _error;

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final netIsPos    = netPosition >= Decimal.zero;
    final walletIsPos = walletBalance >= Decimal.zero;
    final ccy         = currency.isEmpty ? 'USD' : currency;

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(
              width: 7, height: 7,
              decoration: const BoxDecoration(color: _purple, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              'Personal wallet',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant, fontSize: 12,
              ),
            ),
          ]),
          const SizedBox(height: 6),
          if (_loading)
            const SizedBox(height: 28, child: LinearProgressIndicator(color: _purple))
          else
            Text(
              '$ccy ${walletBalance.abs().toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 26, letterSpacing: -0.5,
                color: _error
                    ? theme.colorScheme.onSurfaceVariant
                    : (walletIsPos ? _purple : _orange),
              ),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _BalancePill(
              label: 'Cash balance',
              amount: walletBalance.abs().toStringAsFixed(2),
              currency: ccy,
              color: walletIsPos ? _purple : _orange,
              bgColor: walletIsPos ? _purpleDim : _orangeDim,
            )),
            const SizedBox(width: 8),
            Expanded(child: _BalancePill(
              label: 'True net worth',
              amount: netPosition.abs().toStringAsFixed(2),
              currency: ccy,
              color: netIsPos ? _teal : _orange,
              bgColor: netIsPos ? _tealDim : _orangeDim,
            )),
          ]),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Balance pill
// ---------------------------------------------------------------------------
class _BalancePill extends StatelessWidget {
  const _BalancePill({
    required this.label,
    required this.amount,
    required this.currency,
    required this.color,
    required this.bgColor,
  });

  final String label;
  final String amount;
  final String currency;
  final Color  color;
  final Color  bgColor;

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
              ),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text('$currency $amount',
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Category row — spending breakdown
// ---------------------------------------------------------------------------
class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.category,
    required this.amount,
    required this.total,
  });

  final String  category;
  final Decimal amount;
  final Decimal total;

  static const Map<String, IconData> _icons = {
    'Food & drink':      Icons.restaurant_outlined,
    'Transport':         Icons.directions_car_outlined,
    'Entertainment':     Icons.movie_outlined,
    'Bills & utilities': Icons.receipt_long_outlined,
    'Shopping':          Icons.shopping_bag_outlined,
    'Travel':            Icons.flight_outlined,
    'General':           Icons.category_outlined,
    'Other':             Icons.category_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pct   = total > Decimal.zero
        ? ((amount / total).toDecimal(scaleOnInfinitePrecision: 6) * Decimal.fromInt(100)).toDouble()
        : 0.0;
    final icon  = _icons[category] ?? Icons.category_outlined;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: _purple.withAlpha(28),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: _purple),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(category,
                      style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600, fontSize: 13)),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: pct / 100,
                      backgroundColor: _purple.withAlpha(22),
                      color: _purple,
                      minHeight: 4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('USD ${amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13, color: _purple)),
                Text('${pct.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

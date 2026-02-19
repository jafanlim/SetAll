import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/expense_model.dart';
import '../../../../data/models/group_model.dart';

// ---------------------------------------------------------------------------
// Fintech colour palette
// ---------------------------------------------------------------------------
const _teal = Color(0xFF00D9B0);   // "You are owed" – Teal
const _orange = Color(0xFFFF8C42); // "You owe" – Orange
const _tealDim = Color(0x2600D9B0);
const _orangeDim = Color(0x26FF8C42);

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final summaryAsync = ref.watch(balanceSummaryProvider);
    final groupsAsync = ref.watch(myGroupsProvider);
    final expensesAsync = ref.watch(recentExpensesProvider);

    final body = RefreshIndicator(
      color: _teal,
      onRefresh: () async {
        HapticUtils.lightTap();
        ref.invalidate(balanceSummaryProvider);
        ref.invalidate(myGroupsProvider);
        ref.invalidate(recentExpensesProvider);
      },
      child: CustomScrollView(
        slivers: [
          // ── Net Balance Hero ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 12.h),
              child: summaryAsync.when(
                data: (summary) {
                  final owed = Decimal.tryParse(summary.youAreOwed) ?? Decimal.zero;
                  final owe = Decimal.tryParse(summary.youOwe) ?? Decimal.zero;
                  final net = owed - owe;
                  final isPositive = net >= Decimal.zero;
                  final display = isPositive ? net : -net;
                  return _NetBalanceHero(
                    netDisplay: display.toStringAsFixed(2),
                    currency: summary.currency,
                    isPositive: isPositive,
                    youAreOwed: summary.youAreOwed,
                    youOwe: summary.youOwe,
                  );
                },
                loading: () => _NetBalanceHero.loading(),
                error: (_, _) => _NetBalanceHero.error(),
              ),
            ),
          ),

          // ── Groups ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 10.h),
              child: Text(
                'Your groups',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15.sp,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          groupsAsync.when(
            data: (groups) => groups.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 24.h),
                      child: Center(
                        child: Text(
                          'No groups yet. Tap Add expense to create one.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _GroupCard(group: groups[index]),
                      childCount: groups.length,
                    ),
                  ),
            loading: () => SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24.w),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24.w),
                child: Center(
                  child: Text(
                    'Could not load groups',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            ),
          ),

          // ── Recent Activity ───────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 24.h, 16.w, 10.h),
              child: Text(
                'Recent activity',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15.sp,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          expensesAsync.when(
            data: (expenses) => expenses.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                      child: Text(
                        'No expenses yet. Tap + to get started.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _ActivityTile(expense: expenses[index]),
                      childCount: expenses.length,
                    ),
                  ),
            loading: () => SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24.w),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24.w),
                child: Center(
                  child: Text(
                    'Could not load activity',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(child: SizedBox(height: 96.h)),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'SetAll',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20.sp,
            letterSpacing: -0.3,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              HapticUtils.primaryTap();
              context.push(AppRouter.settings);
            },
            tooltip: 'Settings',
          ),
        ],
      ),
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticUtils.primaryTap();
          context.push(AppRouter.groupPicker);
        },
        backgroundColor: _teal,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: Text(
          'Add expense',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Net Balance Hero Widget
// ---------------------------------------------------------------------------
class _NetBalanceHero extends StatelessWidget {
  const _NetBalanceHero({
    required this.netDisplay,
    required this.currency,
    required this.isPositive,
    required this.youAreOwed,
    required this.youOwe,
  }) : _loading = false, _error = false;

  const _NetBalanceHero.loading()
      : netDisplay = '—',
        currency = '',
        isPositive = true,
        youAreOwed = '0',
        youOwe = '0',
        _loading = true,
        _error = false;

  const _NetBalanceHero.error()
      : netDisplay = '—',
        currency = '',
        isPositive = true,
        youAreOwed = '0',
        youOwe = '0',
        _loading = false,
        _error = true;

  final String netDisplay;
  final String currency;
  final bool isPositive;
  final String youAreOwed;
  final String youOwe;
  final bool _loading;
  final bool _error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = isPositive ? _teal : _orange;

    return GlassCard(
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8.w,
                height: 8.w,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 8.w),
              Text(
                isPositive ? 'Overall you are owed' : 'Overall you owe',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12.sp,
                ),
              ),
            ],
          ),
          SizedBox(height: 8.h),
          if (_loading)
            SizedBox(height: 36.h, child: const LinearProgressIndicator())
          else
            Text(
              '$currency $netDisplay',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 34.sp,
                letterSpacing: -1.0,
                color: _error ? theme.colorScheme.onSurfaceVariant : accent,
              ),
            ),
          SizedBox(height: 16.h),
          Row(
            children: [
              Expanded(
                child: _BalancePill(
                  label: 'Owed to you',
                  amount: youAreOwed,
                  currency: currency,
                  color: _teal,
                  bgColor: _tealDim,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: _BalancePill(
                  label: 'You owe',
                  amount: youOwe,
                  currency: currency,
                  color: _orange,
                  bgColor: _orangeDim,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
  final Color color;
  final Color bgColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 10.sp,
            ),
          ),
          SizedBox(height: 2.h),
          Text(
            '$currency $amount',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 14.sp,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Group card
// ---------------------------------------------------------------------------
class _GroupCard extends ConsumerWidget {
  const _GroupCard({required this.group});
  final GroupModel group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final balanceAsync = ref.watch(groupBalanceSummaryProvider(group.id));

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      child: GlassCard(
        child: InkWell(
          onTap: () {
            HapticUtils.lightTap();
            context.push('/group/${group.id}', extra: {'groupName': group.name});
          },
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: _tealDim,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Center(
                    child: Text(
                      group.name.isNotEmpty
                          ? group.name[0].toUpperCase()
                          : 'G',
                      style: TextStyle(
                        color: _teal,
                        fontWeight: FontWeight.w800,
                        fontSize: 16.sp,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.sp,
                        ),
                      ),
                      SizedBox(height: 4.h),
                      balanceAsync.when(
                        data: (s) {
                          final owed = Decimal.tryParse(s.youAreOwed) ?? Decimal.zero;
                          final owe = Decimal.tryParse(s.youOwe) ?? Decimal.zero;
                          if (owed == Decimal.zero && owe == Decimal.zero) {
                            return Text(
                              'Settled up',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _teal,
                                fontSize: 11.sp,
                              ),
                            );
                          }
                          return RichText(
                            text: TextSpan(
                              style: TextStyle(fontSize: 11.sp),
                              children: [
                                if (owed > Decimal.zero) ...[
                                  TextSpan(
                                    text: '+${s.currency} ${s.youAreOwed}',
                                    style: const TextStyle(
                                      color: _teal,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                                if (owed > Decimal.zero && owe > Decimal.zero)
                                  const TextSpan(text: '  '),
                                if (owe > Decimal.zero) ...[
                                  TextSpan(
                                    text: '-${s.currency} ${s.youOwe}',
                                    style: const TextStyle(
                                      color: _orange,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        },
                        loading: () => SizedBox(height: 12.h),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 20.sp,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity tile
// ---------------------------------------------------------------------------
class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.expense});
  final ExpenseModel expense;

  static const Map<String, IconData> _categoryIcons = {
    'Food & drink': Icons.restaurant_outlined,
    'Transport': Icons.directions_car_outlined,
    'Entertainment': Icons.movie_outlined,
    'Bills & utilities': Icons.receipt_long_outlined,
    'Shopping': Icons.shopping_bag_outlined,
    'Travel': Icons.flight_outlined,
    'Other': Icons.category_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon =
        _categoryIcons[expense.category] ?? Icons.attach_money_outlined;

    // Display original amount if available, otherwise stored amount
    final displayAmount = expense.originalAmount ?? expense.amount;
    final displayCurrency = expense.originalCurrency ?? expense.currency;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 3.h),
      child: GlassCard(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Row(
          children: [
            Container(
              width: 38.w,
              height: 38.w,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(icon, size: 18.sp, color: theme.colorScheme.onSurfaceVariant),
            ),
            SizedBox(width: 12.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.description.isEmpty ? expense.category : expense.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13.sp,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (expense.originalCurrency != null &&
                      expense.originalCurrency != expense.currency) ...[
                    SizedBox(height: 2.h),
                    Text(
                      '${expense.currency} ${expense.amount} base',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10.sp,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$displayCurrency $displayAmount',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13.sp,
                    color: _teal,
                  ),
                ),
                if (expense.createdAt != null)
                  Text(
                    _shortDate(expense.createdAt!),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 10.sp,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _shortDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}';
    } catch (_) {
      return '';
    }
  }
}


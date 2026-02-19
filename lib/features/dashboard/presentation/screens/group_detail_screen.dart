import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../data/repositories/setall_repository.dart' show BalanceSummary;
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/expense_model.dart';
import '../../../../data/models/profile_model.dart';

const _teal = Color(0xFF00D9B0);
const _tealDim = Color(0x2600D9B0);
const _orange = Color(0xFFFF8C42);

class GroupDetailScreen extends ConsumerWidget {
  const GroupDetailScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final expensesAsync = ref.watch(groupExpensesProvider(groupId));
    final balanceAsync = ref.watch(groupBalanceSummaryProvider(groupId));

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          groupName,
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16.sp),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Invite member',
            onPressed: () {
              HapticUtils.primaryTap();
              context.push(
                '/group/$groupId/invite',
                extra: {'groupName': groupName},
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _teal,
        onRefresh: () async {
          HapticUtils.lightTap();
          ref.invalidate(groupMembersProvider(groupId));
          ref.invalidate(groupExpensesProvider(groupId));
          ref.invalidate(groupBalanceSummaryProvider(groupId));
        },
        child: CustomScrollView(
          slivers: [
            // ── Balance summary ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
                child: balanceAsync.when(
                  data: (s) => _GroupBalanceCard(summary: s),
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
              ),
            ),

            // ── Members section ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 20.h, 16.w, 8.h),
                child: Text(
                  'Members',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15.sp,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w),
                child: membersAsync.when(
                  data: (members) => _MemberList(members: members),
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (e, _) => Text(
                    'Could not load members',
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 13.sp),
                  ),
                ),
              ),
            ),

            // ── Expenses section ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16.w, 24.h, 16.w, 8.h),
                child: Text(
                  'Expenses',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15.sp,
                  ),
                ),
              ),
            ),
            expensesAsync.when(
              data: (expenses) {
                if (expenses.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                      child: Text(
                        'No expenses yet. Tap + to add one.',
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 13.sp,
                        ),
                      ),
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => _ExpenseTile(
                      expense: expenses[i],
                      groupId: groupId,
                      groupName: groupName,
                      onDeleted: () {
                        ref.invalidate(groupExpensesProvider(groupId));
                        ref.invalidate(balanceSummaryProvider);
                        ref.invalidate(recentExpensesProvider);
                        ref.invalidate(groupBalanceSummaryProvider(groupId));
                      },
                    ),
                    childCount: expenses.length,
                  ),
                );
              },
              loading: () => SliverToBoxAdapter(
                child: const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ),
              error: (e, _) => SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16.w),
                  child: Text(
                    'Could not load expenses',
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 13.sp),
                  ),
                ),
              ),
            ),

            SliverToBoxAdapter(child: SizedBox(height: 96.h)),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticUtils.primaryTap();
          context.push(
            AppRouter.addExpense,
            extra: {'groupId': groupId, 'groupName': groupName},
          );
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
// Group balance summary card
// ---------------------------------------------------------------------------
class _GroupBalanceCard extends StatelessWidget {
  const _GroupBalanceCard({required this.summary});
  final BalanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owed = Decimal.tryParse(summary.youAreOwed) ?? Decimal.zero;
    final owe = Decimal.tryParse(summary.youOwe) ?? Decimal.zero;

    if (owed == Decimal.zero && owe == Decimal.zero) {
      return GlassCard(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline, color: _teal, size: 18.sp),
            SizedBox(width: 8.w),
            Text(
              'All settled up in this group',
              style: TextStyle(
                color: _teal,
                fontWeight: FontWeight.w600,
                fontSize: 13.sp,
              ),
            ),
          ],
        ),
      );
    }

    return GlassCard(
      padding: EdgeInsets.all(16.w),
      child: Row(
        children: [
          if (owed > Decimal.zero)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Owed to you',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '+${summary.currency} ${summary.youAreOwed}',
                    style: TextStyle(
                      color: _teal,
                      fontWeight: FontWeight.w700,
                      fontSize: 16.sp,
                    ),
                  ),
                ],
              ),
            ),
          if (owe > Decimal.zero)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You owe',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '-${summary.currency} ${summary.youOwe}',
                    style: TextStyle(
                      color: _orange,
                      fontWeight: FontWeight.w700,
                      fontSize: 16.sp,
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
// Members list
// ---------------------------------------------------------------------------
class _MemberList extends StatelessWidget {
  const _MemberList({required this.members});
  final List<ProfileModel> members;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (members.isEmpty) {
      return Text(
        'No members yet',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 13.sp,
        ),
      );
    }
    return GlassCard(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Column(
        children: members.map((m) {
          final initial = m.name.isNotEmpty ? m.name[0].toUpperCase() : '?';
          return ListTile(
            dense: true,
            leading: Container(
              width: 32.w,
              height: 32.w,
              decoration: const BoxDecoration(
                color: _tealDim,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initial,
                  style: TextStyle(
                    color: _teal,
                    fontWeight: FontWeight.w700,
                    fontSize: 13.sp,
                  ),
                ),
              ),
            ),
            title: Text(
              m.name,
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
            ),
            subtitle: m.defaultCurrency != 'USD'
                ? Text(
                    m.defaultCurrency,
                    style: TextStyle(
                      fontSize: 10.sp,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : null,
          );
        }).toList(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Expense list
// ---------------------------------------------------------------------------
class _ExpenseTile extends ConsumerWidget {
  const _ExpenseTile({
    required this.expense,
    required this.groupId,
    required this.groupName,
    required this.onDeleted,
  });

  final ExpenseModel expense;
  final String groupId;
  final String groupName;
  final VoidCallback onDeleted;

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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final icon =
        _categoryIcons[expense.category] ?? Icons.attach_money_outlined;
    final displayAmount = expense.originalAmount ?? expense.amount;
    final displayCurrency = expense.originalCurrency ?? expense.currency;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 3.h),
      child: GlassCard(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
        child: Row(
          children: [
            Container(
              width: 36.w,
              height: 36.w,
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10.r),
              ),
              child: Icon(icon, size: 16.sp, color: theme.colorScheme.onSurfaceVariant),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    expense.description.isEmpty ? expense.category : expense.description,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.sp),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (expense.originalCurrency != null &&
                      expense.originalCurrency != expense.currency)
                    Text(
                      '${expense.currency} ${expense.amount} base',
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            Text(
              '$displayCurrency $displayAmount',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.sp,
                color: _teal,
              ),
            ),
            PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                size: 18.sp,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              onSelected: (value) async {
                if (value == 'edit') {
                  context.push(
                    '/group/$groupId/expense/${expense.id}',
                    extra: {'groupName': groupName},
                  );
                } else if (value == 'delete') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete expense?'),
                      content: Text(
                        'Remove "${expense.description.isEmpty ? expense.amount : expense.description}"? '
                        'This cannot be undone.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop(true),
                          style: FilledButton.styleFrom(
                            backgroundColor: theme.colorScheme.error,
                          ),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true && context.mounted) {
                    await ref.read(setAllRepositoryProvider).deleteExpense(expense.id);
                    if (context.mounted) {
                      onDeleted();
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Expense deleted')),
                      );
                    }
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

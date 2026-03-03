import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../data/repositories/setall_repository.dart' show BalanceSummary;
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../core/widgets/swipe_action_card.dart';
import '../../../../data/models/expense_model.dart';
import '../../../../data/models/profile_model.dart';

const _teal = Color(0xFF00D9B0);
const _tealDim = Color(0x2600D9B0);
const _orange = Color(0xFFFF8C42);

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  bool _manuallySettled = false;
  late String _groupName;

  @override
  void initState() {
    super.initState();
    _groupName = widget.groupName;
  }

  Future<void> _renameGroup(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = TextEditingController(text: _groupName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Group name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Rename'),
          ),
        ],
      ),
    );
    // Dispose after the dialog's exit animation completes to avoid
    // "controller used after dispose" during the pop transition.
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (newName == null || newName.isEmpty || !mounted) return;
    final ok = await ref.read(setAllRepositoryProvider).renameGroup(widget.groupId, newName);
    if (!mounted) return;
    if (ok) {
      setState(() => _groupName = newName);
      ref.invalidate(myGroupsProvider);
      HapticUtils.success();
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not rename group')),
      );
    }
  }

  Future<void> _deleteGroup(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text('Delete "$_groupName"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final ok = await ref.read(setAllRepositoryProvider).deleteGroup(widget.groupId);
    if (!mounted) return;
    if (ok) {
      ref.invalidate(myGroupsProvider);
      ref.invalidate(balanceSummaryProvider);
      HapticUtils.success();
      router.pop();
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Only the group creator can delete it')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final groupId = widget.groupId;
    final groupName = _groupName;
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final expensesAsync = ref.watch(groupExpensesProvider(groupId));
    final balanceAsync = ref.watch(groupBalanceSummaryProvider(groupId));
    final creatorAsync = ref.watch(groupCreatorProvider(groupId));

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
          if (_manuallySettled)
            TextButton.icon(
              icon: const Icon(Icons.undo, size: 16),
              label: const Text('Reopen'),
              style: TextButton.styleFrom(foregroundColor: _teal),
              onPressed: () {
                HapticUtils.selection();
                setState(() => _manuallySettled = false);
              },
            )
          else
            TextButton.icon(
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: const Text('Settle'),
              style: TextButton.styleFrom(foregroundColor: _teal),
              onPressed: () async {
                HapticUtils.primaryTap();
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Mark as settled?'),
                    content: const Text(
                      'This hides the outstanding balance for this group. '
                      'Existing expenses are kept. You can reopen it anytime.',
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
                        onPressed: () => Navigator.of(ctx).pop(true),
                        child: const Text('Settle'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) setState(() => _manuallySettled = true);
              },
            ),
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
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'rename') _renameGroup(context);
              if (value == 'delete') _deleteGroup(context);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'rename', child: Text('Rename group')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('Delete group', style: TextStyle(color: Colors.redAccent)),
              ),
            ],
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
                child: _manuallySettled
                    ? GlassCard(
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline, color: _teal, size: 18.sp),
                            SizedBox(width: 8.w),
                            Text(
                              'Marked as settled',
                              style: TextStyle(color: _teal, fontWeight: FontWeight.w600, fontSize: 13.sp),
                            ),
                          ],
                        ),
                      )
                    : balanceAsync.when(
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
                  data: (members) => _MemberList(
                    members: members,
                    groupId: groupId,
                    creatorId: creatorAsync.valueOrNull ?? '',
                  ),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: _teal, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'All settled up in this group',
                style: const TextStyle(
                  color: _teal,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
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
class _MemberList extends ConsumerWidget {
  const _MemberList({
    required this.members,
    required this.groupId,
    required this.creatorId,
  });
  final List<ProfileModel> members;
  final String groupId;
  final String creatorId;

  Future<void> _removeMember(
    BuildContext context,
    WidgetRef ref,
    ProfileModel member,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove member?'),
        content: Text('Remove "${member.name}" from this group?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await ref
        .read(setAllRepositoryProvider)
        .removeGroupMember(groupId, member.id);

    if (!context.mounted) return;
    if (result.ok) {
      ref.invalidate(groupMembersProvider(groupId));
      ref.invalidate(balanceSummaryProvider);
      HapticUtils.success();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.error ?? 'Could not remove member.')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final currentProfileAsync = ref.watch(currentProfileProvider);
    final currentUid = currentProfileAsync.valueOrNull?.id;
    final isCreator = currentUid == creatorId;

    if (members.isEmpty) {
      return Text(
        'No members yet',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      );
    }
    return GlassCard(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: members.map((m) {
          final initial = m.name.isNotEmpty ? m.name[0].toUpperCase() : '?';
          final isCreatorMember = m.id == creatorId;
          return ListTile(
            dense: true,
            leading: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: _tealDim,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: _teal,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            title: Text(
              isCreatorMember ? '${m.name} (creator)' : m.name,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: m.defaultCurrency != 'USD'
                ? Text(
                    m.defaultCurrency,
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                : null,
            trailing: isCreator && !isCreatorMember
                ? IconButton(
                    icon: const Icon(Icons.person_remove_outlined, size: 18),
                    color: Colors.redAccent,
                    tooltip: 'Remove member',
                    onPressed: () => _removeMember(context, ref, m),
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
    final baseCurrencyAsync = ref.watch(baseCurrencyProvider);
    final baseCurrency = baseCurrencyAsync.valueOrNull ?? 'USD';
    // Only show conversion note when expense currency differs from base currency
    final showConversion = expense.currency != baseCurrency && expense.universalUsdAmount != null;
    final rateAsync = showConversion
        ? ref.watch(rateToBaseProvider((from: 'USD', base: baseCurrency)))
        : null;
    final convertedAmount = showConversion && rateAsync?.valueOrNull != null
        ? ((Decimal.tryParse(expense.universalUsdAmount ?? '0') ?? Decimal.zero) *
            (Decimal.tryParse(rateAsync!.valueOrNull!) ?? Decimal.one))
            .round(scale: 2)
            .toStringAsFixed(2)
        : null;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 3.h),
      child: SwipeActionCard(
        actionsPanelWidth: 140,
        actions: [
          SwipeAction(
            icon: Icons.edit_outlined,
            label: 'Edit',
            color: _teal,
            onTap: () => context.push(
              '/group/$groupId/expense/${expense.id}',
              extra: {'groupName': groupName},
            ),
          ),
          SwipeAction(
            icon: Icons.delete_outline,
            label: 'Delete',
            color: Colors.redAccent,
            onTap: () => _confirmDelete(context, ref),
          ),
        ],
        child: GestureDetector(
          onLongPress: () => _showContextMenu(context, ref),
          onSecondaryTapUp: defaultTargetPlatform == TargetPlatform.macOS
              ? (d) => _showRightClickMenu(context, ref, d.globalPosition)
              : null,
          child: GlassCard(
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
            child: InkWell(
              borderRadius: BorderRadius.circular(12.r),
              onTap: () => context.push(
                '/group/$groupId/expense/${expense.id}',
                extra: {'groupName': groupName},
              ),
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
                      if (convertedAmount != null)
                        Text(
                          '≈ $baseCurrency $convertedAmount',
                          style: TextStyle(
                            fontSize: 10.sp,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      else if (expense.originalCurrency != null &&
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
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showRightClickMenu(
    BuildContext context, WidgetRef ref, Offset position) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 16, color: _teal),
            const SizedBox(width: 8),
            const Text('Edit expense'),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: const [
            Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Delete expense', style: TextStyle(color: Colors.redAccent)),
          ]),
        ),
      ],
    );
    if (!context.mounted) return;
    if (result == 'edit') {
      context.push('/group/$groupId/expense/${expense.id}',
          extra: {'groupName': groupName});
    } else if (result == 'delete') {
      _confirmDelete(context, ref);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    HapticUtils.primaryTap();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text(
          'Remove "${expense.description.isEmpty ? expense.amount : expense.description}"? '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await ref.read(setAllRepositoryProvider).deleteExpense(expense.id);
      if (context.mounted) {
        onDeleted();
        HapticUtils.success();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense deleted')),
        );
      }
    }
  }

  Future<void> _showContextMenu(BuildContext context, WidgetRef ref) async {
    HapticUtils.primaryTap();
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit_outlined, color: _teal),
              title: const Text('Edit expense'),
              onTap: () => Navigator.of(ctx).pop('edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Delete expense', style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (result == 'edit') {
      context.push('/group/$groupId/expense/${expense.id}', extra: {'groupName': groupName});
    } else if (result == 'delete') {
      _confirmDelete(context, ref);
    }
  }
}

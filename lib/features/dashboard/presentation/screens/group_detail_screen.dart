import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../data/repositories/setall_repository.dart' show BalanceSummary;
import '../../../../domain/services/settlement_engine.dart' show SettlementTransaction;
import '../../../../core/utils/amount_formatter.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../core/widgets/swipe_action_card.dart';
import '../../../../data/models/expense_model.dart';
import '../../../../data/models/profile_model.dart';

const _teal = Color(0xFF00D9B0);
const _tealDim = Color(0x2600D9B0);
const _orange = Color(0xFFFF8C42);
const _brandOrange = Color(0xFFF97316);

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
  bool _editMode = false;
  final Set<String> _selected = {};
  late String _groupName;

  @override
  void initState() {
    super.initState();
    _groupName = widget.groupName;
  }

  void _toggleEditMode() {
    HapticUtils.selection();
    setState(() {
      _editMode = !_editMode;
      _selected.clear();
    });
  }

  void _toggleExpense(String id) {
    HapticUtils.selection();
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _selectAllExpenses(List<String> ids) {
    HapticUtils.selection();
    setState(() => _selected.addAll(ids));
  }

  void _deselectAllExpenses() {
    HapticUtils.selection();
    setState(() => _selected.clear());
  }

  Future<void> _deleteBatchExpenses() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expenses?'),
        content: Text(
          'Are you sure you want to delete $count expense${count == 1 ? '' : 's'}?\n\nThis is irreversible.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text('Delete ($count)'),
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final groupId = widget.groupId;
    final ok = await ref.read(setAllRepositoryProvider).deleteExpenses(_selected.toList());
    if (!mounted) return;
    if (ok) {
      HapticUtils.success();
      ref.invalidate(groupExpensesProvider(groupId));
      ref.invalidate(balanceSummaryProvider);
      ref.invalidate(recentExpensesProvider);
      ref.invalidate(groupBalanceSummaryProvider(groupId));
      setState(() {
        _editMode = false;
        _selected.clear();
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete some expenses.')),
      );
    }
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
    // ignore: use_build_context_synchronously
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text('Delete "$_groupName" and all its expenses?'),
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
    // ignore: use_build_context_synchronously
    final doubleConfirm = await showDialog<bool>(
      context: context, // ignore: use_build_context_synchronously
      builder: (ctx) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text('This action is irreversible. All expenses and balances in this group will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, delete forever'),
          ),
        ],
      ),
    );
    if (doubleConfirm != true || !mounted) return;
    final ok = await ref.read(setAllRepositoryProvider).deleteGroup(widget.groupId);
    if (!mounted) return;
    if (ok) {
      ref.invalidate(myGroupsProvider);
      ref.invalidate(balanceSummaryProvider);
      ref.invalidate(recentExpensesProvider);
      HapticUtils.success();
      router.pop();
    } else {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not delete group.')),
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
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        actions: _editMode
            ? [
                expensesAsync.whenData((expenses) {
                  final allSelected = expenses.isNotEmpty &&
                      expenses.every((e) => _selected.contains(e.id));
                  return TextButton(
                    onPressed: allSelected
                        ? _deselectAllExpenses
                        : () => _selectAllExpenses(expenses.map((e) => e.id).toList()),
                    child: Text(allSelected ? 'Deselect All' : 'Select All'),
                  );
                }).valueOrNull ?? const SizedBox.shrink(),
                TextButton(
                  onPressed: _toggleEditMode,
                  child: const Text('Cancel'),
                ),
                if (_selected.isNotEmpty)
                  TextButton.icon(
                    onPressed: _deleteBatchExpenses,
                    icon: const Icon(Icons.delete_outline, size: 16, color: _brandOrange),
                    label: Text(
                      'Delete (${_selected.length})',
                      style: const TextStyle(color: _brandOrange),
                    ),
                  ),
              ]
            : [
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
                    if (value == 'editExpenses') _toggleEditMode();
                  },
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'rename', child: Text('Rename group')),
                    const PopupMenuItem(value: 'editExpenses', child: Text('Select expenses')),
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
          ref.invalidate(simplifiedDebtsProvider(groupId));
        },
        child: CustomScrollView(
          slivers: [
            // ── Balance summary ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _manuallySettled
                    ? GlassCard(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline, color: _teal, size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Marked as settled',
                                style: const TextStyle(color: _teal, fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      )
                    : balanceAsync.when(
                        skipLoadingOnReload: true,
                        data: (s) => _GroupBalanceCard(summary: s),
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
              ),
            ),

            // ── Settlement Plan section ──────────────────────────────────
            if (!_manuallySettled)
              SliverToBoxAdapter(
                child: _SettlementPlanSection(groupId: groupId),
              ),

            // ── Members section ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  'Members',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
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
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                  ),
                ),
              ),
            ),

            // ── Expenses section ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                child: Text(
                  'Expenses',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            expensesAsync.when(
              data: (expenses) {
                if (expenses.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          'No expenses yet. Tap + to add one.',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 13,
                        ),
                      ),
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final expense = expenses[i];
                      if (_editMode) {
                        return _ExpenseTileSelectable(
                          expense: expense,
                          selected: _selected.contains(expense.id),
                          onToggle: () => _toggleExpense(expense.id),
                        );
                      }
                      return _ExpenseTile(
                        expense: expense,
                        groupId: groupId,
                        groupName: groupName,
                        onDeleted: () {
                          ref.invalidate(groupExpensesProvider(groupId));
                          ref.invalidate(balanceSummaryProvider);
                          ref.invalidate(recentExpensesProvider);
                          ref.invalidate(groupBalanceSummaryProvider(groupId));
                        },
                      );
                    },
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'Could not load expenses',
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 96)),
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
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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
      padding: const EdgeInsets.all(16),
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
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '+${summary.currency} ${formatAmount(summary.youAreOwed)}',
                    style: const TextStyle(
                      color: _teal,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
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
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    '-${summary.currency} ${formatAmount(summary.youOwe)}',
                    style: const TextStyle(
                      color: _orange,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
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
// Selectable expense tile — used in batch Edit mode
// ---------------------------------------------------------------------------
class _ExpenseTileSelectable extends StatelessWidget {
  const _ExpenseTileSelectable({
    required this.expense,
    required this.selected,
    required this.onToggle,
  });

  final ExpenseModel expense;
  final bool selected;
  final VoidCallback onToggle;

  static const Map<String, IconData> _categoryIcons = {
    'Food & drink':      Icons.restaurant_outlined,
    'Transport':         Icons.directions_car_outlined,
    'Entertainment':     Icons.movie_outlined,
    'Bills & utilities': Icons.receipt_long_outlined,
    'Shopping':          Icons.shopping_bag_outlined,
    'Travel':            Icons.flight_outlined,
    'Other':             Icons.category_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final icon = _categoryIcons[expense.category] ?? Icons.attach_money_outlined;
    final label = expense.description.isEmpty ? expense.category : expense.description;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: GestureDetector(
        onTap: onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? _brandOrange : Colors.transparent,
              width: 2,
            ),
          ),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected ? _brandOrange : Colors.transparent,
                    border: Border.all(
                      color: selected ? _brandOrange : theme.colorScheme.onSurfaceVariant,
                      width: 2,
                    ),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 13, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 10),
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${expense.currency} ${formatAmount(expense.amount)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: _teal,
                  ),
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
    final displayAmount = formatAmount(expense.originalAmount ?? expense.amount);
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.push(
                '/group/$groupId/expense/${expense.id}',
                extra: {'groupName': groupName},
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        expense.description.isEmpty ? expense.category : expense.description,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (convertedAmount != null)
                        Text(
                          '≈ $baseCurrency $convertedAmount',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        )
                      else if (expense.originalCurrency != null &&
                          expense.originalCurrency != expense.currency)
                        Text(
                          '${expense.currency} ${formatAmount(expense.amount)} base',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$displayCurrency $displayAmount',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
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
          'Remove "${expense.description.isEmpty ? expense.category : expense.description}"?',
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
    if (confirm != true || !context.mounted) return;
    final doubleConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text('This action is irreversible. This expense and its splits will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, delete forever'),
          ),
        ],
      ),
    );
    if (doubleConfirm != true || !context.mounted) return;
    await ref.read(setAllRepositoryProvider).deleteExpense(expense.id);
    if (context.mounted) {
      onDeleted();
      HapticUtils.success();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense deleted')),
      );
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

// ---------------------------------------------------------------------------
// Settlement Plan section
// ---------------------------------------------------------------------------

/// Button shown next to a debt row when the current user is the debtor.
/// Confirms then calls [SetAllRepository.recordSettlement].
class _SettleButton extends ConsumerStatefulWidget {
  const _SettleButton({
    required this.groupId,
    required this.debt,
    required this.amountStr,
  });

  final String groupId;
  final SettlementTransaction debt;
  final String amountStr;

  @override
  ConsumerState<_SettleButton> createState() => _SettleButtonState();
}

class _SettleButtonState extends ConsumerState<_SettleButton> {
  bool _loading = false;

  Future<void> _settle() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Record settlement?'),
        content: Text(
          'This records that you paid ${widget.amountStr}. '
          'The debt will disappear from the settlement plan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Settle'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _loading = true);
    final ok = await ref.read(setAllRepositoryProvider).recordSettlement(
      groupId: widget.groupId,
      fromUserId: widget.debt.fromUserId,
      toUserId: widget.debt.toUserId,
      amount: widget.debt.amount.toString(),
      currency: widget.debt.currency,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (ok) {
      ref.invalidate(groupBalanceSummaryProvider(widget.groupId));
      ref.invalidate(simplifiedDebtsProvider(widget.groupId));
      ref.invalidate(balanceSummaryProvider);
      HapticUtils.success();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not record settlement. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
      );
    }
    return TextButton(
      onPressed: _settle,
      style: TextButton.styleFrom(
        foregroundColor: _teal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: const Text(
        'Settle',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
    );
  }
}

class _SettlementPlanSection extends ConsumerWidget {
  const _SettlementPlanSection({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final debtsAsync = ref.watch(simplifiedDebtsProvider(groupId));
    final membersAsync = ref.watch(groupMembersProvider(groupId));
    final currentUid = ref.watch(currentUserIdProvider);

    return debtsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
      data: (debts) {
        if (debts.isEmpty) return const SizedBox.shrink();

        final memberMap = {
          for (final m in membersAsync.valueOrNull ?? <ProfileModel>[]) m.id: m,
        };

        String displayName(String uid) {
          if (uid == currentUid) return 'You';
          final m = memberMap[uid];
          if (m == null) return uid.substring(0, 8);
          return m.nickname?.isNotEmpty == true ? m.nickname! : m.name;
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Settlement Plan',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 8),
              GlassCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: debts.map((debt) {
                    final fromName = displayName(debt.fromUserId);
                    final toName = displayName(debt.toUserId);
                    final isCurrentUserDebtor = debt.fromUserId == currentUid;
                    final amountStr =
                        '${debt.currency} ${debt.amount.toStringAsFixed(2)}';

                    return ListTile(
                      dense: true,
                      leading: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: isCurrentUserDebtor
                              ? const Color(0x26FF8C42)
                              : _tealDim,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.arrow_forward_rounded,
                          size: 16,
                          color: isCurrentUserDebtor ? _orange : _teal,
                        ),
                      ),
                      title: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: fromName,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: isCurrentUserDebtor
                                    ? _orange
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                            TextSpan(
                              text: ' owes ',
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            TextSpan(
                              text: toName,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: debt.toUserId == currentUid
                                    ? _teal
                                    : theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: isCurrentUserDebtor
                          ? _SettleButton(
                              groupId: groupId,
                              debt: debt,
                              amountStr: amountStr,
                            )
                          : Text(
                              amountStr,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: _teal,
                              ),
                            ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../data/models/group_model.dart';
import '../../../../data/repositories/setall_repository.dart' show BalanceSummary;
import '../../../../domain/services/settlement_engine.dart' show SettlementTransaction;
import '../../../../core/services/date_format_service.dart';
import '../../../../core/utils/amount_formatter.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../core/widgets/swipe_action_card.dart';
import '../../../../data/models/expense_model.dart';
import '../../../../data/models/profile_model.dart';
import '../../../../domain/entities/expense.dart' show SplitType;
import '../../../receipt/presentation/receipt_entry_sheet.dart';

const _teal = Color(0xFF00D9B0);
const _tealDim = Color(0x2600D9B0);
const _orange = Color(0xFFFF8C42);
const _brandOrange = Color(0xFFF97316);
const _blue = Color(0xFF3B82F6);

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
        title: Text('group_detail.delete_expenses_title'.tr()),
        content: Text(
          count == 1
              ? 'group_detail.delete_expenses_confirm'.tr(namedArgs: {'count': count.toString()})
              : 'group_detail.delete_expenses_confirm_plural'.tr(namedArgs: {'count': count.toString()}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.delete_outline, size: 16),
            label: Text('common.delete_count'.tr(namedArgs: {'count': count.toString()})),
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
        SnackBar(content: Text('group_detail.could_not_delete_expenses'.tr())),
      );
    }
  }

  Future<void> _renameGroup(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ctrl = TextEditingController(text: _groupName);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('group_detail.rename_group'.tr()),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(labelText: 'group_detail.group_name_label'.tr()),
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('common.cancel'.tr())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: Text('common.rename'.tr()),
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
        SnackBar(content: Text('group_detail.could_not_rename'.tr())),
      );
    }
  }

  Future<void> _settleGroup() async {
    HapticUtils.primaryTap();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('group_detail.settle_title'.tr()),
        content: Text('group_detail.settle_body'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('common.cancel'.tr())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('common.settle'.tr()),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final ok = await ref.read(setAllRepositoryProvider).setGroupSettled(widget.groupId);
    if (!mounted) return;
    if (ok) {
      ref.invalidate(myGroupsProvider);
      ref.invalidate(simplifiedDebtsProvider(widget.groupId));
      ref.invalidate(groupBalanceSummaryProvider(widget.groupId));
      ref.invalidate(omniActivityProvider);
      HapticUtils.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('group_detail.settled_snack'.tr())),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('group_detail.settle_failed'.tr()), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _reopenGroup() async {
    HapticUtils.primaryTap();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('group_detail.reopen_title'.tr()),
        content: Text('group_detail.reopen_body'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('common.cancel'.tr())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('common.reopen'.tr()),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final ok = await ref.read(setAllRepositoryProvider).clearGroupSettled(widget.groupId);
    if (!mounted) return;
    if (ok) {
      ref.invalidate(myGroupsProvider);
      ref.invalidate(simplifiedDebtsProvider(widget.groupId));
      ref.invalidate(groupBalanceSummaryProvider(widget.groupId));
      ref.invalidate(omniActivityProvider);
      HapticUtils.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('group_detail.reopened_snack'.tr())),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('group_detail.reopen_failed'.tr()), backgroundColor: Colors.red),
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
        title: Text('group_detail.delete_title'.tr()),
        content: Text('group_detail.delete_body'.tr(namedArgs: {'name': _groupName})),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('common.cancel'.tr())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    // ignore: use_build_context_synchronously
    final doubleConfirm = await showDialog<bool>(
      context: context, // ignore: use_build_context_synchronously
      builder: (ctx) => AlertDialog(
        title: Text('group_detail.delete_sure_title'.tr()),
        content: Text('group_detail.delete_sure_body'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('common.cancel'.tr())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('common.yes_delete_forever'.tr()),
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
        SnackBar(content: Text('group_detail.could_not_delete'.tr())),
      );
    }
  }

  void _openReceiptScan(
    BuildContext context,
    String groupId,
    String baseCurrency,
  ) {
    HapticUtils.primaryTap();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ReceiptEntrySheet(groupId: groupId, defaultCurrency: baseCurrency),
    );
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
    final groupsAsync  = ref.watch(myGroupsProvider);
    final group = groupsAsync.valueOrNull
        ?.where((g) => g.id == groupId)
        .firstOrNull;

    final baseCcyAsync = ref.watch(baseCurrencyProvider);
    final baseCurrency = group?.defaultCurrency ?? baseCcyAsync.valueOrNull ?? 'USD';

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
                    child: Text(allSelected ? 'group_detail.deselect_all'.tr() : 'group_detail.select_all'.tr()),
                  );
                }).valueOrNull ?? const SizedBox.shrink(),
                TextButton(
                  onPressed: _toggleEditMode,
                  child: Text('common.cancel'.tr()),
                ),
                if (_selected.isNotEmpty)
                  TextButton.icon(
                    onPressed: _deleteBatchExpenses,
                    icon: const Icon(Icons.delete_outline, size: 16, color: _brandOrange),
                    label: Text(
                      'common.delete_count'.tr(namedArgs: {'count': _selected.length.toString()}),
                      style: const TextStyle(color: _brandOrange),
                    ),
                  ),
              ]
            : [
                if (group?.isSettled == true)
                  TextButton.icon(
                    icon: const Icon(Icons.lock_open_outlined, size: 16),
                    label: Text('common.reopen'.tr()),
                    style: TextButton.styleFrom(foregroundColor: _orange),
                    onPressed: _reopenGroup,
                  )
                else
                  TextButton.icon(
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: Text('common.settle'.tr()),
                    style: TextButton.styleFrom(foregroundColor: _teal),
                    onPressed: _settleGroup,
                  ),
                IconButton(
                  icon: const Icon(Icons.document_scanner_rounded),
                  tooltip: 'receipt.scan_bill'.tr(),
                  onPressed: () =>
                      _openReceiptScan(context, groupId, baseCurrency),
                ),
                IconButton(
                  icon: const Icon(Icons.person_add_outlined),
                  tooltip: 'group_detail.invite_member'.tr(),
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
                    if (value == 'editGroup' && group != null) {
                      context.push('/group/$groupId/edit', extra: group);
                    }
                    if (value == 'delete') _deleteGroup(context);
                    if (value == 'editExpenses') _toggleEditMode();
                    if (value == 'settle') _settleGroup();
                    if (value == 'reopen') _reopenGroup();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'editGroup', child: Text('group_detail.edit_group'.tr())),
                    PopupMenuItem(value: 'rename', child: Text('group_detail.rename_group'.tr())),
                    PopupMenuItem(value: 'editExpenses', child: Text('group_detail.select_expenses'.tr())),
                    if (group?.isSettled == true)
                      PopupMenuItem(value: 'reopen', child: Text('group_detail.reopen_group'.tr() ))
                    else
                      PopupMenuItem(value: 'settle', child: Text('group_detail.settle_group'.tr())),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('group_detail.delete_group'.tr(), style: const TextStyle(color: Colors.redAccent)),
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
            // ── Group hero (avatar / colour chip) ─────────────────────
            if (group != null)
              SliverToBoxAdapter(
                child: _GroupHeroBar(group: group),
              ),

            // ── Settled banner ───────────────────────────────────────────
            if (group?.isSettled == true)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: _tealDim,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _teal.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: _teal, size: 20),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'common.settled_group_banner'.tr(),
                            style: TextStyle(
                              color: _teal,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _reopenGroup,
                          style: TextButton.styleFrom(
                            foregroundColor: _orange,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text('common.reopen'.tr(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Balance summary ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: balanceAsync.when(
                        skipLoadingOnReload: true,
                        data: (s) => _GroupBalanceCard(summary: s),
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
              ),
            ),

            // ── Settlement Plan section ──────────────────────────────────
            SliverToBoxAdapter(
              child: _SettlementPlanSection(groupId: groupId),
            ),

            // ── Members section ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
                child: Text(
                  'group_detail.members'.tr(),
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
                    'common.could_not_load_members'.tr(),
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
                  'group_detail.expenses'.tr(),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          Text(
                            'common.no_expenses_yet_tap'.tr(),
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: _blue,
                                side: BorderSide(
                                  color: _blue.withValues(alpha: 0.4),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              icon: const Icon(
                                Icons.document_scanner_rounded,
                                size: 20,
                              ),
                              label: Text(
                                'receipt.scan_bill'.tr(),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              onPressed: () => _openReceiptScan(
                                context,
                                groupId,
                                baseCurrency,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'receipt.scan_bill_subtitle'.tr(),
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final expense = expenses[i];
                      if (_editMode) {
                        return ExpenseTileSelectable(
                          expense: expense,
                          selected: _selected.contains(expense.id),
                          onToggle: () => _toggleExpense(expense.id),
                        );
                      }
                      return ExpenseTile(
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
                    'common.could_not_load_expenses'.tr(),
                    style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'scan_bill',
            onPressed: () => _openReceiptScan(context, groupId, baseCurrency),
            backgroundColor: _blue,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.document_scanner_rounded),
            label: Text(
              'receipt.scan_bill'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'add_expense',
            onPressed: () {
              HapticUtils.primaryTap();
              context.push(
                AppRouter.addExpense,
                extra: {
                  'groupId': groupId,
                  'groupName': groupName,
                  if (group?.defaultCurrency != null)
                    'groupCurrency': group!.defaultCurrency!,
                },
              );
            },
            backgroundColor: _teal,
            foregroundColor: Colors.black,
            icon: const Icon(Icons.add),
            label: Text(
              'group_detail.add_expense'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ],
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
                'common.all_settled_group'.tr(),
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
                    'common.owed_to_you'.tr(),
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
                    'common.you_owe'.tr(),
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
        title: Text('common.remove_member_title'.tr()),
        content: Text('common.remove_member_confirm'.tr(namedArgs: {'name': member.name})),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('common.remove'.tr()),
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
        SnackBar(content: Text(result.error ?? 'common.could_not_remove_member'.tr())),
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
        'common.no_members_yet'.tr(),
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
              isCreatorMember ? 'common.you_creator'.tr(namedArgs: {'name': m.name}) : m.name,
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
                    tooltip: 'common.remove_member_title'.tr(),
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
// Helpers
// ---------------------------------------------------------------------------

/// Formats [createdAt] (ISO-8601 string) for display in expense tiles.
/// Uses short form ("d MMM") for current-year entries and medium form
/// ("d MMM yyyy") for prior-year entries.
String formatExpenseDate(String? createdAt) {
  if (createdAt == null) return '';
  try {
    final dt = DateTime.parse(createdAt).toLocal();
    if (dt.year == DateTime.now().year) {
      return DateFormatService.instance.formatShort(dt);
    } else {
      return DateFormatService.instance.formatMedium(dt);
    }
  } catch (_) {
    return '';
  }
}

// ---------------------------------------------------------------------------
// Selectable expense tile — used in batch Edit mode
// ---------------------------------------------------------------------------
class ExpenseTileSelectable extends ConsumerWidget {
  const ExpenseTileSelectable({
    super.key,
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final icon = _categoryIcons[expense.category] ?? Icons.attach_money_outlined;
    final label = expense.description.isEmpty ? expense.category : expense.description;
    final displayAmount = formatAmount(expense.originalAmount ?? expense.amount);
    final displayCurrency = expense.originalCurrency ?? expense.currency;
    final baseCurrencyAsync = ref.watch(baseCurrencyProvider);
    final baseCurrency = baseCurrencyAsync.valueOrNull ?? 'USD';

    // Date
    final dateStr = formatExpenseDate(expense.createdAt);

    // ≈ estimate — shown only when displayed currency differs from base
    final showConversion = displayCurrency != baseCurrency && expense.universalUsdAmount != null;
    String? convertedAmount;
    if (showConversion) {
      if (baseCurrency == 'USD') {
        // Direct from universal_usd_amount — no rate lookup needed (rate ≡ 1)
        convertedAmount = (Decimal.tryParse(expense.universalUsdAmount!) ?? Decimal.zero)
            .round(scale: 2)
            .toStringAsFixed(2);
      } else {
        final rateAsync = ref.watch(rateToBaseProvider((from: 'USD', base: baseCurrency)));
        if (rateAsync.valueOrNull != null) {
          convertedAmount = ((Decimal.tryParse(expense.universalUsdAmount!) ?? Decimal.zero) *
              (Decimal.tryParse(rateAsync.valueOrNull!) ?? Decimal.one))
              .round(scale: 2)
              .toStringAsFixed(2);
        }
      }
    }

    final showSecondary = dateStr.isNotEmpty || convertedAmount != null;

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (showSecondary) ...[
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (dateStr.isNotEmpty) ...[
                              Text(
                                dateStr,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                            if (dateStr.isNotEmpty && convertedAmount != null)
                              const SizedBox(width: 6),
                            if (convertedAmount != null) ...[
                              Text(
                                '≈ $baseCurrency $convertedAmount',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
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
    );
  }
}

// ---------------------------------------------------------------------------
// Expense list
// ---------------------------------------------------------------------------
class ExpenseTile extends ConsumerWidget {
  const ExpenseTile({
    super.key,
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
    final icon = expense.iconCodepoint != null
        ? IconData(expense.iconCodepoint!, fontFamily: 'MaterialIcons')
        : (_categoryIcons[expense.category] ?? Icons.attach_money_outlined);
    final iconColor = expense.iconColor != null
        ? Color(expense.iconColor!)
        : theme.colorScheme.onSurfaceVariant;
    final displayAmount = formatAmount(expense.originalAmount ?? expense.amount);
    final displayCurrency = expense.originalCurrency ?? expense.currency;
    final baseCurrencyAsync = ref.watch(baseCurrencyProvider);
    final baseCurrency = baseCurrencyAsync.valueOrNull ?? 'USD';
    // Date
    final dateStr = formatExpenseDate(expense.createdAt);
    // Show conversion when displayed currency differs from base AND we have a USD anchor
    final showConversion = displayCurrency != baseCurrency && expense.universalUsdAmount != null;
    String? convertedAmount;
    if (showConversion) {
      if (baseCurrency == 'USD') {
        // Direct from universal_usd_amount — no rate lookup needed (rate ≡ 1)
        convertedAmount = (Decimal.tryParse(expense.universalUsdAmount!) ?? Decimal.zero)
            .round(scale: 2)
            .toStringAsFixed(2);
      } else {
        final rateAsync = ref.watch(rateToBaseProvider((from: 'USD', base: baseCurrency)));
        if (rateAsync.valueOrNull != null) {
          convertedAmount = ((Decimal.tryParse(expense.universalUsdAmount!) ?? Decimal.zero) *
              (Decimal.tryParse(rateAsync.valueOrNull!) ?? Decimal.one))
              .round(scale: 2)
              .toStringAsFixed(2);
        }
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: SwipeActionCard(
        actionsPanelWidth: 140,
        actions: [
          SwipeAction(
            icon: Icons.edit_outlined,
            label: 'common.edit'.tr(),
            color: _teal,
            onTap: () => context.push(
              '/group/$groupId/expense/${expense.id}',
              extra: {'groupName': groupName},
            ),
          ),
          SwipeAction(
            icon: Icons.delete_outline,
            label: 'common.delete'.tr(),
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
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => context.push(
                AppRouter.groupExpenseDetail,
                extra: {'expense': expense, 'groupId': groupId, 'groupName': groupName},
              ),
              child: Row(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 4, height: 44,
                        decoration: BoxDecoration(
                          color: iconColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(icon, size: 16,
                            color: theme.colorScheme.onSurface.withAlpha(180)),
                      ),
                    ],
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
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          if (dateStr.isNotEmpty) ...[
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          _SplitMethodBadge(expense.splitType),
                          if (convertedAmount != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              '≈ $baseCurrency $convertedAmount',
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$displayCurrency $displayAmount',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: iconColor,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.chevron_right, size: 16, color: Color(0xFF94A3B8)),
                ),
              ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _showContextMenu(BuildContext context, WidgetRef ref) async {
    HapticUtils.primaryTap();
    final uid = await ref.read(setAllRepositoryProvider).ensureUser();
    if (!context.mounted) return;
    final canSettle = uid != null &&
        expense.payerId == uid &&
        expense.groupId != null &&
        expense.category != 'Settlement';

    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.edit_outlined, color: _teal),
              title: Text('groups_screen.edit_expense'.tr()),
              onTap: () => Navigator.of(ctx).pop('edit'),
            ),
            if (canSettle)
              ListTile(
                leading: const Icon(Icons.check_circle_outline, color: Colors.green),
                title: Text('group_detail.settle_group'.tr()),
                subtitle: Text('${expense.currency} ${expense.amount} owed to you'),
                onTap: () => Navigator.of(ctx).pop('settle'),
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: Text('groups_screen.delete_expense_title'.tr(), style: const TextStyle(color: Colors.redAccent)),
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
    } else if (result == 'settle' && uid != null) {
      await _settleExpense(context, ref, uid);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    HapticUtils.primaryTap();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('expense_detail.delete_title'.tr()),
        content: Text(
          'expense_detail.delete_body'.tr(namedArgs: {'label': expense.description.isEmpty ? expense.category : expense.description}),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('common.cancel'.tr())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('common.delete'.tr()),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    final doubleConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('expense_detail.delete_sure_title'.tr()),
        content: Text('expense_detail.delete_sure_body'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text('common.cancel'.tr())),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('common.yes_delete_forever'.tr()),
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
        SnackBar(content: Text('groups_screen.expense_deleted'.tr())),
      );
    }
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
            Text('groups_screen.edit_expense'.tr()),
          ]),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
            const SizedBox(width: 8),
            Text('groups_screen.delete_expense_title'.tr(), style: const TextStyle(color: Colors.redAccent)),
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

  Future<void> _settleExpense(BuildContext context, WidgetRef ref, String uid) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('group_detail.settle_title'.tr()),
        content: Text('group_detail.settle_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: _teal),
            child: Text('common.settle'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final repo = ref.read(setAllRepositoryProvider);
    final ok = await repo.setGroupSettled(expense.groupId!);
    if (!context.mounted) return;
    if (ok) {
      ref.invalidate(myGroupsProvider);
      ref.invalidate(simplifiedDebtsProvider(expense.groupId!));
      ref.invalidate(groupBalanceSummaryProvider(expense.groupId!));
      ref.invalidate(omniActivityProvider);
      HapticUtils.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('group_detail.settled_snack'.tr())),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('group_detail.settle_failed'.tr()),
          backgroundColor: Colors.red,
        ),
      );
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
    this.isCreditor = false,
  });

  final String groupId;
  final SettlementTransaction debt;
  final String amountStr;
  final bool isCreditor;

  @override
  ConsumerState<_SettleButton> createState() => _SettleButtonState();
}

class _SettleButtonState extends ConsumerState<_SettleButton> {
  bool _loading = false;

  Future<void> _settle() async {
    HapticUtils.primaryTap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('group_detail.settle_title'.tr()),
        content: Text('group_detail.settle_body'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(foregroundColor: _teal),
            child: Text('common.settle'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!mounted) return;
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final ok = await ref.read(setAllRepositoryProvider).setGroupSettled(widget.groupId);
      if (!mounted) return;
      if (ok) {
        ref.invalidate(myGroupsProvider);
        ref.invalidate(simplifiedDebtsProvider(widget.groupId));
        ref.invalidate(groupBalanceSummaryProvider(widget.groupId));
        ref.invalidate(omniActivityProvider);
        HapticUtils.success();
      } else {
        messenger.showSnackBar(const SnackBar(
          content: Text('Settlement failed. Please try again.'),
          backgroundColor: Colors.red,
        ));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text('Settlement failed: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: _loading ? null : _settle,
      style: TextButton.styleFrom(
        foregroundColor: _teal,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: _loading
          ? const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
            )
          : Text(
              widget.isCreditor ? 'Mark received' : 'Settle',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
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
                      trailing: (isCurrentUserDebtor || debt.toUserId == currentUid)
                          ? _SettleButton(
                              groupId: groupId,
                              debt: debt,
                              amountStr: amountStr,
                              isCreditor: debt.toUserId == currentUid && !isCurrentUserDebtor,
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

// ---------------------------------------------------------------------------
// Group hero bar — shows avatar/icon/colour strip at top of detail screen
// ---------------------------------------------------------------------------
const Map<String, IconData> _kGroupIconMap = {
  'groups':     Icons.groups_outlined,
  'home':       Icons.home_outlined,
  'flight':     Icons.flight_outlined,
  'hotel':      Icons.hotel_outlined,
  'restaurant': Icons.restaurant_outlined,
  'shopping':   Icons.shopping_bag_outlined,
  'sports':     Icons.sports_soccer_outlined,
  'music':      Icons.music_note_outlined,
  'school':     Icons.school_outlined,
  'work':       Icons.work_outline,
  'car':        Icons.directions_car_outlined,
  'beach':      Icons.beach_access_outlined,
  'party':      Icons.celebration_outlined,
  'health':     Icons.favorite_outline,
  'coffee':     Icons.local_cafe_outlined,
};

class _GroupHeroBar extends ConsumerWidget {
  const _GroupHeroBar({required this.group});
  final GroupModel group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme       = Theme.of(context);
    final accentColor = group.colorValue != null
        ? Color(group.colorValue!)
        : _teal;
    final iconData    = _kGroupIconMap[group.iconName] ?? Icons.groups_outlined;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: accentColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: accentColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            // Avatar or icon
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(14),
              ),
              child: group.avatarUrl != null
                  ? _GroupAvatarImage(storagePath: group.avatarUrl!, accent: accentColor, iconData: iconData)
                  : Icon(iconData, size: 24, color: accentColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        group.type.name == 'direct' ? 'Direct' : 'Group',
                        style: TextStyle(
                          fontSize: 11,
                          color: accentColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (group.defaultCurrency != null) ...
                        [
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: accentColor.withValues(alpha: 0.4),
                                width: 0.8,
                              ),
                            ),
                            child: Text(
                              group.defaultCurrency!,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: accentColor,
                                letterSpacing: 0.3,
                              ),
                            ),
                          ),
                        ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupAvatarImage extends ConsumerWidget {
  const _GroupAvatarImage({
    required this.storagePath,
    required this.accent,
    required this.iconData,
  });
  final String storagePath;
  final Color accent;
  final IconData iconData;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(_groupDetailAvatarProvider(storagePath));
    return urlAsync.when(
      data: (url) => url != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      Icon(iconData, size: 24, color: accent)),
            )
          : Icon(iconData, size: 24, color: accent),
      loading: () => const Center(
          child: SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))),
      error: (_, _) => Icon(iconData, size: 24, color: accent),
    );
  }
}

final _groupDetailAvatarProvider =
    FutureProvider.family<String?, String>((ref, storagePath) async {
  return ref
      .watch(setAllRepositoryProvider)
      .generateGroupAvatarSignedUrl(storagePath);
});

// ---------------------------------------------------------------------------
// Split method badge
// ---------------------------------------------------------------------------
class _SplitMethodBadge extends StatelessWidget {
  const _SplitMethodBadge(this.splitType);
  final SplitType splitType;

  static const _kEven       = Color(0xFF00D9B0);
  static const _kPercentage = Color(0xFF6366F1);
  static const _kExact      = Color(0xFFF59E0B);

  @override
  Widget build(BuildContext context) {
    final (label, icon, color) = switch (splitType) {
      SplitType.even   => ('Evenly',     Icons.balance_outlined,     _kEven),
      SplitType.manual => ('Exact',      Icons.attach_money_outlined, _kExact),
      SplitType.parts  => ('By Parts',   Icons.pie_chart_outline,     _kPercentage),
    };
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 10, color: color.withValues(alpha: 0.8)),
        const SizedBox(width: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: color.withValues(alpha: 0.8),
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }
}

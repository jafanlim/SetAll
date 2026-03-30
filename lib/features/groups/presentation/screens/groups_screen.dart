import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/amount_formatter.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/utils/navigation_utils.dart';
import '../../../../core/widgets/app_top_button.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../core/widgets/swipe_action_card.dart';
import '../../../../data/models/expense_model.dart';
import '../../../../core/config/auth_config.dart';
import '../../../../data/models/group_model.dart';
import '../../../settings/services/pdf_export_service.dart';

const _teal       = Color(0xFF00D9B0);
const _tealDim    = Color(0x2600D9B0);
const _orange     = Color(0xFFFF8C42);
const _orangeDim = Color(0x26FF8C42);
const _brandOrange = Color(0xFFF97316);

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

enum _GroupSort      { nameAZ, nameZA }
enum _ActivityFilter { all, income, expense }
enum _ActivitySort   { newest, oldest, largest, smallest }

class GroupsScreen extends ConsumerStatefulWidget {
  const GroupsScreen({super.key});

  @override
  ConsumerState<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends ConsumerState<GroupsScreen> {
  bool _editMode = false;
  final Set<String> _selected = {};
  _GroupSort        _groupSort   = _GroupSort.nameAZ;
  _ActivityFilter   _actFilter   = _ActivityFilter.all;
  _ActivitySort     _actSort     = _ActivitySort.newest;
  String?           _actCatFilter;
  Set<String>       _groupNameFilter  = {};
  final Set<int>    _groupColorFilter = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncServiceProvider).performFullSync().then((_) {
        if (mounted) {
          ref.invalidate(balanceSummaryProvider);
          ref.invalidate(recentExpensesProvider);
        }
      });
    });
  }

  void _toggleEditMode() {
    HapticUtils.selection();
    setState(() {
      _editMode = !_editMode;
      _selected.clear();
    });
  }

  void _toggleItem(String id) {
    HapticUtils.selection();
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
      } else {
        _selected.add(id);
      }
    });
  }

  void _selectAll(List<String> ids) {
    HapticUtils.selection();
    setState(() => _selected.addAll(ids));
  }

  void _deselectAll() {
    HapticUtils.selection();
    setState(() => _selected.clear());
  }

  Future<void> _showGroupNamePicker(BuildContext ctx, List<GroupModel> groups) async {
    final tempSelected = Set<String>.from(_groupNameFilter);
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setLocal) => AlertDialog(
          title: Text('groups_screen.filter_by_group'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          contentPadding: const EdgeInsets.fromLTRB(0, 12, 0, 0),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: groups.map((g) {
                final accent = g.colorValue != null ? Color(g.colorValue!) : _teal;
                return CheckboxListTile(
                  value: tempSelected.contains(g.id),
                  onChanged: (v) => setLocal(() {
                    if (v == true) { tempSelected.add(g.id); } else { tempSelected.remove(g.id); }
                  }),
                  title: Text(g.name,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  secondary: Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  activeColor: accent,
                  checkColor: Colors.white,
                  controlAffinity: ListTileControlAffinity.trailing,
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => setLocal(() => tempSelected.clear()),
              child: Text('common.clear_all'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dlgCtx, true),
              child: Text('common.apply'.tr()),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      setState(() => _groupNameFilter = tempSelected);
    }
  }

  bool _batchDeleting = false;

  List<GroupModel> _applyGroupSort(List<GroupModel> all) {
    var list = List<GroupModel>.from(all);
    if (_groupNameFilter.isNotEmpty) {
      list = list.where((g) => _groupNameFilter.contains(g.id)).toList();
    }
    if (_groupColorFilter.isNotEmpty) {
      list = list.where(
          (g) => g.colorValue != null && _groupColorFilter.contains(g.colorValue)).toList();
    }
    switch (_groupSort) {
      case _GroupSort.nameAZ: list.sort((a, b) => a.name.compareTo(b.name));
      case _GroupSort.nameZA: list.sort((a, b) => b.name.compareTo(a.name));
    }
    return list;
  }

  List<ExpenseModel> _applyActivityFilterSort(List<ExpenseModel> all,
      {List<GroupModel> groups = const []}) {
    final colorById = <String, int?>{for (final g in groups) g.id: g.colorValue};
    var list = all.where((e) {
      if (_groupNameFilter.isNotEmpty && !_groupNameFilter.contains(e.groupId)) return false;
      if (_groupColorFilter.isNotEmpty) {
        final cv = e.groupId != null ? colorById[e.groupId] : null;
        if (cv == null || !_groupColorFilter.contains(cv)) return false;
      }
      if (_actCatFilter != null) {
        return (e.category.isEmpty ? 'Other' : e.category) == _actCatFilter;
      }
      switch (_actFilter) {
        case _ActivityFilter.all:     return true;
        case _ActivityFilter.income:  return e.isIncome;
        case _ActivityFilter.expense: return !e.isIncome;
      }
    }).toList();
    switch (_actSort) {
      case _ActivitySort.newest:
        list.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
      case _ActivitySort.oldest:
        list.sort((a, b) => (a.createdAt ?? '').compareTo(b.createdAt ?? ''));
      case _ActivitySort.largest:
        list.sort((a, b) {
          final av = Decimal.tryParse(a.universalUsdAmount ?? a.amount) ?? Decimal.zero;
          final bv = Decimal.tryParse(b.universalUsdAmount ?? b.amount) ?? Decimal.zero;
          return bv.compareTo(av);
        });
      case _ActivitySort.smallest:
        list.sort((a, b) {
          final av = Decimal.tryParse(a.universalUsdAmount ?? a.amount) ?? Decimal.zero;
          final bv = Decimal.tryParse(b.universalUsdAmount ?? b.amount) ?? Decimal.zero;
          return av.compareTo(bv);
        });
    }
    return list;
  }

  Future<void> _deleteBatch() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('groups_screen.delete_title'.tr()),
        content: Text(
          count == 1
              ? 'groups_screen.delete_confirm_one'.tr()
              : 'groups_screen.delete_confirm'.tr(namedArgs: {'count': count.toString()}),
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
    setState(() => _batchDeleting = true);
    final repo = ref.read(setAllRepositoryProvider);
    final ok = await repo.deleteGroups(_selected.toList());
    if (!mounted) return;
    setState(() => _batchDeleting = false);
    // Always refresh — some deletes may have succeeded even if not all did.
    HapticUtils.success();
    ref.invalidate(myGroupsProvider);
    ref.invalidate(balanceSummaryProvider);
    ref.invalidate(recentExpensesProvider);
    ref.invalidate(allGroupMembersBatchProvider);
    setState(() {
      _editMode = false;
      _selected.clear();
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('groups_screen.error_delete'.tr())),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme         = Theme.of(context);
    final summaryAsync  = ref.watch(balanceSummaryProvider);
    final groupsAsync   = ref.watch(myGroupsProvider);
    final expensesAsync = ref.watch(recentExpensesProvider);

    return Stack(
      children: [
      Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'groups.title'.tr(),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -0.3,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        automaticallyImplyLeading: false,
        actions: _editMode
            ? [
                groupsAsync.whenData((groups) {
                  final allSelected = groups.isNotEmpty &&
                      groups.every((g) => _selected.contains(g.id));
                  return TextButton(
                    onPressed: allSelected
                        ? _deselectAll
                        : () => _selectAll(groups.map((g) => g.id).toList()),
                    child: Text(allSelected ? 'common.deselect_all'.tr() : 'common.select_all'.tr()),
                  );
                }).valueOrNull ?? const SizedBox.shrink(),
                TextButton(
                  onPressed: _toggleEditMode,
                  child: Text('common.cancel'.tr()),
                ),
                if (_selected.isNotEmpty)
                  TextButton.icon(
                    onPressed: _deleteBatch,
                    icon: const Icon(Icons.delete_outline, size: 16, color: _brandOrange),
                    label: Text(
                      'common.delete_count'.tr(namedArgs: {'count': _selected.length.toString()}),
                      style: const TextStyle(color: _brandOrange),
                    ),
                  ),
              ]
            : [
                AppTopPopupButton<_ActivitySort>(
                  icon: Icons.swap_vert_rounded,
                  tooltip: 'groups_screen.sort_activity_tooltip'.tr(),
                  initialValue: _actSort,
                  onSelected: (s) { HapticUtils.selection(); setState(() => _actSort = s); },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: _ActivitySort.newest,   child: Text('common.newest_first'.tr())),
                    PopupMenuItem(value: _ActivitySort.oldest,   child: Text('common.oldest_first'.tr())),
                    PopupMenuItem(value: _ActivitySort.largest,  child: Text('common.largest_first'.tr())),
                    PopupMenuItem(value: _ActivitySort.smallest, child: Text('common.smallest_first'.tr())),
                  ],
                ),
                const SizedBox(width: 4),
                AppTopButton(
                  icon: Icons.picture_as_pdf_outlined,
                  tooltip: 'Export all groups as PDF',
                  onPressed: () async {
                    HapticUtils.lightTap();
                    await PdfExportService().exportAllGroupsAsPdf();
                  },
                ),
                const SizedBox(width: 4),
                AppTopPopupButton<_GroupSort>(
                  icon: Icons.sort_rounded,
                  tooltip: 'groups_screen.sort_groups_tooltip'.tr(),
                  initialValue: _groupSort,
                  onSelected: (s) { HapticUtils.selection(); setState(() => _groupSort = s); },
                  itemBuilder: (_) => [
                    PopupMenuItem(value: _GroupSort.nameAZ, child: Text('common.name_az'.tr())),
                    PopupMenuItem(value: _GroupSort.nameZA, child: Text('common.name_za'.tr())),
                  ],
                ),
                const SizedBox(width: 4),
                AppTopButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'common.refresh'.tr(),
                  onPressed: () async {
                    HapticUtils.lightTap();
                    await ref.read(syncServiceProvider).performFullSync();
                    if (!mounted) return;
                    ref.invalidate(myGroupsProvider);
                    ref.invalidate(balanceSummaryProvider);
                    ref.invalidate(recentExpensesProvider);
                    ref.invalidate(omniActivityProvider);
                  },
                ),
                const SizedBox(width: 4),
                TextButton(
                  onPressed: _toggleEditMode,
                  child: Text('common.edit'.tr()),
                ),
              ],
      ),
      floatingActionButton: _editMode
          ? null
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                FloatingActionButton.extended(
                  heroTag: 'fab_new_group',
                  onPressed: () async {
                    HapticUtils.primaryTap();
                    await context.push(AppRouter.createGroup);
                    if (!mounted) return;
                    ref.invalidate(myGroupsProvider);
                  },
                  backgroundColor: _teal.withValues(alpha: 0.15),
                  foregroundColor: _teal,
                  elevation: 2,
                  icon: const Icon(Icons.group_add_outlined),
                  label: Text(
                    'groups_screen.new_group'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
                const SizedBox(height: 10),
                FloatingActionButton.extended(
                  heroTag: 'fab_add_expense',
                  onPressed: () {
                    HapticUtils.primaryTap();
                    context.push(AppRouter.groupPicker);
                  },
                  backgroundColor: _teal,
                  foregroundColor: Colors.black,
                  icon: const Icon(Icons.add),
                  label: Text(
                    'groups_screen.add_expense'.tr(),
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                ),
              ],
            ),
      body: RefreshIndicator(
        color: _teal,
        onRefresh: () async {
          HapticUtils.lightTap();
          await ref.read(syncServiceProvider).performFullSync();
          if (!mounted) return;
          ref.invalidate(balanceSummaryProvider);
          ref.invalidate(myGroupsProvider);
          ref.invalidate(recentExpensesProvider);
        },
        child: CustomScrollView(
          slivers: [
            // ── Net Balance Hero ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: summaryAsync.when(
                  skipLoadingOnReload: true,
                  data: (summary) {
                    final owed = Decimal.tryParse(summary.youAreOwed) ?? Decimal.zero;
                    final owe  = Decimal.tryParse(summary.youOwe)     ?? Decimal.zero;
                    final net  = owed - owe;
                    final isPos = net >= Decimal.zero;
                    return _NetBalanceHero(
                      netDisplay:  (isPos ? net : -net).toStringAsFixed(2),
                      currency:    summary.currency,
                      isPositive:  isPos,
                      youAreOwed:  summary.youAreOwed,
                      youOwe:      summary.youOwe,
                    );
                  },
                  loading: () => const _NetBalanceHero.loading(),
                  error: (_, _) => const _NetBalanceHero.error(),
                ),
              ),
            ),

            // ── Groups section header ──────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'groups.your_groups'.tr(),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700, fontSize: 13,
                    letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),

            // ── Group filter (name dropdown + color dots) ──────────────────
            groupsAsync.when(
              data: (groups) {
                if (groups.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
                final uniqueColors = <int>{
                  for (final g in groups)
                    if (g.colorValue != null) g.colorValue!
                }.toList();
                final hasFilters = _groupNameFilter.isNotEmpty || _groupColorFilter.isNotEmpty;
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // ── Name dropdown ──────────────────────────────
                          GestureDetector(
                            onTap: () => _showGroupNamePicker(context, groups),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: _groupNameFilter.isNotEmpty ? _teal.withAlpha(38) : Colors.transparent,
                                border: Border.all(
                                  color: _groupNameFilter.isNotEmpty
                                      ? _teal
                                      : theme.colorScheme.outline.withAlpha(100),
                                  width: _groupNameFilter.isNotEmpty ? 1.5 : 1,
                                ),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.group_outlined, size: 14,
                                      color: _groupNameFilter.isNotEmpty
                                          ? _teal
                                          : theme.colorScheme.onSurfaceVariant),
                                  const SizedBox(width: 6),
                                  Text(
                                    _groupNameFilter.isEmpty
                                        ? 'groups.title'.tr()
                                        : _groupNameFilter.length == 1
                                            ? 'dashboard.group_count_one'.tr(namedArgs: {'count': '1'})
                                            : 'dashboard.group_count_other'.tr(namedArgs: {'count': _groupNameFilter.length.toString()}),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _groupNameFilter.isNotEmpty
                                          ? _teal
                                          : theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.expand_more_rounded, size: 14,
                                      color: _groupNameFilter.isNotEmpty
                                          ? _teal
                                          : theme.colorScheme.onSurfaceVariant),
                                ],
                              ),
                            ),
                          ),
                          // ── Color dots ─────────────────────────────────
                          if (uniqueColors.isNotEmpty) ...[const SizedBox(width: 8),
                            Container(width: 1, height: 20,
                                color: theme.colorScheme.outlineVariant),
                            const SizedBox(width: 8),
                            ...uniqueColors.map((cv) {
                              final c = Color(cv);
                              final isSelected = _groupColorFilter.contains(cv);
                              return Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: GestureDetector(
                                  onTap: () => setState(() {
                                    if (isSelected) {
                                      _groupColorFilter.remove(cv);
                                    } else {
                                      _groupColorFilter.add(cv);
                                    }
                                  }),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 160),
                                    width: 28, height: 28,
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: isSelected ? Colors.white : Colors.transparent,
                                        width: 2.5,
                                      ),
                                      boxShadow: isSelected
                                          ? [BoxShadow(color: c.withAlpha(160),
                                              blurRadius: 6, spreadRadius: 1)]
                                          : null,
                                    ),
                                    child: isSelected
                                        ? const Icon(Icons.check, size: 12, color: Colors.white)
                                        : null,
                                  ),
                                ),
                              );
                            }),
                          ],
                          // ── Clear all ──────────────────────────────────
                          if (hasFilters) ...[const SizedBox(width: 4),
                            GestureDetector(
                              onTap: () => setState(() {
                                _groupNameFilter.clear();
                                _groupColorFilter.clear();
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                      color: theme.colorScheme.outline.withAlpha(100)),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.close, size: 12,
                                        color: theme.colorScheme.onSurfaceVariant),
                                    const SizedBox(width: 4),
                                    Text('common.clear'.tr(), style: TextStyle(
                                        fontSize: 11,
                                        color: theme.colorScheme.onSurfaceVariant)),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            // ── Group list ────────────────────────────────────────────────
            groupsAsync.when(
              data: (groups) {
                final sorted = _applyGroupSort(groups);
                return sorted.isEmpty
                  ? SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                        child: Center(
                          child: Text(
                            'groups.no_groups'.tr(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ))
                  : SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (ctx, i) {
                          final group = sorted[i];
                          if (_editMode) {
                            return _GroupCardSelectable(
                              group: group,
                              selected: _selected.contains(group.id),
                              onToggle: () => _toggleItem(group.id),
                            );
                          }
                          return _GroupCard(group: group);
                        },
                        childCount: sorted.length,
                      ));
              },
              loading: () => const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(24),
                      child: Center(child: CircularProgressIndicator()))),
              error: (_, _) => SliverToBoxAdapter(
                  child: Padding(padding: const EdgeInsets.all(24),
                      child: Center(child: Text('groups_screen.could_not_load'.tr(),
                          style: const TextStyle(color: Colors.redAccent))))),
            ),

            // ── Recent Activity header + filter chips ─────────────────────
            if (!_editMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'groups_screen.recent_activity'.tr(),
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w700, fontSize: 13,
                            letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        expensesAsync.whenData((e) {
                          final filtered = _applyActivityFilterSort(e, groups: groupsAsync.valueOrNull ?? []);
                          return '${filtered.length} item${filtered.length == 1 ? '' : 's'}';
                        }).valueOrNull ?? '',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ),

            // ── Activity filter chips ─────────────────────────────────────
            if (!_editMode)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _FilterChip(
                          label: 'wallet_screen.filter_all'.tr(),
                          selected: _actCatFilter == null && _actFilter == _ActivityFilter.all,
                          onTap: () => setState(() { _actFilter = _ActivityFilter.all; _actCatFilter = null; }),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'wallet_screen.filter_income'.tr(),
                          selected: _actCatFilter == null && _actFilter == _ActivityFilter.income,
                          color: _teal,
                          onTap: () => setState(() { _actFilter = _ActivityFilter.income; _actCatFilter = null; }),
                        ),
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: 'wallet_screen.filter_expense'.tr(),
                          selected: _actCatFilter == null && _actFilter == _ActivityFilter.expense,
                          color: _orange,
                          onTap: () => setState(() { _actFilter = _ActivityFilter.expense; _actCatFilter = null; }),
                        ),
                        if (_actCatFilter != null) ...[const SizedBox(width: 8),
                          _FilterChip(
                            label: _actCatFilter!,
                            selected: true,
                            color: _brandOrange,
                            onTap: () => setState(() => _actCatFilter = null),
                            trailing: const Icon(Icons.close, size: 11, color: Colors.white),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

            // ── Recent Activity list ──────────────────────────────────────
            if (!_editMode)
              groupsAsync.when(
                data: (groups) {
                  final groupNameMap = {for (final g in groups) g.id: g.name};
                  return expensesAsync.when(
                    data: (allExpenses) {
                      final expenses = _applyActivityFilterSort(allExpenses, groups: groups);
                      if (expenses.isEmpty) {
                        return SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                            child: Center(
                              child: Column(children: [
                                Icon(Icons.receipt_long_outlined,
                                    size: 40, color: theme.colorScheme.onSurfaceVariant.withAlpha(100)),
                                const SizedBox(height: 12),
                                Text(
                                  allExpenses.isEmpty
                                      ? 'groups_screen.no_expenses_yet'.tr()
                                      : 'groups_screen.no_expenses_filter'.tr(),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant),
                                  textAlign: TextAlign.center,
                                ),
                              ]),
                            ),
                          ),
                        );
                      }
                      final groupMap = {for (final g in groups) g.id: g};
                      return SliverList(
                        delegate: SliverChildBuilderDelegate(
                          (ctx, i) => _ActivityTile(
                            expense:   expenses[i],
                            groupId:   expenses[i].groupId,
                            groupName: groupNameMap[expenses[i].groupId] ?? '',
                            group:     expenses[i].groupId != null ? groupMap[expenses[i].groupId] : null,
                            onCategoryTap: (cat) => setState(() {
                              _actCatFilter = cat;
                              _actFilter = _ActivityFilter.all;
                            }),
                          ),
                          childCount: expenses.length,
                        ),
                      );
                    },
                    loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
                    error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
                  );
                },
                loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
                error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 96)),
          ],
        ),
      ),
    ),
    if (_batchDeleting)
      const Positioned.fill(
        child: ColoredBox(
          color: Color(0x66000000),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
  ],
);
  }
}

// ---------------------------------------------------------------------------
// Net balance hero
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
      : netDisplay = '—', currency = '', isPositive = true,
        youAreOwed = '0', youOwe = '0', _loading = true, _error = false;

  const _NetBalanceHero.error()
      : netDisplay = '—', currency = '', isPositive = true,
        youAreOwed = '0', youOwe = '0', _loading = false, _error = true;

  final String netDisplay;
  final String currency;
  final bool isPositive;
  final String youAreOwed;
  final String youOwe;
  final bool _loading;
  final bool _error;

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final accent = isPositive ? _teal : _orange;
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(width: 7, height: 7,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(isPositive ? 'groups_screen.overall_owed'.tr() : 'groups_screen.overall_owe'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant, fontSize: 12)),
          ]),
          const SizedBox(height: 6),
          if (_loading)
            const SizedBox(height: 28, child: LinearProgressIndicator())
          else
            Text('$currency $netDisplay',
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 26, letterSpacing: -0.5,
                    color: _error ? theme.colorScheme.onSurfaceVariant : accent),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _BalancePill(label: 'groups_screen.owed_to_you'.tr(), amount: youAreOwed,
                currency: currency, color: _teal, bgColor: _tealDim)),
            const SizedBox(width: 8),
            Expanded(child: _BalancePill(label: 'groups_screen.you_owe'.tr(), amount: youOwe,
                currency: currency, color: _orange, bgColor: _orangeDim)),
          ]),
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
          Text('$currency $amount',
            style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
            overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Selectable group card — used in Edit mode
// ---------------------------------------------------------------------------
class _GroupCardSelectable extends ConsumerWidget {
  const _GroupCardSelectable({
    required this.group,
    required this.selected,
    required this.onToggle,
  });

  final GroupModel group;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final balanceAsync = ref.watch(groupBalanceSummaryProvider(group.id));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GestureDetector(
        onTap: onToggle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _brandOrange : Colors.transparent,
              width: 2,
            ),
          ),
          child: GlassCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? _brandOrange : Colors.transparent,
                      border: Border.all(
                        color: selected ? _brandOrange : theme.colorScheme.onSurfaceVariant,
                        width: 2,
                      ),
                    ),
                    child: selected
                        ? const Icon(Icons.check, size: 14, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _tealDim,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
                        style: const TextStyle(
                          color: _teal, fontWeight: FontWeight.w800, fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          group.name,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700, fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        balanceAsync.when(
                          data: (s) {
                            final owed = Decimal.tryParse(s.youAreOwed) ?? Decimal.zero;
                            final owe  = Decimal.tryParse(s.youOwe)     ?? Decimal.zero;
                            if (owed == Decimal.zero && owe == Decimal.zero) {
                              return Text('Settled up',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                      color: _teal, fontSize: 11));
                            }
                            return Text(
                              owed > Decimal.zero
                                  ? '+${s.currency} ${s.youAreOwed}'
                                  : '-${s.currency} ${s.youOwe}',
                              style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600,
                                color: owed > Decimal.zero ? _teal : _orange,
                              ),
                            );
                          },
                          loading: () => const SizedBox(height: 11),
                          error: (_, _) => const SizedBox.shrink(),
                        ),
                      ],
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
}

// ---------------------------------------------------------------------------
// Group card — swipe to edit/delete, long-press context menu, right-click menu
// ---------------------------------------------------------------------------
class _GroupCard extends ConsumerStatefulWidget {
  const _GroupCard({required this.group});
  final GroupModel group;

  @override
  ConsumerState<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends ConsumerState<_GroupCard> {
  bool _deleting = false;

  Future<void> _rename() async {
    HapticUtils.primaryTap();
    final ctrl = TextEditingController(text: widget.group.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Group name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final newName = ctrl.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (confirmed != true || newName.isEmpty || newName == widget.group.name) return;
    final ok = await ref.read(setAllRepositoryProvider).renameGroup(widget.group.id, newName);
    if (!mounted) return;
    if (ok) {
      ref.invalidate(myGroupsProvider);
      HapticUtils.success();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not rename. Only the group creator can rename.')),
      );
    }
  }

  Future<void> _delete({bool force = false}) async {
    HapticUtils.primaryTap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(force ? 'Force delete group?' : 'Delete group?'),
        content: Text(
          force
              ? 'Force-delete "${widget.group.name}"? This will also purge all its expenses and splits from the server.'
              : 'Delete "${widget.group.name}"? You can restore it from the Activity screen within 12 months.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: force ? _brandOrange : Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(force ? 'Force Delete' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    final repo = ref.read(setAllRepositoryProvider);
    final ok = force
        ? await repo.forceDeleteGroup(widget.group.id)
        : await repo.deleteGroup(widget.group.id);
    if (!mounted) return;
    setState(() => _deleting = false);
    if (ok) {
      ref.invalidate(myGroupsProvider);
      ref.invalidate(balanceSummaryProvider);
      ref.invalidate(recentExpensesProvider);
      HapticUtils.success();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete group. Try Force Delete from the long-press menu.')),
      );
    }
  }

  Future<void> _showContextMenu(BuildContext context) async {
    HapticUtils.primaryTap();
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: _teal),
              title: const Text('Rename group'),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Delete group', style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined, color: _brandOrange),
              title: const Text('Force Delete', style: TextStyle(color: _brandOrange)),
              subtitle: const Text('Purges all expenses from server', style: TextStyle(fontSize: 11)),
              onTap: () => Navigator.of(ctx).pop('force_delete'),
            ),
          ],
        ),
      ),
    );
    if (result == 'rename') _rename();
    if (result == 'delete') _delete();
    if (result == 'force_delete') _delete(force: true);
  }

  Future<void> _showRightClickMenu(BuildContext context, Offset position) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: Row(children: [
            const Icon(Icons.edit_outlined, size: 16, color: _teal),
            const SizedBox(width: 8),
            const Text('Rename group'),
          ]),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Delete group', style: TextStyle(color: Colors.redAccent)),
          ]),
        ),
        const PopupMenuItem(
          value: 'force_delete',
          child: Row(children: [
            Icon(Icons.delete_forever_outlined, size: 16, color: _brandOrange),
            SizedBox(width: 8),
            Text('Force Delete', style: TextStyle(color: _brandOrange)),
          ]),
        ),
      ],
    );
    if (result == 'rename') _rename();
    if (result == 'delete') _delete();
    if (result == 'force_delete') _delete(force: true);
  }

  static const _kStorageBase =
      '${AuthConfig.supabaseUrl}/storage/v1/object/public/group-avatars/';

  static String? _resolveAvatarUrl(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    if (raw.startsWith('http')) return raw;
    return '$_kStorageBase$raw';
  }

  // Map icon name -> IconData for the group card avatar.
  static IconData _iconForName(String? name) {
    const iconMap = {
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
    return iconMap[name] ?? Icons.groups_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme        = Theme.of(context);
    final allMembersMap = ref.watch(allGroupMembersBatchProvider);
    final membersAsync  = allMembersMap.whenData(
      (map) => map[widget.group.id] ?? [],
    );
    final balanceAsync = ref.watch(groupBalanceSummaryProvider(widget.group.id));

    final group       = widget.group;
    final accentColor = group.colorValue != null ? Color(group.colorValue!) : _teal;
    final bgColor     = accentColor.withValues(alpha: 0.15);

    return Stack(
      children: [
      Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SwipeActionCard(
        actionsPanelWidth: 140,
        actions: [
          SwipeAction(icon: Icons.edit_outlined,  label: 'Edit',   color: _teal,            onTap: _rename),
          SwipeAction(icon: Icons.delete_outline, label: 'Delete', color: Colors.redAccent, onTap: _delete),
        ],
        child: GestureDetector(
          onLongPress: () => _showContextMenu(context),
          onSecondaryTapUp: defaultTargetPlatform == TargetPlatform.macOS
              ? (d) => _showRightClickMenu(context, d.globalPosition)
              : null,
          child: GlassCard(
            child: InkWell(
              onTap: () {
                HapticUtils.lightTap();
                navigateToGroup(
                  context: context,
                  ref: ref,
                  groupId: widget.group.id,
                  groupName: widget.group.name,
                  group: widget.group,
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // ── Group avatar ────────────────────────────────────────
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _resolveAvatarUrl(group.avatarUrl) != null
                            ? Image.network(
                                _resolveAvatarUrl(group.avatarUrl)!,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Center(
                                  child: Icon(Icons.groups_outlined, size: 20, color: accentColor),
                                ),
                              )
                            : Center(
                                child: group.iconName != null
                                    ? Icon(_iconForName(group.iconName), size: 20, color: accentColor)
                                    : Text(
                                        group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
                                        style: TextStyle(
                                          color: accentColor,
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                        ),
                                      ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // ── Group info ──────────────────────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.group.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          membersAsync.when(
                            data: (members) => Text(
                              '${members.length} member${members.length == 1 ? '' : 's'}',
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                            ),
                            loading: () => const SizedBox(height: 11),
                            error: (_, _) => const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 4),
                          balanceAsync.when(
                            data: (s) {
                              final owed = Decimal.tryParse(s.youAreOwed) ?? Decimal.zero;
                              final owe  = Decimal.tryParse(s.youOwe)     ?? Decimal.zero;
                              if (owed == Decimal.zero && owe == Decimal.zero) {
                                return Text(
                                  'Settled up',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: _teal,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              }
                              return RichText(
                                text: TextSpan(
                                  style: const TextStyle(fontSize: 11),
                                  children: [
                                    if (owed > Decimal.zero)
                                      TextSpan(
                                        text: '+${s.currency} ${s.youAreOwed}',
                                        style: const TextStyle(color: _teal, fontWeight: FontWeight.w600),
                                      ),
                                    if (owed > Decimal.zero && owe > Decimal.zero)
                                      const TextSpan(text: '  '),
                                    if (owe > Decimal.zero)
                                      TextSpan(
                                        text: '-${s.currency} ${s.youOwe}',
                                        style: const TextStyle(color: _orange, fontWeight: FontWeight.w600),
                                      ),
                                  ],
                                ),
                              );
                            },
                            loading: () => const SizedBox(height: 11),
                            error: (_, _) => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),

                    // ── Quick invite icon ────────────────────────────────────
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.person_add_outlined,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          HapticUtils.lightTap();
                          context.push(
                            '/group/${widget.group.id}/invite',
                            extra: {'groupName': widget.group.name},
                          );
                        },
                        tooltip: 'Add member',
                      ),
                    ),

                    const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
    if (_deleting)
      const Positioned.fill(
        child: ColoredBox(
          color: Color(0x66000000),
          child: Center(
            child: CircularProgressIndicator(),
          ),
        ),
      ),
  ],
);
  }
}

// ---------------------------------------------------------------------------
// Activity tile  (tap → Edit, swipe left → Delete, right-click → menu)
// ---------------------------------------------------------------------------
class _ActivityTile extends ConsumerWidget {
  const _ActivityTile({
    required this.expense,
    required this.groupId,
    required this.groupName,
    this.group,
    this.onCategoryTap,
  });
  final ExpenseModel expense;
  final String? groupId;
  final String groupName;
  final GroupModel? group;
  final void Function(String category)? onCategoryTap;

  static const Map<String, IconData> _categoryIcons = {
    'Food & drink': Icons.restaurant_outlined,
    'Transport': Icons.directions_car_outlined,
    'Entertainment': Icons.movie_outlined,
    'Bills & utilities': Icons.receipt_long_outlined,
    'Shopping': Icons.shopping_bag_outlined,
    'Travel': Icons.flight_outlined,
    'Other': Icons.category_outlined,
  };

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    HapticUtils.primaryTap();
    final confirmed = await showDialog<bool>(
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
    if (confirmed != true || !context.mounted) return;
    await ref.read(setAllRepositoryProvider).deleteExpense(expense.id);
    ref.invalidate(recentExpensesProvider);
    ref.invalidate(balanceSummaryProvider);
    ref.invalidate(omniActivityProvider);
    if (context.mounted) {
      HapticUtils.success();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense deleted')),
      );
    }
  }

  Future<void> _showLongPressMenu(BuildContext context, WidgetRef ref) async {
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
    if (result == 'edit' && groupId != null) {
      context.push('/group/$groupId/expense/${expense.id}', extra: {'groupName': ''});
    } else if (result == 'delete') {
      _delete(context, ref);
    }
  }

  Future<void> _showRightClickMenu(BuildContext context, WidgetRef ref, Offset position) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(children: [
            Icon(Icons.edit_outlined, size: 16, color: _teal),
            const SizedBox(width: 8),
            const Text('Edit expense'),
          ]),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Delete expense', style: TextStyle(color: Colors.redAccent)),
          ]),
        ),
      ],
    );
    if (!context.mounted) return;
    if (result == 'edit' && groupId != null) {
      context.push('/group/$groupId/expense/${expense.id}', extra: {'groupName': ''});
    } else if (result == 'delete') {
      _delete(context, ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final icon  = _categoryIcons[expense.category] ?? Icons.attach_money_outlined;
    final displayAmount   = formatAmount(expense.originalAmount ?? expense.amount);
    final displayCurrency = expense.originalCurrency ?? expense.currency;

    // Group visual identity
    final groupAccent = group?.colorValue != null ? Color(group!.colorValue!) : null;
    final groupIcon   = _kGroupIconMap[group?.iconName] ?? icon;
    // Base-currency equivalent
    final baseCcyAsync      = ref.watch(baseCurrencyProvider);
    final baseCcy           = baseCcyAsync.valueOrNull ?? 'USD';
    final entryCcy          = expense.currency.isEmpty ? 'USD' : expense.currency;
    final showConversion    = entryCcy != baseCcy;
    final rateAsync         = showConversion
        ? ref.watch(rateToBaseProvider((from: 'USD', base: baseCcy)))
        : null;
    final rateUsdToBase     = Decimal.tryParse(rateAsync?.valueOrNull ?? '1') ?? Decimal.one;
    final usdAmt            = Decimal.tryParse(expense.universalUsdAmount ?? '') ?? Decimal.zero;
    final baseAmt           = (usdAmt * rateUsdToBase).round(scale: 2);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: SwipeActionCard(
        actionsPanelWidth: 140,
        actions: [
          SwipeAction(icon: Icons.edit_outlined,  label: 'Edit',   color: _teal,            onTap: () { if (groupId != null) context.push('/group/$groupId/expense/${expense.id}', extra: {'groupName': ''}); }),
          SwipeAction(icon: Icons.delete_outline, label: 'Delete', color: Colors.redAccent, onTap: () => _delete(context, ref)),
        ],
        child: GestureDetector(
          onLongPress: () => _showLongPressMenu(context, ref),
          onSecondaryTapUp: defaultTargetPlatform == TargetPlatform.macOS
              ? (d) => _showRightClickMenu(context, ref, d.globalPosition)
              : null,
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: groupId != null
                  ? () => context.push(
                      AppRouter.groupExpenseDetail,
                      extra: {'expense': expense, 'groupId': groupId, 'groupName': groupName},
                    )
                  : null,
              child: Row(
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 4, height: 44,
                        decoration: BoxDecoration(
                          color: groupAccent ?? _teal,
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
                        child: Icon(
                          expense.iconCodepoint != null
                              ? IconData(expense.iconCodepoint!, fontFamily: 'MaterialIcons')
                              : groupIcon,
                          size: 16,
                          color: theme.colorScheme.onSurface.withAlpha(180),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          expense.description.isEmpty ? expense.category : expense.description,
                          style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (groupName.isNotEmpty) ...[const SizedBox(height: 2),
                          Text(groupName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: groupAccent ?? theme.colorScheme.onSurfaceVariant,
                              fontSize: 10,
                              fontWeight: groupAccent != null ? FontWeight.w600 : FontWeight.normal,
                            ),
                            overflow: TextOverflow.ellipsis)],
                      ],
                    ),
                  ),
                  IntrinsicWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('$displayCurrency $displayAmount',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: groupAccent ?? _teal)),
                        if (showConversion && usdAmt > Decimal.zero)
                          Text('≈ $baseCcy ${baseAmt.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            )),
                        if (expense.createdAt != null)
                          Text(_shortDate(expense.createdAt!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                      ],
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

  String _shortDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}';
    } catch (_) {
      return '';
    }
  }
}

// ---------------------------------------------------------------------------
// Filter chip
// ---------------------------------------------------------------------------
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
    this.trailing,
  });

  final String        label;
  final bool          selected;
  final VoidCallback  onTap;
  final Color?        color;
  final Widget?       trailing;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? _teal;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? accent : accent.withAlpha(22),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent : accent.withAlpha(60),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : accent,
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 4), trailing!],
          ],
        ),
      ),
    );
  }
}

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
import '../../../../data/models/expense_model.dart';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const _purple    = Color(0xFF8B5CF6);
const _purpleDim = Color(0x268B5CF6);
const _teal      = Color(0xFF00D9B0);
const _tealDim   = Color(0x2600D9B0);
const _orange    = Color(0xFFFF8C42);
const _orangeDim = Color(0x26FF8C42);
const _brandOrange = Color(0xFFF97316);

enum _WalletFilter { all, income, expense }
enum _WalletSort   { newest, oldest, largest, smallest }

/// Standalone Wallet screen — personal cash balance, true net worth,
/// spending breakdown, and a selectable recent entries list.
class WalletScreen extends ConsumerStatefulWidget {
  const WalletScreen({super.key});

  @override
  ConsumerState<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends ConsumerState<WalletScreen> {
  bool _editMode = false;
  final Set<String> _selected = {};
  _WalletFilter _filter      = _WalletFilter.all;
  _WalletSort   _sort        = _WalletSort.newest;
  String?       _catFilter;   // non-null → show only this category
  Color?        _colorFilter; // non-null → show only entries with this accent color

  void _toggleEditMode() {
    HapticUtils.selection();
    setState(() { _editMode = !_editMode; _selected.clear(); });
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

  Future<void> _deleteBatch() async {
    if (_selected.isEmpty) return;
    final count = _selected.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entries?'),
        content: Text(
          'Delete $count wallet entr${count == 1 ? 'y' : 'ies'}? This cannot be undone.',
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
    final repo = ref.read(setAllRepositoryProvider);
    for (final id in _selected.toList()) {
      await repo.deleteExpense(id);
    }
    if (!mounted) return;
    HapticUtils.success();
    ref.invalidate(personalExpensesProvider);
    ref.invalidate(walletBalanceProvider);
    ref.invalidate(walletTotalsProvider);
    ref.invalidate(balanceSummaryProvider);
    ref.invalidate(omniActivityProvider);
    setState(() { _editMode = false; _selected.clear(); });
  }

  Future<void> _deleteOne(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('This wallet entry will be permanently removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _brandOrange, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(setAllRepositoryProvider).deleteExpense(id);
    if (!mounted) return;
    HapticUtils.success();
    ref.invalidate(personalExpensesProvider);
    ref.invalidate(walletBalanceProvider);
    ref.invalidate(walletTotalsProvider);
    ref.invalidate(balanceSummaryProvider);
    ref.invalidate(omniActivityProvider);
  }

  void _viewExpense(ExpenseModel expense) {
    context.push(AppRouter.walletEntryDetail, extra: expense);
  }

  void _editExpense(ExpenseModel expense) {
    context.push(
      '/group/${expense.groupId?.isNotEmpty == true ? expense.groupId : 'wallet'}/expense/${expense.id}',
      extra: expense,
    );
  }

  List<ExpenseModel> _applyFilterSort(List<ExpenseModel> all) {
    var list = all.where((e) {
      if (_colorFilter != null) {
        final c = e.iconColor != null ? Color(e.iconColor!) : null;
        if (c?.toARGB32() != _colorFilter!.toARGB32()) return false;
      }
      if (_catFilter != null) {
        final cat = e.category.isEmpty ? 'General' : e.category;
        return cat == _catFilter;
      }
      switch (_filter) {
        case _WalletFilter.all:     return true;
        case _WalletFilter.income:  return e.isIncome;
        case _WalletFilter.expense: return !e.isIncome;
      }
    }).toList();

    switch (_sort) {
      case _WalletSort.newest:
        list.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
      case _WalletSort.oldest:
        list.sort((a, b) => (a.createdAt ?? '').compareTo(b.createdAt ?? ''));
      case _WalletSort.largest:
        list.sort((a, b) {
          final av = Decimal.tryParse(a.universalUsdAmount ?? a.amount) ?? Decimal.zero;
          final bv = Decimal.tryParse(b.universalUsdAmount ?? b.amount) ?? Decimal.zero;
          return bv.compareTo(av);
        });
      case _WalletSort.smallest:
        list.sort((a, b) {
          final av = Decimal.tryParse(a.universalUsdAmount ?? a.amount) ?? Decimal.zero;
          final bv = Decimal.tryParse(b.universalUsdAmount ?? b.amount) ?? Decimal.zero;
          return av.compareTo(bv);
        });
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final theme         = Theme.of(context);
    final walletAsync   = ref.watch(walletBalanceProvider);
    final totalsAsync   = ref.watch(walletTotalsProvider);
    final personalAsync = ref.watch(personalExpensesProvider);
    final baseCcyAsync  = ref.watch(baseCurrencyProvider);
    final baseCurrency  = baseCcyAsync.valueOrNull ?? 'USD';

    final allExpenses  = personalAsync.valueOrNull ?? [];
    final expenses     = _applyFilterSort(allExpenses);
    final allIds       = expenses.map((e) => e.id).toList();
    final allSelected  = allIds.isNotEmpty && allIds.every(_selected.contains);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Wallet',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.3),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        automaticallyImplyLeading: false,
        actions: _editMode
            ? [
                TextButton(
                  onPressed: allSelected ? _deselectAll : () => _selectAll(allIds),
                  child: Text(allSelected ? 'Deselect All' : 'Select All'),
                ),
                if (_selected.isNotEmpty)
                  TextButton.icon(
                    onPressed: _deleteBatch,
                    icon: const Icon(Icons.delete_outline, size: 16, color: _brandOrange),
                    label: Text(
                      'Delete (${_selected.length})',
                      style: const TextStyle(color: _brandOrange),
                    ),
                  ),
                TextButton(onPressed: _toggleEditMode, child: const Text('Cancel')),
              ]
            : [
                AppTopPopupButton<_WalletSort>(
                  icon: Icons.sort_rounded,
                  tooltip: 'Sort',
                  initialValue: _sort,
                  onSelected: (s) { HapticUtils.selection(); setState(() => _sort = s); },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: _WalletSort.newest,   child: Text('Newest first')),
                    PopupMenuItem(value: _WalletSort.oldest,   child: Text('Oldest first')),
                    PopupMenuItem(value: _WalletSort.largest,  child: Text('Largest first')),
                    PopupMenuItem(value: _WalletSort.smallest, child: Text('Smallest first')),
                  ],
                ),
                const SizedBox(width: 4),
                AppTopButton(
                  icon: Icons.refresh_rounded,
                  tooltip: 'Refresh',
                  onPressed: () async {
                    HapticUtils.lightTap();
                    await ref.read(syncServiceProvider).performFullSync();
                    if (!mounted) return;
                    ref.invalidate(personalExpensesProvider);
                    ref.invalidate(walletBalanceProvider);
                    ref.invalidate(walletTotalsProvider);
                    ref.invalidate(balanceSummaryProvider);
                  },
                ),
                const SizedBox(width: 4),
                TextButton(onPressed: _toggleEditMode, child: const Text('Edit')),
              ],
      ),
      floatingActionButton: _editMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                HapticUtils.primaryTap();
                context.push(AppRouter.walletEntryType);
              },
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Add wallet entry',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            ),
      body: RefreshIndicator(
        color: _purple,
        onRefresh: () async {
          HapticUtils.lightTap();
          ref.invalidate(walletBalanceProvider);
          ref.invalidate(personalExpensesProvider);
          ref.invalidate(balanceSummaryProvider);
          ref.invalidate(baseCurrencyProvider);
        },
        child: CustomScrollView(
          slivers: [
            // ── Wallet Hero ──────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: walletAsync.when(
                  skipLoadingOnReload: true,
                  data: (walletStr) {
                    final walletDec = Decimal.tryParse(walletStr) ?? Decimal.zero;
                    final totals = totalsAsync.valueOrNull;
                    return WalletHero(
                      walletBalance: walletDec,
                      income: totals?.income,
                      spend: totals?.spend,
                      currency: baseCurrency,
                    );
                  },
                  loading: () => WalletHero.loading(),
                  error: (_, _) => WalletHero.error(),
                ),
              ),
            ),

            // ── Filter chips ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      _FilterChip(
                        label: 'All',
                        selected: _catFilter == null && _colorFilter == null && _filter == _WalletFilter.all,
                        onTap: () => setState(() { _filter = _WalletFilter.all; _catFilter = null; _colorFilter = null; }),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Income',
                        selected: _catFilter == null && _colorFilter == null && _filter == _WalletFilter.income,
                        color: _teal,
                        onTap: () => setState(() { _filter = _WalletFilter.income; _catFilter = null; _colorFilter = null; }),
                      ),
                      const SizedBox(width: 8),
                      _FilterChip(
                        label: 'Expense',
                        selected: _catFilter == null && _colorFilter == null && _filter == _WalletFilter.expense,
                        color: _purple,
                        onTap: () => setState(() { _filter = _WalletFilter.expense; _catFilter = null; _colorFilter = null; }),
                      ),
                      // Color filter dots — one per unique accent color used in entries
                      ...() {
                        final entries = personalAsync.valueOrNull ?? [];
                        final seen = <int>{};
                        final colors = <Color>[];
                        for (final e in entries) {
                          if (e.iconColor != null && seen.add(e.iconColor!)) {
                            colors.add(Color(e.iconColor!));
                          }
                        }
                        if (colors.isEmpty) return <Widget>[];
                        return [
                          const SizedBox(width: 4),
                          Container(width: 1, height: 20,
                            color: Theme.of(context).colorScheme.outlineVariant),
                          const SizedBox(width: 4),
                          ...colors.map((c) {
                            final isSelected = _colorFilter?.toARGB32() == c.toARGB32();
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: GestureDetector(
                                onTap: () => setState(() {
                                  _colorFilter = isSelected ? null : c;
                                  if (!isSelected) { _catFilter = null; }
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
                                        ? [BoxShadow(color: c.withAlpha(160), blurRadius: 6, spreadRadius: 1)]
                                        : null,
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check, size: 12, color: Colors.white)
                                      : null,
                                ),
                              ),
                            );
                          }),
                        ];
                      }(),
                      if (_catFilter != null) ...[
                        const SizedBox(width: 8),
                        _FilterChip(
                          label: _catFilter!,
                          selected: true,
                          color: _orange,
                          onTap: () => setState(() => _catFilter = null),
                          trailing: const Icon(Icons.close, size: 12, color: Colors.white),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),

            // ── Spending Breakdown ───────────────────────────────────────
            if (_catFilter == null && _filter != _WalletFilter.income) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Text('Spending breakdown',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700, fontSize: 13,
                        letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant,
                      )),
                ),
              ),
              personalAsync.when(
                data: (exp) {
                  final spend = <String, Decimal>{};
                  for (final e in exp) {
                    if (e.isIncome) continue;
                    final cat    = e.category.isEmpty ? 'General' : e.category;
                    final rawUsd = Decimal.tryParse(e.universalUsdAmount ?? e.amount) ?? Decimal.zero;
                    final entryBaseCcy = e.originalCurrency ?? e.currency;
                    final amt = (entryBaseCcy == baseCurrency && e.originalAmount != null)
                        ? (Decimal.tryParse(e.originalAmount!) ?? rawUsd)
                        : rawUsd;
                    spend[cat] = (spend[cat] ?? Decimal.zero) + amt;
                  }
                  if (spend.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
                  final sorted = spend.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
                  final total  = sorted.fold(Decimal.zero, (s, e) => s + e.value);
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _CategoryRow(
                        category: sorted[i].key,
                        amount: sorted[i].value,
                        total: total,
                        accentColor: _purple,
                        onTap: () {
                          HapticUtils.selection();
                          setState(() => _catFilter = sorted[i].key);
                        },
                      ),
                      childCount: sorted.length,
                    ),
                  );
                },
                loading: () => const SliverToBoxAdapter(
                  child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
                ),
                error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              ),
            ],

            // ── Income Breakdown ─────────────────────────────────────────
            if (_catFilter == null && _filter != _WalletFilter.expense) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                  child: Text('Income breakdown',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700, fontSize: 13,
                        letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant,
                      )),
                ),
              ),
              personalAsync.when(
                data: (exp) {
                  final income = <String, Decimal>{};
                  for (final e in exp) {
                    if (!e.isIncome) continue;
                    final cat    = e.category.isEmpty ? 'General' : e.category;
                    final rawUsd = Decimal.tryParse(e.universalUsdAmount ?? e.amount) ?? Decimal.zero;
                    final entryBaseCcy = e.originalCurrency ?? e.currency;
                    final amt = (entryBaseCcy == baseCurrency && e.originalAmount != null)
                        ? (Decimal.tryParse(e.originalAmount!) ?? rawUsd)
                        : rawUsd;
                    income[cat] = (income[cat] ?? Decimal.zero) + amt;
                  }
                  if (income.isEmpty) return const SliverToBoxAdapter(child: SizedBox.shrink());
                  final sorted = income.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
                  final total  = sorted.fold(Decimal.zero, (s, e) => s + e.value);
                  return SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (ctx, i) => _CategoryRow(
                        category: sorted[i].key,
                        amount: sorted[i].value,
                        total: total,
                        accentColor: _teal,
                        onTap: () {
                          HapticUtils.selection();
                          setState(() { _catFilter = sorted[i].key; _filter = _WalletFilter.income; });
                        },
                      ),
                      childCount: sorted.length,
                    ),
                  );
                },
                loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
                error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              ),
            ],

            // ── Entries list ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                child: Row(
                  children: [
                    Text(
                      _catFilter != null
                          ? _catFilter!
                          : (_filter == _WalletFilter.income ? 'Income entries'
                              : _filter == _WalletFilter.expense ? 'Expense entries'
                              : 'All entries'),
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700, fontSize: 13,
                        letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${expenses.length} entr${expenses.length == 1 ? 'y' : 'ies'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant, fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            if (expenses.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
                  child: Center(
                    child: Column(children: [
                      Icon(Icons.account_balance_wallet_outlined,
                          size: 48, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(height: 16),
                      Text('No entries found',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface)),
                      const SizedBox(height: 8),
                      Text('Try a different filter or add a new entry.',
                          style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                          textAlign: TextAlign.center),
                    ]),
                  ),
                ),
              )
            else
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _WalletEntryRow(
                    expense: expenses[i],
                    editMode: _editMode,
                    selected: _selected.contains(expenses[i].id),
                    onToggle: () => _toggleItem(expenses[i].id),
                    onView: () => _viewExpense(expenses[i]),
                    onEdit: () => _editExpense(expenses[i]),
                    onDelete: () => _deleteOne(expenses[i].id),
                  ),
                  childCount: expenses.length,
                ),
              ),

            const SliverToBoxAdapter(child: SizedBox(height: 112)),
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
    this.income,
    this.spend,
    this.currency = 'USD',
  }) : _loading = false, _error = false;

  static final _zero = Decimal.zero;

  WalletHero.loading({super.key})
      : walletBalance = _zero, income = null, spend = null, currency = 'USD', _loading = true, _error = false;

  WalletHero.error({super.key})
      : walletBalance = _zero, income = null, spend = null, currency = 'USD', _loading = false, _error = true;

  final Decimal  walletBalance;
  final Decimal? income;
  final Decimal? spend;
  final String   currency;
  final bool     _loading;
  final bool     _error;

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final walletIsPos = walletBalance >= Decimal.zero;

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
              '$currency ${walletBalance.abs().toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.w800, fontSize: 26, letterSpacing: -0.5,
                color: _error
                    ? theme.colorScheme.onSurfaceVariant
                    : (walletIsPos ? _purple : _orange),
              ).withAccentShadow(context, opacity: 0.28),
              maxLines: 1, overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _BalancePill(
              label: 'Income',
              amount: (income ?? Decimal.zero).toStringAsFixed(2),
              color: _teal,
              bgColor: _tealDim,
            )),
            const SizedBox(width: 8),
            Expanded(child: _BalancePill(
              label: 'Expenses',
              amount: (spend ?? Decimal.zero).toStringAsFixed(2),
              color: walletIsPos ? _purple : _orange,
              bgColor: walletIsPos ? _purpleDim : _orangeDim,
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
    required this.color,
    required this.bgColor,
  });

  final String label;
  final String amount;
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
                shadows: accentShadows(context),
              ),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(amount,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13)
                  .withAccentShadow(context),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wallet entry row — tap to edit, right-click context menu, checkbox in edit mode
// ---------------------------------------------------------------------------
/// Smart amount formatter: 4 decimal places for values < 0.01, else 2.
String _fmtAmt(Decimal d) {
  if (d == Decimal.zero) return '0.00';
  final abs = d.abs();
  if (abs < Decimal.parse('0.01')) return d.toStringAsFixed(4);
  return d.toStringAsFixed(2);
}

class _WalletEntryRow extends ConsumerWidget {
  const _WalletEntryRow({
    required this.expense,
    required this.editMode,
    required this.selected,
    required this.onToggle,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final ExpenseModel expense;
  final bool         editMode;
  final bool         selected;
  final VoidCallback onToggle;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme      = Theme.of(context);
    final isIncome   = expense.isIncome;
    final amt        = Decimal.tryParse(expense.amount) ?? Decimal.zero;
    final ccy        = expense.currency.isEmpty ? 'USD' : expense.currency;
    final desc       = expense.description.isEmpty ? 'Wallet entry' : expense.description;
    final baseCcy    = ref.watch(baseCurrencyProvider).valueOrNull ?? 'USD';
    final usdAmt     = Decimal.tryParse(expense.universalUsdAmount ?? '') ?? Decimal.zero;

    // Prefer original currency/amount for the main display (e.g. "100 VND").
    // Fall back to the stored base-currency amount when no conversion occurred.
    final hasOrig   = expense.originalCurrency != null &&
        expense.originalAmount != null &&
        expense.originalCurrency != ccy;
    final dispAmt   = hasOrig
        ? (Decimal.tryParse(expense.originalAmount!) ?? amt)
        : amt;
    final dispCcy   = hasOrig ? expense.originalCurrency! : ccy;
    final showEquiv = dispCcy != baseCcy && usdAmt > Decimal.zero;

    final tile = GestureDetector(
      onTap: editMode ? onToggle : onView,
      onSecondaryTapUp: (details) async {
        final pos = details.globalPosition;
        final result = await showMenu<_EntryAction>(
          context: context,
          position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 1, pos.dy + 1),
          items: [
            const PopupMenuItem(value: _EntryAction.edit,   child: _MenuRow(icon: Icons.edit_outlined,   label: 'Edit')),
            const PopupMenuItem(value: _EntryAction.delete, child: _MenuRow(icon: Icons.delete_outlined, label: 'Delete')),
          ],
        );
        if (result == _EntryAction.edit)   onEdit();
        if (result == _EntryAction.delete) onDelete();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              if (editMode)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: Checkbox(
                    value: selected,
                    onChanged: (_) => onToggle(),
                    activeColor: _brandOrange,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                ),
              Builder(builder: (ctx) {
                final entryColor = expense.iconColor != null
                    ? Color(expense.iconColor!)
                    : (isIncome ? _teal : _purple);
                final entryIcon = expense.iconCodepoint != null
                    ? IconData(expense.iconCodepoint!, fontFamily: 'MaterialIcons')
                    : (isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded);
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Accent stripe
                    Container(
                      width: 4, height: 44,
                      decoration: BoxDecoration(
                        color: entryColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Icon on neutral bg
                    Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(
                        color: Theme.of(ctx).colorScheme.surfaceContainerHighest.withAlpha(80),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(entryIcon, size: 16,
                          color: Theme.of(ctx).colorScheme.onSurface.withAlpha(180)),
                    ),
                  ],
                );
              }),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(desc,
                        style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600, fontSize: 13),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(expense.category.isEmpty ? 'General' : expense.category,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${isIncome ? '+' : '-'}$dispCcy ${_fmtAmt(dispAmt)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: isIncome ? _teal : _purple,
                    ),
                  ),
                  if (showEquiv)
                    Text(
                      '≈ $baseCcy ${_fmtAmt(usdAmt)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
              if (!editMode)
                const Padding(
                  padding: EdgeInsets.only(left: 6),
                  child: Icon(Icons.chevron_right, size: 16, color: Color(0xFF94A3B8)),
                ),
            ],
          ),
        ),
      ),
    );

    return tile;
  }
}

enum _EntryAction { edit, delete }

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});
  final IconData icon;
  final String   label;

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 16),
      const SizedBox(width: 10),
      Text(label),
    ]);
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
    this.onTap,
    this.accentColor = _purple,
  });

  final String       category;
  final Decimal      amount;
  final Decimal      total;
  final VoidCallback? onTap;
  final Color        accentColor;

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

    return GestureDetector(
      onTap: onTap,
      child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: accentColor.withAlpha(28),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 16, color: accentColor),
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
                      backgroundColor: accentColor.withAlpha(22),
                      color: accentColor,
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
                    style: TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13, color: accentColor)),
                Text('${pct.toStringAsFixed(1)}%',
                    style: const TextStyle(fontSize: 10, color: Color(0xFF94A3B8))),
              ],
            ),
          ],
        ),
      ),
    ));
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
    final accent = color ?? _purple;
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

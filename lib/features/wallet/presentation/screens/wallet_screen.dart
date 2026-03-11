import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/haptic_utils.dart';
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

  void _editExpense(ExpenseModel expense) {
    context.push(
      '/group/${expense.groupId ?? 'wallet'}/expense/${expense.id}',
      extra: expense,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme         = Theme.of(context);
    final walletAsync   = ref.watch(walletBalanceProvider);
    final totalsAsync   = ref.watch(walletTotalsProvider);
    final personalAsync = ref.watch(personalExpensesProvider);
    final baseCcyAsync  = ref.watch(baseCurrencyProvider);
    final baseCurrency  = baseCcyAsync.valueOrNull ?? 'USD';

    final expenses = personalAsync.valueOrNull ?? [];
    final allIds   = expenses.map((e) => e.id).toList();
    final allSelected = allIds.isNotEmpty && allIds.every(_selected.contains);

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
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
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
                TextButton(onPressed: _toggleEditMode, child: const Text('Edit')),
              ],
      ),
      floatingActionButton: _editMode
          ? null
          : FloatingActionButton.extended(
              onPressed: () {
                HapticUtils.primaryTap();
                context.push(AppRouter.addExpense, extra: {'groupId': '', 'groupName': ''});
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

            // ── Spending Breakdown ───────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
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
                  // Use originalAmount in originalCurrency when available and
                  // the entry currency matches baseCurrency — avoids double-converting.
                  // Otherwise fall back to universalUsdAmount (stored in USD)
                  // which walletBalanceProvider already converted for the hero total.
                  // For the breakdown we mirror the same logic: use the USD amount
                  // as a proxy (exact per-entry conversion would require async).
                  // The breakdown proportions are correct; only the absolute numbers
                  // vary by currency and are consistent with the hero total above.
                  final rawUsd = Decimal.tryParse(e.universalUsdAmount ?? e.amount) ?? Decimal.zero;
                  final entryBaseCcy = e.originalCurrency ?? e.currency;
                  // If the entry was recorded in the current base currency, use
                  // the original amount directly (no conversion needed).
                  final amt = (entryBaseCcy == baseCurrency && e.originalAmount != null)
                      ? (Decimal.tryParse(e.originalAmount!) ?? rawUsd)
                      : rawUsd;
                  spend[cat] = (spend[cat] ?? Decimal.zero) + amt;
                }
                if (spend.isEmpty) {
                  return SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                      child: Center(
                        child: Column(children: [
                          Icon(Icons.account_balance_wallet_outlined,
                              size: 48, color: theme.colorScheme.onSurfaceVariant),
                          const SizedBox(height: 16),
                          Text('No personal expenses yet',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.onSurface)),
                          const SizedBox(height: 8),
                          Text('Tap + to add your first wallet entry.',
                              style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                              textAlign: TextAlign.center),
                        ]),
                      ),
                    ),
                  );
                }
                final sorted = spend.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
                final total  = sorted.fold(Decimal.zero, (s, e) => s + e.value);
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (ctx, i) => _CategoryRow(category: sorted[i].key, amount: sorted[i].value, total: total),
                    childCount: sorted.length,
                  ),
                );
              },
              loading: () => const SliverToBoxAdapter(
                child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator())),
              ),
              error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),

            // ── Recent Entries ───────────────────────────────────────────
            if (expenses.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
                  child: Text('Recent entries',
                      style: theme.textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w700, fontSize: 13,
                        letterSpacing: 0.5, color: theme.colorScheme.onSurfaceVariant,
                      )),
                ),
              ),
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (ctx, i) => _WalletEntryRow(
                    expense: expenses[i],
                    editMode: _editMode,
                    selected: _selected.contains(expenses[i].id),
                    onToggle: () => _toggleItem(expenses[i].id),
                    onEdit: () => _editExpense(expenses[i]),
                    onDelete: () => _deleteOne(expenses[i].id),
                  ),
                  childCount: expenses.length,
                ),
              ),
            ],

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
              ),
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
              ),
              overflow: TextOverflow.ellipsis),
          const SizedBox(height: 2),
          Text(amount,
              style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wallet entry row — tap to edit, right-click context menu, checkbox in edit mode
// ---------------------------------------------------------------------------
class _WalletEntryRow extends StatelessWidget {
  const _WalletEntryRow({
    required this.expense,
    required this.editMode,
    required this.selected,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
  });

  final ExpenseModel expense;
  final bool         editMode;
  final bool         selected;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final isIncome = expense.isIncome;
    final amt      = Decimal.tryParse(expense.amount) ?? Decimal.zero;
    final ccy      = expense.currency.isEmpty ? 'USD' : expense.currency;
    final desc     = expense.description.isEmpty ? 'Wallet entry' : expense.description;

    final tile = GestureDetector(
      onTap: editMode ? onToggle : onEdit,
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
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: isIncome ? _teal.withAlpha(28) : _purple.withAlpha(28),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                  size: 16,
                  color: isIncome ? _teal : _purple,
                ),
              ),
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
              Text(
                '${isIncome ? '+' : '-'}$ccy ${amt.toStringAsFixed(2)}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: isIncome ? _teal : _purple,
                ),
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

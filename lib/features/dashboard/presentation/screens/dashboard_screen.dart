import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/amount_formatter.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/utils/navigation_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../core/widgets/swipe_action_card.dart';
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
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // StreamProviders (myGroupsProvider, groupExpensesProvider) update
      // automatically via notifySyncComplete(). Only non-stream providers need
      // explicit invalidation after sync.
      ref.read(syncServiceProvider).performFullSync().then((_) {
        if (mounted) {
          ref.invalidate(balanceSummaryProvider);
          ref.invalidate(recentExpensesProvider);
        }
      });
    });
  }

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
        await ref.read(syncServiceProvider).performFullSync();
        ref.invalidate(balanceSummaryProvider);
        ref.invalidate(myGroupsProvider);
        ref.invalidate(recentExpensesProvider);
      },
      child: CustomScrollView(
        slivers: [
          // ── Net Liquidity Hero ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: summaryAsync.when(
                skipLoadingOnReload: true,
                data: (summary) {
                  final owed = Decimal.tryParse(summary.youAreOwed) ?? Decimal.zero;
                  final owe  = Decimal.tryParse(summary.youOwe)     ?? Decimal.zero;
                  final net  = owed - owe;
                  final isPositive = net >= Decimal.zero;
                  final display = isPositive ? net : -net;
                  return _BalanceHero(
                    netDisplay: display.toStringAsFixed(2),
                    currency: summary.currency,
                    isPositive: isPositive,
                    youAreOwed: summary.youAreOwed,
                    youOwe: summary.youOwe,
                    walletBalanceAsync: ref.watch(walletBalanceProvider),
                  );
                },
                loading: () => _BalanceHero.loading(),
                error: (_, _) => _BalanceHero.error(),
              ),
            ),
          ),

          // ── Groups ───────────────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
              child: Text(
                'Your groups',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          groupsAsync.when(
            data: (groups) => groups.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                padding: const EdgeInsets.all(24),
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
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
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
              child: Text(
                'Recent activity',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.5,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          groupsAsync.when(
            data: (groups) {
              final groupNameMap = {for (final g in groups) g.id: g.name};
              return expensesAsync.when(
                data: (expenses) => expenses.isEmpty
                    ? SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                          (context, index) => _ActivityTile(
                            expense: expenses[index],
                            groupId: expenses[index].groupId,
                            groupName: groupNameMap[expenses[index].groupId] ?? '',
                          ),
                          childCount: expenses.length,
                        ),
                      ),
                loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
                error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
              );
            },
            loading: () => expensesAsync.when(
              data: (expenses) => SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _ActivityTile(
                    expense: expenses[index],
                    groupId: expenses[index].groupId,
                    groupName: '',
                  ),
                  childCount: expenses.length,
                ),
              ),
              loading: () => SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: const Center(child: CircularProgressIndicator()),
                ),
              ),
              error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
            error: (_, _) => expensesAsync.when(
              data: (expenses) => SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => _ActivityTile(
                    expense: expenses[index],
                    groupId: expenses[index].groupId,
                    groupName: '',
                  ),
                  childCount: expenses.length,
                ),
              ),
              loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
              error: (_, _) => const SliverToBoxAdapter(child: SizedBox.shrink()),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 96)),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'SetAll',
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
      body: body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticUtils.primaryTap();
          context.push(AppRouter.groupPicker);
        },
        backgroundColor: _teal,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text(
          'Add expense',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Balance Hero — toggles between Net Debt (group) and Wallet Balance views
// ---------------------------------------------------------------------------
const _purple = Color(0xFF8B5CF6);
const _purpleDim = Color(0x268B5CF6);

class _BalanceHero extends StatefulWidget {
  const _BalanceHero({
    required this.netDisplay,
    required this.currency,
    required this.isPositive,
    required this.youAreOwed,
    required this.youOwe,
    required this.walletBalanceAsync,
  }) : _loading = false, _error = false;

  const _BalanceHero.loading()
      : netDisplay = '—',
        currency = '',
        isPositive = true,
        youAreOwed = '0',
        youOwe = '0',
        walletBalanceAsync = const AsyncValue.loading(),
        _loading = true,
        _error = false;

  const _BalanceHero.error()
      : netDisplay = '—',
        currency = '',
        isPositive = true,
        youAreOwed = '0',
        youOwe = '0',
        walletBalanceAsync = const AsyncValue.data('0'),
        _loading = false,
        _error = true;

  final String netDisplay;
  final String currency;
  final bool isPositive;
  final String youAreOwed;
  final String youOwe;
  final AsyncValue<String> walletBalanceAsync;
  final bool _loading;
  final bool _error;

  @override
  State<_BalanceHero> createState() => _BalanceHeroState();
}

class _BalanceHeroState extends State<_BalanceHero> {
  // false = Net Debt (group view), true = Wallet Balance (personal view)
  bool _showWallet = false;

  void _toggle() {
    HapticUtils.selection();
    setState(() => _showWallet = !_showWallet);
  }

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final walletValue = widget.walletBalanceAsync.valueOrNull ?? '0';
    final walletDec   = Decimal.tryParse(walletValue) ?? Decimal.zero;
    final walletPos   = walletDec >= Decimal.zero;

    final accent        = _showWallet ? _purple    : (widget.isPositive ? _teal : _orange);
    final accentDim     = _showWallet ? _purpleDim : (widget.isPositive ? _tealDim : _orangeDim);
    final heroLabel     = _showWallet
        ? (walletPos ? 'Net liquidity' : 'Net liquidity deficit')
        : (widget.isPositive ? 'Overall you are owed' : 'Overall you owe');
    final heroAmount    = _showWallet
        ? '${widget.currency.isEmpty ? 'USD' : widget.currency} ${walletDec.abs().toStringAsFixed(2)}'
        : '${widget.currency} ${widget.netDisplay}';

    return GlassCard(
      padding: EdgeInsets.zero,
      child: InkWell(
        onTap: _toggle,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Header row ──────────────────────────────────────────────
              Row(
                children: [
                  Container(
                    width: 7, height: 7,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    heroLabel,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  // Mode toggle chip
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: accentDim,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _showWallet ? Icons.account_balance_wallet_outlined : Icons.group_outlined,
                          size: 11,
                          color: accent,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _showWallet ? 'Wallet' : 'Group',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: accent,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // ── Main amount ─────────────────────────────────────────────
              if (widget._loading)
                const SizedBox(height: 28, child: LinearProgressIndicator())
              else
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    heroAmount,
                    key: ValueKey(_showWallet),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 26,
                      letterSpacing: -0.5,
                      color: widget._error
                          ? theme.colorScheme.onSurfaceVariant
                          : accent,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 12),
              // ── Pills ───────────────────────────────────────────────────
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _showWallet
                    ? Row(
                        key: const ValueKey('wallet-pills'),
                        children: [
                          Expanded(
                            child: _BalancePill(
                              label: 'Income',
                              amount: walletPos ? walletValue : '0',
                              currency: widget.currency.isEmpty ? 'USD' : widget.currency,
                              color: _teal,
                              bgColor: _tealDim,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _BalancePill(
                              label: 'Net deficit',
                              amount: walletPos ? '0' : walletDec.abs().toStringAsFixed(2),
                              currency: widget.currency.isEmpty ? 'USD' : widget.currency,
                              color: _orange,
                              bgColor: _orangeDim,
                            ),
                          ),
                        ],
                      )
                    : Row(
                        key: const ValueKey('group-pills'),
                        children: [
                          Expanded(
                            child: _BalancePill(
                              label: 'Owed to you',
                              amount: widget.youAreOwed,
                              currency: widget.currency,
                              color: _teal,
                              bgColor: _tealDim,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _BalancePill(
                              label: 'You owe',
                              amount: widget.youOwe,
                              currency: widget.currency,
                              color: _orange,
                              bgColor: _orangeDim,
                            ),
                          ),
                        ],
                      ),
              ),
              // ── Tap hint ────────────────────────────────────────────────
              const SizedBox(height: 10),
              Center(
                child: Text(
                  'Tap to toggle ${_showWallet ? 'group' : 'wallet'} view',
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant.withAlpha(130),
                  ),
                ),
              ),
            ],
          ),
        ),
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
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '$currency $amount',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Group card  (swipe left → Edit | Delete)
// ---------------------------------------------------------------------------
class _GroupCard extends ConsumerStatefulWidget {
  const _GroupCard({required this.group});
  final GroupModel group;

  @override
  ConsumerState<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends ConsumerState<_GroupCard> {
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

  Future<void> _delete() async {
    HapticUtils.primaryTap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text('Delete "${widget.group.name}" and all its expenses?'),
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
    if (confirmed != true || !mounted) return;
    final doubleConfirmed = await showDialog<bool>(
      context: context,
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
    if (doubleConfirmed != true || !mounted) return;
    final ok = await ref.read(setAllRepositoryProvider).deleteGroup(widget.group.id);
    if (!mounted) return;
    if (ok) {
      ref.invalidate(myGroupsProvider);
      ref.invalidate(balanceSummaryProvider);
      ref.invalidate(recentExpensesProvider);
      HapticUtils.success();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete group.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balanceAsync = ref.watch(groupBalanceSummaryProvider(widget.group.id));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SwipeActionCard(
          actionsPanelWidth: 140,
          actions: [
            SwipeAction(icon: Icons.edit_outlined, label: 'Edit', color: _teal, onTap: _rename),
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
                  navigateToGroup(context: context, ref: ref, groupId: widget.group.id, groupName: widget.group.name);
                },
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: _tealDim,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Center(
                          child: Text(
                            widget.group.name.isNotEmpty ? widget.group.name[0].toUpperCase() : 'G',
                            style: const TextStyle(color: _teal, fontWeight: FontWeight.w800, fontSize: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
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
                            const SizedBox(height: 4),
                            balanceAsync.when(
                              skipLoadingOnReload: true,
                              data: (s) {
                                final owed = Decimal.tryParse(s.youAreOwed) ?? Decimal.zero;
                                final owe  = Decimal.tryParse(s.youOwe)     ?? Decimal.zero;
                                if (owed == Decimal.zero && owe == Decimal.zero) {
                                  return Text('Settled up',
                                      style: theme.textTheme.bodySmall?.copyWith(color: _teal, fontSize: 11));
                                }
                                return RichText(
                                  text: TextSpan(
                                    style: const TextStyle(fontSize: 11),
                                    children: [
                                      if (owed > Decimal.zero)
                                        TextSpan(
                                          text: '+${s.currency} ${formatAmount(s.youAreOwed)}',
                                          style: const TextStyle(color: _teal, fontWeight: FontWeight.w600),
                                        ),
                                      if (owed > Decimal.zero && owe > Decimal.zero)
                                        const TextSpan(text: '  '),
                                      if (owe > Decimal.zero)
                                        TextSpan(
                                          text: '-${s.currency} ${formatAmount(s.youOwe)}',
                                          style: const TextStyle(color: _orange, fontWeight: FontWeight.w600),
                                        ),
                                    ],
                                  ),
                                );
                              },
                              loading: () => const SizedBox(height: 12),
                              error: (_, _) => const SizedBox.shrink(),
                            ),
                          ],
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
    );
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
              leading: Icon(Icons.edit_outlined, color: _teal),
              title: const Text('Rename group'),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Delete group', style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (result == 'rename') _rename();
    if (result == 'delete') _delete();
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
            Icon(Icons.edit_outlined, size: 16, color: _teal),
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
      ],
    );
    if (result == 'rename') _rename();
    if (result == 'delete') _delete();
  }
}

// ---------------------------------------------------------------------------
// Activity tile  (tap → Edit, swipe left → Delete, right-click → menu)
// ---------------------------------------------------------------------------
class _ActivityTile extends ConsumerWidget {
  const _ActivityTile({required this.expense, required this.groupId, required this.groupName});
  final ExpenseModel expense;
  final String? groupId;
  final String groupName;

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
    final doubleConfirmed = await showDialog<bool>(
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
    if (doubleConfirmed != true || !context.mounted) return;
    await ref.read(setAllRepositoryProvider).deleteExpense(expense.id);
    ref.invalidate(recentExpensesProvider);
    ref.invalidate(balanceSummaryProvider);
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
      context.push('/group/$groupId/expense/${expense.id}',
          extra: {'groupName': ''});
    } else if (result == 'delete') {
      _delete(context, ref);
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
      context.push('/group/$groupId/expense/${expense.id}',
          extra: {'groupName': ''});
    } else if (result == 'delete') {
      _delete(context, ref);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final icon = _categoryIcons[expense.category] ?? Icons.attach_money_outlined;
    final displayAmount = formatAmount(expense.originalAmount ?? expense.amount);
    final displayCurrency = expense.originalCurrency ?? expense.currency;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
      child: SwipeActionCard(
        actionsPanelWidth: 140,
        actions: [
          SwipeAction(icon: Icons.edit_outlined, label: 'Edit', color: _teal, onTap: () { if (groupId != null) context.push('/group/$groupId/expense/${expense.id}', extra: {'groupName': ''}); }),
          SwipeAction(icon: Icons.delete_outline, label: 'Delete', color: Colors.redAccent, onTap: () => _delete(context, ref)),
        ],
        child: GestureDetector(
          onLongPress: () => _showLongPressMenu(context, ref),
          onSecondaryTapUp: defaultTargetPlatform == TargetPlatform.macOS
              ? (d) => _showRightClickMenu(context, ref, d.globalPosition)
              : null,
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: groupId != null ? () => context.push(
                '/group/$groupId/expense/${expense.id}',
                extra: {'groupName': ''},
              ) : null,
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                      Text(
                        expense.description.isEmpty ? expense.category : expense.description,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (groupName.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          groupName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (expense.originalCurrency != null &&
                          expense.originalCurrency != expense.currency) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${expense.currency} ${formatAmount(expense.amount)} base',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                IntrinsicWidth(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$displayCurrency $displayAmount',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _teal),
                      ),
                      if (expense.createdAt != null)
                        Text(
                          _shortDate(expense.createdAt!),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
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

  String _shortDate(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      return '${d.day}/${d.month}';
    } catch (_) {
      return '';
    }
  }
}



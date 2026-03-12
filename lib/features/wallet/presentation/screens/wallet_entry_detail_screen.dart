import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/expense_model.dart';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const _purple     = Color(0xFF8B5CF6);
const _purpleDim  = Color(0x268B5CF6);
const _teal       = Color(0xFF00D9B0);
const _green      = Color(0xFF22C55E);
const _greenDim   = Color(0x1A22C55E);
const _brandOrange = Color(0xFFF97316);

// Category icons
const Map<String, IconData> _kCategoryIcons = {
  'Food & drink':      Icons.restaurant_outlined,
  'Transport':         Icons.directions_car_outlined,
  'Entertainment':     Icons.movie_outlined,
  'Bills & utilities': Icons.receipt_long_outlined,
  'Shopping':          Icons.shopping_bag_outlined,
  'Travel':            Icons.flight_outlined,
  'General':           Icons.category_outlined,
  'Other':             Icons.category_outlined,
};

// Category colors
const Map<String, Color> _kCategoryColors = {
  'Food & drink':      Color(0xFFEF4444),
  'Transport':         Color(0xFF3B82F6),
  'Entertainment':     Color(0xFFA855F7),
  'Bills & utilities': Color(0xFFF59E0B),
  'Shopping':          Color(0xFFEC4899),
  'Travel':            Color(0xFF06B6D4),
  'General':           Color(0xFF8B5CF6),
  'Other':             Color(0xFF94A3B8),
};

/// Detail / information screen for a single wallet entry.
/// Shows the sum breakdown, mini analytics gauge, category badge,
/// and prominent [Edit] / [Delete] action buttons.
class WalletEntryDetailScreen extends ConsumerStatefulWidget {
  const WalletEntryDetailScreen({
    super.key,
    required this.expense,
  });

  final ExpenseModel expense;

  @override
  ConsumerState<WalletEntryDetailScreen> createState() =>
      _WalletEntryDetailScreenState();
}

class _WalletEntryDetailScreenState
    extends ConsumerState<WalletEntryDetailScreen> {

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('This wallet entry will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(setAllRepositoryProvider).deleteExpense(widget.expense.id);
    if (!mounted) return;
    HapticUtils.success();
    ref.invalidate(personalExpensesProvider);
    ref.invalidate(walletBalanceProvider);
    ref.invalidate(walletTotalsProvider);
    ref.invalidate(balanceSummaryProvider);
    ref.invalidate(omniActivityProvider);
    context.pop();
    context.pop(); // also pop the detail screen
  }

  void _edit() {
    HapticUtils.primaryTap();
    context.push(
      '/group/${widget.expense.groupId ?? 'wallet'}/expense/${widget.expense.id}',
      extra: widget.expense,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final expense     = widget.expense;
    final isIncome    = expense.isIncome;
    final accentColor = isIncome ? _green : _purple;
    final accentDim   = isIncome ? _greenDim : _purpleDim;

    final amt    = Decimal.tryParse(expense.amount) ?? Decimal.zero;
    final usdAmt = Decimal.tryParse(expense.universalUsdAmount ?? '') ??
        Decimal.tryParse(expense.amount) ?? Decimal.zero;
    final ccy    = expense.currency.isEmpty ? 'USD' : expense.currency;

    final baseCcyAsync = ref.watch(baseCurrencyProvider);
    final baseCcy      = baseCcyAsync.valueOrNull ?? 'USD';

    final categoryColor = _kCategoryColors[expense.category] ?? _purple;
    final categoryIcon  = _kCategoryIcons[expense.category] ?? Icons.category_outlined;

    // Mini analytics: personal expenses for category gauge
    final personalAsync = ref.watch(personalExpensesProvider);
    final expenses = personalAsync.valueOrNull ?? [];

    // Monthly spend for this category
    final now        = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    Decimal catMonthSpend  = Decimal.zero;
    Decimal totalMonthSpend = Decimal.zero;
    for (final e in expenses) {
      if (e.isIncome != isIncome) continue;  // match same type
      final createdAt = DateTime.tryParse(e.createdAt ?? '') ?? DateTime(2000);
      if (createdAt.isBefore(monthStart)) continue;
      final eAmt = Decimal.tryParse(e.universalUsdAmount ?? e.amount) ?? Decimal.zero;
      totalMonthSpend += eAmt;
      if (e.category == expense.category) catMonthSpend += eAmt;
    }

    final gaugeRatio = (totalMonthSpend > Decimal.zero)
        ? (catMonthSpend / totalMonthSpend)
            .toDecimal(scaleOnInfinitePrecision: 4)
            .toDouble()
            .clamp(0.0, 1.0)
        : 0.0;

    // Date formatting
    final dateStr = expense.createdAt != null
        ? () {
            try {
              final dt = DateTime.parse(expense.createdAt!).toLocal();
              return DateFormat('EEE, d MMM yyyy  HH:mm').format(dt);
            } catch (_) { return expense.createdAt!; }
          }()
        : '—';

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          isIncome ? 'Income Entry' : 'Expense Entry',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          // Edit button
          TextButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit'),
            style: TextButton.styleFrom(foregroundColor: _teal),
          ),
          // Delete button
          TextButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: _brandOrange),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [

          // ── Hero Amount Card ─────────────────────────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: accentDim,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                        color: accentColor, size: 22,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            expense.description.isEmpty ? 'Wallet entry' : expense.description,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700, fontSize: 15,
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // SUM BREAKDOWN
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      // Entry currency amount (large)
                      Text(
                        '${isIncome ? '+' : '-'}$ccy ${amt.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          color: accentColor,
                        ),
                      ),
                      // Default currency equivalent
                      if (ccy != baseCcy) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.swap_horiz, size: 14, color: Color(0xFF94A3B8)),
                            const SizedBox(width: 4),
                            Text(
                              '≈ $baseCcy ${usdAmt.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (expense.exchangeRateApplied != null && ccy != baseCcy) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Rate at entry: 1 $ccy = ${expense.exchangeRateApplied} $baseCcy',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Category Card ────────────────────────────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(categoryIcon, color: categoryColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Category',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        expense.category.isEmpty ? 'General' : expense.category,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: categoryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                // Type badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isIncome ? 'INCOME' : 'EXPENSE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Mini Analytics ───────────────────────────────────────────────
          if (true) ...[
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bar_chart_rounded, size: 16, color: accentColor),
                      const SizedBox(width: 6),
                      Text(
                        'Monthly ${isIncome ? 'Income' : 'Spending'} — ${expense.category.isEmpty ? 'General' : expense.category}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700, fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Gauge bar
                  Stack(
                    children: [
                      Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: gaugeRatio,
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: categoryColor,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _AnalyticPill(
                        label: expense.category.isEmpty ? 'General' : expense.category,
                        value: '≈ $baseCcy ${catMonthSpend.toStringAsFixed(0)}',
                        color: categoryColor,
                      ),
                      _AnalyticPill(
                        label: 'All categories',
                        value: '≈ $baseCcy ${totalMonthSpend.toStringAsFixed(0)}',
                        color: accentColor,
                      ),
                      _AnalyticPill(
                        label: 'Share',
                        value: '${(gaugeRatio * 100).toStringAsFixed(1)}%',
                        color: _teal,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Figures are approximated in $baseCcy using the USD anchor.',
                    style: TextStyle(
                      fontSize: 9,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Meta info ────────────────────────────────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _MetaRow(label: 'Entry ID',   value: widget.expense.id, mono: true),
                const Divider(height: 16),
                _MetaRow(label: 'Created',    value: dateStr),
                if (expense.originalCurrency != null && expense.originalCurrency != ccy) ...[
                  const Divider(height: 16),
                  _MetaRow(
                    label: 'Original',
                    value: '${expense.originalCurrency} ${expense.originalAmount ?? '—'}',
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _AnalyticPill extends StatelessWidget {
  const _AnalyticPill({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value, this.mono = false});
  final String label;
  final String value;
  final bool   mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}

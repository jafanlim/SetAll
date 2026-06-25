import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/category_utils.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const _green      = Color(0xFF22C55E);
const _orange     = Color(0xFFF97316);
const _purple     = Color(0xFF8B5CF6);

// ---------------------------------------------------------------------------
// BudgetsScreen — list of budget rows + add/edit/delete
// ---------------------------------------------------------------------------
class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme    = Theme.of(context);
    final progress = ref.watch(budgetProgressProvider);
    final baseCcyAsync = ref.watch(baseCurrencyProvider);
    final baseCurrency = baseCcyAsync.valueOrNull ?? 'USD';

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'budget.title'.tr(),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.3),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticUtils.primaryTap();
          _showEditSheet(context, ref, null, baseCurrency);
        },
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: Text('budget.add_budget'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      ),
      body: progress.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text(e.toString())),
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.savings_outlined,
                      size: 48, color: theme.colorScheme.onSurfaceVariant.withAlpha(80)),
                  const SizedBox(height: 12),
                  Text('budget.no_budgets'.tr(),
                      style: TextStyle(
                          fontSize: 15, color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 6),
                  Text('budget.no_budgets_hint'.tr(),
                      style: TextStyle(
                          fontSize: 12, color: theme.colorScheme.onSurfaceVariant.withAlpha(150))),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: list.length,
            itemBuilder: (ctx, i) => _BudgetTile(
              progress: list[i],
              onEdit: () {
                HapticUtils.selection();
                _showEditSheet(context, ref, list[i], baseCurrency);
              },
              onDelete: () async {
                HapticUtils.selection();
                await ref.read(setAllRepositoryProvider).deleteBudget(list[i].id);
                ref.invalidate(budgetsProvider);
                ref.invalidate(budgetProgressProvider);
              },
            ),
          );
        },
      ),
    );
  }

  void _showEditSheet(
    BuildContext context,
    WidgetRef ref,
    BudgetProgress? existing,
    String baseCurrency,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BudgetEditSheet(
        existing: existing,
        baseCurrency: baseCurrency,
        onSave: (row) async {
          await ref.read(setAllRepositoryProvider).upsertBudget(row);
          ref.invalidate(budgetsProvider);
          ref.invalidate(budgetProgressProvider);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Budget tile
// ---------------------------------------------------------------------------
class _BudgetTile extends StatelessWidget {
  const _BudgetTile({
    required this.progress,
    required this.onEdit,
    required this.onDelete,
  });

  final BudgetProgress  progress;
  final VoidCallback     onEdit;
  final VoidCallback     onDelete;

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final frac    = progress.fraction;
    final isOver  = progress.isOver;
    final barColor = isOver ? _orange : _green;
    final label   = progress.category != null ? categoryTr(progress.category!) : 'budget.overall'.tr();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(label,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w700, fontSize: 14)),
                ),
                IconButton(
                  icon: const Icon(Icons.edit_outlined, size: 16),
                  onPressed: onEdit,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 16,
                      color: theme.colorScheme.error),
                  onPressed: onDelete,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: frac,
                minHeight: 6,
                backgroundColor: barColor.withAlpha(30),
                valueColor: AlwaysStoppedAnimation<Color>(barColor),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${progress.currency} ${progress.spend.toStringAsFixed(2)} / '
                  '${progress.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isOver ? _orange : _green),
                ),
                Text(
                  isOver
                      ? 'budget.over_budget'.tr()
                      : '${(frac * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                      fontSize: 11,
                      color: isOver
                          ? _orange
                          : theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Budget edit sheet
// ---------------------------------------------------------------------------
class _BudgetEditSheet extends ConsumerStatefulWidget {
  const _BudgetEditSheet({
    required this.existing,
    required this.baseCurrency,
    required this.onSave,
  });

  final BudgetProgress? existing;
  final String          baseCurrency;
  final Future<void> Function(Map<String, dynamic>) onSave;

  @override
  ConsumerState<_BudgetEditSheet> createState() => _BudgetEditSheetState();
}

class _BudgetEditSheetState extends ConsumerState<_BudgetEditSheet> {
  final _amountCtrl = TextEditingController();
  String? _category;   // null = overall
  bool _saving = false;

  static const List<String?> _categories = [
    null,
    'Food & drink',
    'Transport',
    'Entertainment',
    'Bills & utilities',
    'Shopping',
    'Travel',
    'General',
  ];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      _category = widget.existing!.category;
      _amountCtrl.text = widget.existing!.amount.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amtStr = _amountCtrl.text.trim();
    final amount = Decimal.tryParse(amtStr);
    if (amount == null || amount <= Decimal.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('budget.invalid_amount'.tr())),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final row = {
        'id':       widget.existing?.id ?? const Uuid().v4(),
        'category': _category,
        'period':   'monthly',
        'amount':   amount.toString(),
        'currency': widget.baseCurrency,
      };
      await widget.onSave(row);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEdit = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── drag handle
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withAlpha(40),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // ── title
                Text(
                  isEdit ? 'budget.edit_budget'.tr() : 'budget.new_budget'.tr(),
                  style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800, letterSpacing: -0.3),
                ),
                const SizedBox(height: 20),

                // ── Category picker
                Text('budget.category_label'.tr(),
                    style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final cat = _categories[i];
                      final label = cat != null ? categoryTr(cat) : 'budget.overall'.tr();
                      final selected = _category == cat;
                      return GestureDetector(
                        onTap: () { HapticUtils.selection(); setState(() => _category = cat); },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: selected ? _purple : _purple.withAlpha(18),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(label,
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: selected ? Colors.white : _purple)),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 20),

                // ── Amount field
                Text('budget.amount_label'.tr(namedArgs: {'currency': widget.baseCurrency}),
                    style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 8),
                TextField(
                  controller: _amountCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    hintText: '0.00',
                    prefixIcon: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(widget.baseCurrency,
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface)),
                    ),
                    prefixIconConstraints: const BoxConstraints(minWidth: 0),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  ),
                ),
                const SizedBox(height: 24),

                // ── Save button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: _purple,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20, height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : Text('common.save'.tr(),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w700)),
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

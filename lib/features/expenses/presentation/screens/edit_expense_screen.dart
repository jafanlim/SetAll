import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/utils/split_engine.dart';
import '../../../../data/models/expense_model.dart';
import '../../../../data/models/profile_model.dart';
import '../../../../data/models/split_model.dart';
import '../../../../data/repositories/setall_repository.dart';
import '../../../../domain/entities/expense.dart';
import 'add_expense_screen.dart' show CurrencyPickerField;

/// Edit existing expense (Splitwise-style). Loads expense + splits, pre-fills form, saves via updateExpense.
class EditExpenseScreen extends ConsumerStatefulWidget {
  const EditExpenseScreen({
    super.key,
    required this.expenseId,
    required this.groupId,
    required this.groupName,
  });

  final String expenseId;
  final String groupId;
  final String groupName;

  @override
  ConsumerState<EditExpenseScreen> createState() => _EditExpenseScreenState();
}

const _teal   = Color(0xFF00D9B0);
const _orange = Color(0xFFFF8C42);

class _EditExpenseScreenState extends ConsumerState<EditExpenseScreen> {
  final _formKey             = GlobalKey<FormState>();
  final _amountController    = TextEditingController();
  final _descriptionController = TextEditingController();

  String    _currency    = 'USD';
  String    _category    = 'General';
  SplitMode _splitMode   = SplitMode.even;
  bool      _isLoading   = true;
  bool      _isSubmitting = false;
  ExpenseModel?        _expense;
  List<ProfileModel>   _members = [];
  String?              _payerId;

  // Per-member controllers for non-even splits (keyed by member id).
  final Map<String, TextEditingController> _customCtrl = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    for (final c in _customCtrl.values) c.dispose();
    super.dispose();
  }

  void _rebuildControllers() {
    for (final c in _customCtrl.values) c.dispose();
    _customCtrl.clear();
    final n = _members.length;
    if (_splitMode == SplitMode.percentage) {
      // 1 dp percentages; payer absorbs the rounding remainder.
      final baseVal = (1000 ~/ n) / 10.0;
      final baseFormatted = baseVal.toStringAsFixed(1);
      final payerVal = 100.0 - baseVal * (n - 1);
      final payerFormatted = payerVal.toStringAsFixed(1);
      for (var i = 0; i < n; i++) {
        final isPayer = _members[i].id == _payerId;
        _customCtrl[_members[i].id] = TextEditingController(
          text: isPayer ? payerFormatted : baseFormatted,
        );
      }
    } else {
      for (var i = 0; i < n; i++) {
        _customCtrl[_members[i].id] = TextEditingController(text: '1');
      }
    }
  }

  Future<void> _load() async {
    final repo       = ref.read(setAllRepositoryProvider);
    final expense    = await repo.getExpense(widget.expenseId);
    final splits     = await repo.getSplitsForExpense(widget.expenseId);
    final members    = await repo.getGroupMembers(widget.groupId);
    final currentUid = await repo.ensureUser();

    if (!mounted) return;
    setState(() {
      _expense  = expense;
      _members  = members;
      _isLoading = false;
      if (expense == null) return;

      _amountController.text      = expense.amount;
      _descriptionController.text = expense.description;
      _currency  = expense.currency;
      _category  = expense.category;
      _splitMode = expense.splitType == SplitType.even
          ? SplitMode.even
          : SplitMode.manual;
      _payerId   = expense.payerId.isNotEmpty ? expense.payerId : currentUid;

      // Pre-fill custom controllers with original-currency amounts (reverse USD).
      final rate = Decimal.tryParse(expense.exchangeRateApplied ?? '') ?? Decimal.one;
      for (final m in members) {
        SplitModel? split;
        try { split = splits.firstWhere((s) => s.userId == m.id); } catch (_) {}
        String initial = '';
        if (split != null) {
          final usdAmt = Decimal.tryParse(split.universalUsdOwed) ?? Decimal.zero;
          initial = rate > Decimal.zero
              ? (usdAmt / rate).toDecimal(scaleOnInfinitePrecision: 2).toString()
              : split.universalUsdOwed;
        }
        _customCtrl[m.id] = TextEditingController(text: initial);
      }
    });
  }

  Future<void> _submit() async {
    if (_expense == null || !_formKey.currentState!.validate()) return;

    final amountStr = _amountController.text.trim().replaceAll(',', '.');
    final amount    = Decimal.tryParse(amountStr);
    if (amount == null || amount <= Decimal.zero) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Enter a valid amount')));
      return;
    }

    final repo       = ref.read(setAllRepositoryProvider);
    final currentUid = await repo.ensureUser();
    final payerId    = _payerId ?? currentUid;
    if (payerId == null) {
      if (mounted) ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not get user. Try again.')));
      return;
    }

    final participantIds = _members.map((m) => m.id).toList();

    List<SplitResult> results;
    SplitType splitType;

    switch (_splitMode) {
      case SplitMode.even:
        results   = SplitEngine.splitEven(total: amount, participantIds: participantIds, payerId: payerId);
        splitType = SplitType.even;
      case SplitMode.percentage:
        final percents = participantIds
            .map((id) => Decimal.tryParse(_customCtrl[id]?.text.trim() ?? '') ?? Decimal.zero)
            .toList();
        final sum = percents.fold(Decimal.zero, (a, b) => a + b);
        if (sum <= Decimal.zero) {
          if (mounted) ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Percentages must sum to 100')));
          return;
        }
        results   = SplitEngine.splitCustom(total: amount, participantIds: participantIds, weights: percents);
        splitType = SplitType.parts;
      case SplitMode.shares:
        final shares = participantIds
            .map((id) => Decimal.tryParse(_customCtrl[id]?.text.trim() ?? '') ?? Decimal.zero)
            .toList();
        if (shares.every((s) => s <= Decimal.zero)) {
          if (mounted) ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Enter at least one share')));
          return;
        }
        results   = SplitEngine.splitCustom(total: amount, participantIds: participantIds, weights: shares);
        splitType = SplitType.parts;
      case SplitMode.manual:
        final amounts = participantIds
            .map((id) => Decimal.tryParse(
                  _customCtrl[id]?.text.trim().replaceAll(',', '.') ?? '') ??
                Decimal.zero)
            .toList();
        final totalManual = amounts.fold(Decimal.zero, (a, b) => a + b);
        if (totalManual != amount) {
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Amounts must sum to $amount (got $totalManual)')));
          return;
        }
        results   = SplitEngine.splitCustom(total: amount, participantIds: participantIds, amountsOwed: amounts);
        splitType = SplitType.manual;
    }

    final splits = results
        .map((r) => SplitInsert(userId: r.userId, universalUsdOwed: r.amountOwed))
        .toList();

    setState(() => _isSubmitting = true);

    final updated = await repo.updateExpense(
      expenseId:   widget.expenseId,
      groupId:     widget.groupId,
      payerId:     payerId,
      amount:      amount,
      description: _descriptionController.text.trim(),
      currency:    _currency,
      splitType:   splitType,
      splits:      splits,
      category:    _category,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (updated != null) {
        ref.invalidate(balanceSummaryProvider);
        ref.invalidate(recentExpensesProvider);
        ref.invalidate(groupExpensesProvider(widget.groupId));
        ref.invalidate(groupBalanceSummaryProvider(widget.groupId));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Expense updated')));
        context.pop();
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Could not update expense')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit expense')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_expense == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit expense')),
        body: const Center(child: Text('Expense not found')),
      );
    }

    final amountForTotal = Decimal.tryParse(
          _amountController.text.trim().replaceAll(',', '.')) ??
        Decimal.zero;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit expense'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(16.w),
          children: [
            Text(
              widget.groupName,
              style: theme.textTheme.titleMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            SizedBox(height: 20.h),

            // ── Amount ──────────────────────────────────────────────────────
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w700, color: _teal),
              decoration: InputDecoration(
                labelText: 'Amount',
                labelStyle: TextStyle(fontSize: 13.sp),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter amount';
                final d = Decimal.tryParse(v.trim().replaceAll(',', '.'));
                if (d == null || d <= Decimal.zero) return 'Enter a valid amount';
                return null;
              },
            ),
            SizedBox(height: 12.h),

            // ── Currency ─────────────────────────────────────────────────────
            CurrencyPickerField(
              selected: _currency,
              onChanged: (code) {
                HapticUtils.selection();
                setState(() => _currency = code);
              },
            ),
            SizedBox(height: 16.h),

            // ── Category ─────────────────────────────────────────────────────
            DropdownButtonFormField<String>(
              value: _category,
              decoration: InputDecoration(
                labelText: 'Category',
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide.none,
                ),
                isDense: true,
              ),
              items: kExpenseCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'General'),
            ),
            SizedBox(height: 16.h),

            // ── Description ──────────────────────────────────────────────────
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'Description (optional)',
                prefixIcon: const Icon(Icons.notes_outlined),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide.none,
                ),
              ),
              maxLines: 2,
            ),
            SizedBox(height: 16.h),

            // ── Paid by ──────────────────────────────────────────────────────
            if (_members.length > 1) ...[
              DropdownButtonFormField<String>(
                value: _members.any((m) => m.id == _payerId) ? _payerId : null,
                decoration: InputDecoration(
                  labelText: 'Paid by',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
                items: _members
                    .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name)))
                    .toList(),
                onChanged: (v) => setState(() => _payerId = v),
              ),
              SizedBox(height: 16.h),
            ],

            if (_expense?.createdAt != null) ...[
              Text(
                'Added ${_expense!.createdAt}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              SizedBox(height: 20.h),
            ],

            // ── Split mode ───────────────────────────────────────────────────
            Text(
              'How to split',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8.h),
            SegmentedButton<SplitMode>(
              segments: [
                ButtonSegment(
                  value: SplitMode.even,
                  label: Text('Even', style: TextStyle(fontSize: 11.sp)),
                  icon: Icon(Icons.equalizer, size: 14.sp),
                ),
                ButtonSegment(
                  value: SplitMode.percentage,
                  label: Text('%', style: TextStyle(fontSize: 11.sp)),
                  icon: Icon(Icons.percent, size: 14.sp),
                ),
                ButtonSegment(
                  value: SplitMode.shares,
                  label: Text('Shares', style: TextStyle(fontSize: 11.sp)),
                  icon: Icon(Icons.pie_chart_outline, size: 14.sp),
                ),
                ButtonSegment(
                  value: SplitMode.manual,
                  label: Text('Manual', style: TextStyle(fontSize: 11.sp)),
                  icon: Icon(Icons.edit, size: 14.sp),
                ),
              ],
              selected: {_splitMode},
              onSelectionChanged: (s) {
                HapticUtils.selection();
                setState(() {
                  _splitMode = s.isNotEmpty ? s.first : _splitMode;
                  _rebuildControllers();
                });
              },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return _teal.withValues(alpha: 0.15);
                  }
                  return theme.colorScheme.surfaceContainerHighest;
                }),
                foregroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) return _teal;
                  return theme.colorScheme.onSurfaceVariant;
                }),
              ),
            ),

            if (_splitMode != SplitMode.even) ...[
              SizedBox(height: 16.h),
              Text(
                _splitMode == SplitMode.percentage
                    ? 'Percentage per person (total = 100)'
                    : _splitMode == SplitMode.shares
                        ? 'Relative shares per person'
                        : 'Exact amount per person',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11.sp,
                ),
              ),
              SizedBox(height: 8.h),
              ..._members.map((m) {
                final c = _customCtrl[m.id];
                if (c == null) return const SizedBox.shrink();
                return Padding(
                  padding: EdgeInsets.only(bottom: 8.h),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          m.name,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontSize: 13.sp),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(width: 12.w),
                      SizedBox(
                        width: 90.w,
                        child: TextFormField(
                          controller: c,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          style: TextStyle(fontSize: 13.sp),
                          onChanged: (_) => setState(() {}),
                          decoration: InputDecoration(
                            hintText: _splitMode == SplitMode.percentage
                                ? '%'
                                : _splitMode == SplitMode.shares
                                    ? 'x'
                                    : _currency,
                            isDense: true,
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8.r),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }),
              if (_splitMode == SplitMode.manual) ...[
                SizedBox(height: 8.h),
                Builder(builder: (ctx) {
                  final entered = _members.fold<Decimal>(
                    Decimal.zero,
                    (sum, m) => sum +
                        (Decimal.tryParse(
                              _customCtrl[m.id]?.text.trim().replaceAll(',', '.') ?? '',
                            ) ??
                            Decimal.zero),
                  );
                  final ok = entered == amountForTotal && amountForTotal > Decimal.zero;
                  return Text(
                    'Total entered: $entered / $amountForTotal',
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: ok ? _teal : _orange,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }),
              ],
            ] else ...[
              SizedBox(height: 12.h),
              Container(
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: _teal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Row(
                  children: [
                    Icon(Icons.equalizer, color: _teal, size: 16.sp),
                    SizedBox(width: 8.w),
                    Text(
                      'Split evenly among ${_members.length} members',
                      style: TextStyle(color: _teal, fontSize: 12.sp),
                    ),
                  ],
                ),
              ),
            ],

            SizedBox(height: 40.h),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.black,
                padding: EdgeInsets.symmetric(vertical: 14.h),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 22, width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                    )
                  : const Text('Save changes', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            SizedBox(height: 32.h),
          ],
        ),
      ),
    );
  }
}

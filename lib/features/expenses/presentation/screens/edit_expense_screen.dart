import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/split_engine.dart';
import '../../../../data/models/expense_model.dart';
import '../../../../data/models/profile_model.dart';
import '../../../../data/models/split_model.dart';
import '../../../../data/repositories/setall_repository.dart';
import '../../../../domain/entities/expense.dart';

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

class _EditExpenseScreenState extends ConsumerState<EditExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  String _currency = 'USD';
  String _category = 'General';
  bool _splitEvenly = true;
  bool _isLoading = true;
  bool _isSubmitting = false;
  ExpenseModel? _expense;
  List<SplitModel> _splits = [];
  List<ProfileModel> _members = [];
  /// For custom split: member id -> amount string (pre-filled from splits).
  final Map<String, TextEditingController> _customAmountControllers = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    for (final c in _customAmountControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final repo = ref.read(setAllRepositoryProvider);
    final expense = await repo.getExpense(widget.expenseId);
    final splits = await repo.getSplitsForExpense(widget.expenseId);
    final members = await repo.getGroupMembers(widget.groupId);

    if (!mounted) return;
    setState(() {
      _expense = expense;
      _splits = splits;
      _members = members;
      _isLoading = false;
      if (expense != null) {
        _amountController.text = expense.amount;
        _descriptionController.text = expense.description;
        _currency = expense.currency;
        _category = expense.category;
        _splitEvenly = expense.splitType == SplitType.even;

        for (final m in members) {
          SplitModel? split;
          try {
            split = splits.firstWhere((s) => s.userId == m.id);
          } catch (_) {}
          final c = TextEditingController(text: split?.amountOwed ?? '');
          _customAmountControllers[m.id] = c;
        }
      }
    });
  }

  Future<void> _submit() async {
    if (_expense == null || !_formKey.currentState!.validate()) return;

    final amountStr = _amountController.text.trim().replaceAll(',', '.');
    final amount = Decimal.tryParse(amountStr);
    if (amount == null || amount <= Decimal.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return;
    }

    final repo = ref.read(setAllRepositoryProvider);
    final payerId = await repo.ensureUser();
    if (payerId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get user. Try again.')),
        );
      }
      return;
    }

    final participantIds = _members.map((m) => m.id).toList();
    if (participantIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No members in this group.')),
        );
      }
      return;
    }

    List<SplitInsert> splits;
    if (_splitEvenly) {
      splits = SplitEngine.splitEven(total: amount, participantIds: participantIds)
          .map((r) => SplitInsert(userId: r.userId, amountOwed: r.amountOwed))
          .toList();
    } else {
      final amounts = <Decimal>[];
      var sum = Decimal.zero;
      for (final id in participantIds) {
        final c = _customAmountControllers[id];
        final s = Decimal.tryParse(c?.text.trim().replaceAll(',', '.') ?? '') ?? Decimal.zero;
        amounts.add(s);
        sum += s;
      }
      if (sum != amount) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Custom split must sum to $amount (got $sum)')),
        );
        return;
      }
      splits = SplitEngine.splitCustom(
        total: amount,
        participantIds: participantIds,
        amountsOwed: amounts,
      ).map((r) => SplitInsert(userId: r.userId, amountOwed: r.amountOwed)).toList();
    }

    setState(() => _isSubmitting = true);

    final updated = await repo.updateExpense(
      expenseId: widget.expenseId,
      groupId: widget.groupId,
      payerId: payerId,
      amount: amount,
      description: _descriptionController.text.trim(),
      currency: _currency,
      splitType: _splitEvenly ? SplitType.even : SplitType.manual,
      splits: splits,
      category: _category,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (updated != null) {
        ref.invalidate(balanceSummaryProvider);
        ref.invalidate(recentExpensesProvider);
        ref.invalidate(groupExpensesProvider(widget.groupId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense updated')),
        );
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update expense')),
        );
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
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              widget.groupName,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '  ',
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'Enter amount';
                final d = Decimal.tryParse(v.trim().replaceAll(',', '.'));
                if (d == null || d <= Decimal.zero) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              decoration: const InputDecoration(labelText: 'Currency'),
              items: ['USD', 'EUR', 'GBP']
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _currency = v ?? 'USD'),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: kExpenseCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'General'),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Description'),
              maxLines: 2,
            ),
            if (_expense?.createdAt != null) ...[
              const SizedBox(height: 12),
              Text(
                'Added ${_expense!.createdAt}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 28),
            Text(
              'Split',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Split evenly'), icon: Icon(Icons.equalizer)),
                ButtonSegment(value: false, label: Text('Custom split'), icon: Icon(Icons.tune)),
              ],
              selected: {_splitEvenly},
              onSelectionChanged: (Set<bool> s) => setState(() => _splitEvenly = s.isNotEmpty ? s.first : _splitEvenly),
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return theme.colorScheme.primaryContainer;
                  }
                  return theme.colorScheme.surfaceContainerHighest;
                }),
              ),
            ),
            if (!_splitEvenly) ...[
              const SizedBox(height: 16),
              ..._members.map((m) {
                final c = _customAmountControllers[m.id];
                if (c == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: TextFormField(
                    controller: c,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: '${m.name} owes',
                      prefixText: '  ',
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                );
              }),
            ],
            const SizedBox(height: 40),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save changes'),
            ),
          ],
        ),
      ),
    );
  }
}

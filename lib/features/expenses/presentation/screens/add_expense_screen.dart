import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/utils/split_engine.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/repositories/setall_repository.dart';
import '../../../../domain/entities/expense.dart';

const List<String> kCurrencies = ['USD', 'EUR', 'GBP'];

enum _SplitMode { even, percentage, shares, manual }

class AddExpenseScreen extends ConsumerStatefulWidget {
  const AddExpenseScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  int _step = 0;
  static const int _totalSteps = 3;

  String _currency = 'USD';
  String _category = 'General';
  _SplitMode _splitMode = _SplitMode.even;
  bool _isSubmitting = false;
  final _rateOverrideController = TextEditingController();

  /// For percentage: index -> percentage (0-100). For shares: index -> shares. For manual: index -> amount.
  final List<TextEditingController> _customControllers = [];
  List<String> _memberIds = [];
  List<String> _memberNames = [];

  @override
  void initState() {
    super.initState();
    _loadMembers();
  }

  Future<void> _loadMembers() async {
    final repo = ref.read(setAllRepositoryProvider);
    final members = await repo.getGroupMembers(widget.groupId);
    if (!mounted) return;
    setState(() {
      _memberIds = members.map((m) => m.id).toList();
      _memberNames = members.map((m) => m.name).toList();
      _customControllers.clear();
      for (var i = 0; i < _memberIds.length; i++) {
        _customControllers.add(TextEditingController(text: _splitMode == _SplitMode.percentage ? '${100 ~/ _memberIds.length}' : '1'));
      }
    });
  }

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _rateOverrideController.dispose();
    for (final c in _customControllers) {
      c.dispose();
    }
    super.dispose();
  }

  void _nextStep() {
    if (_step == 0 && !_validateAmount()) return;
    HapticUtils.primaryTap();
    setState(() {
      if (_step < _totalSteps - 1) _step++;
    });
  }

  void _prevStep() {
    HapticUtils.lightTap();
    setState(() {
      if (_step > 0) _step--;
    });
  }

  bool _validateAmount() {
    final v = _amountController.text.trim().replaceAll(',', '.');
    final d = Decimal.tryParse(v);
    if (d == null || d <= Decimal.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return false;
    }
    return true;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
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

    if (widget.groupId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Choose a group first')),
      );
      return;
    }

    if (_memberIds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No members in this group. Add members first.')),
        );
      }
      return;
    }

    final baseCurrency = await ref.read(balanceServiceProvider).getBaseCurrency();
    final currencyService = ref.read(currencyServiceProvider);

    setState(() => _isSubmitting = true);

    List<SplitResult> results;
    SplitType splitType = SplitType.even;

    switch (_splitMode) {
      case _SplitMode.even:
        results = SplitEngine.splitEven(total: amount, participantIds: _memberIds);
        splitType = SplitType.even;
        break;
      case _SplitMode.percentage:
        final percents = <Decimal>[];
        var sum = Decimal.zero;
        for (final c in _customControllers) {
          final p = Decimal.tryParse(c.text.trim()) ?? Decimal.zero;
          percents.add(p);
          sum += p;
        }
        if (sum <= Decimal.zero) {
          if (mounted) {
            setState(() => _isSubmitting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Percentages must sum to 100')),
            );
          }
          return;
        }
        results = SplitEngine.splitCustom(
          total: amount,
          participantIds: _memberIds,
          weights: percents,
        );
        splitType = SplitType.parts;
        break;
      case _SplitMode.shares:
        final shares = <Decimal>[];
        for (final c in _customControllers) {
          final s = Decimal.tryParse(c.text.trim()) ?? Decimal.zero;
          shares.add(s);
        }
        if (shares.every((s) => s <= Decimal.zero)) {
          if (mounted) {
            setState(() => _isSubmitting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Enter at least one share')),
            );
          }
          return;
        }
        results = SplitEngine.splitCustom(
          total: amount,
          participantIds: _memberIds,
          weights: shares,
        );
        splitType = SplitType.parts;
        break;
      case _SplitMode.manual:
        final amounts = <Decimal>[];
        Decimal totalManual = Decimal.zero;
        for (final c in _customControllers) {
          final a = Decimal.tryParse(c.text.trim().replaceAll(',', '.')) ?? Decimal.zero;
          amounts.add(a);
          totalManual += a;
        }
        if (totalManual != amount) {
          if (mounted) {
            setState(() => _isSubmitting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Amounts must sum to $amount (got $totalManual)')),
            );
          }
          return;
        }
        results = SplitEngine.splitCustom(
          total: amount,
          participantIds: _memberIds,
          amountsOwed: amounts,
        );
        splitType = SplitType.manual;
        break;
    }

    Decimal amountToStore = amount;
    String currencyToStore = _currency;
    Decimal? originalAmount;
    String? originalCurrency;
    String? exchangeRateApplied;
    List<SplitInsert> splitsToStore;

    if (_currency == baseCurrency) {
      splitsToStore = results.map((r) => SplitInsert(userId: r.userId, amountOwed: r.amountOwed)).toList();
    } else {
      final rate = await currencyService.getRate(_currency, baseCurrency);
      amountToStore = (amount * rate).round(scale: 2);
      originalAmount = amount;
      originalCurrency = _currency;
      exchangeRateApplied = rate.toString();
      splitsToStore = results
          .map((r) => SplitInsert(userId: r.userId, amountOwed: (r.amountOwed * rate).round(scale: 2)))
          .toList();
      currencyToStore = baseCurrency;
    }

    final expense = await repo.addExpense(
      groupId: widget.groupId,
      payerId: payerId,
      amount: amountToStore,
      description: _descriptionController.text.trim(),
      currency: currencyToStore,
      splitType: splitType,
      splits: splitsToStore,
      category: _category,
      originalAmount: originalAmount,
      originalCurrency: originalCurrency,
      exchangeRateApplied: exchangeRateApplied,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (expense != null) {
        HapticUtils.success();
        ref.invalidate(balanceSummaryProvider);
        ref.invalidate(recentExpensesProvider);
        ref.invalidate(groupExpensesProvider(widget.groupId));
        ref.invalidate(groupBalanceSummaryProvider(widget.groupId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense saved')),
        );
        context.pop();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save expense')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text('Add expense · ${_step + 1}/$_totalSteps'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            HapticUtils.lightTap();
            context.pop();
          },
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (widget.groupName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  widget.groupName,
                  style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            _stepIndicator(theme),
            const SizedBox(height: 24),
            if (_step == 0) _buildStepAmount(theme),
            if (_step == 1) _buildStepSplit(theme),
            if (_step == 2) _buildStepDetails(theme),
            const SizedBox(height: 24),
            Row(
              children: [
                if (_step > 0)
                  TextButton.icon(
                    onPressed: _prevStep,
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('Back'),
                  ),
                const Spacer(),
                if (_step < _totalSteps - 1)
                  FilledButton.icon(
                    onPressed: _nextStep,
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    icon: _isSubmitting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(_isSubmitting ? 'Saving…' : 'Save expense'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepIndicator(ThemeData theme) {
    return Row(
      children: List.generate(_totalSteps, (i) {
        final active = i == _step;
        final done = i < _step;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: active
                    ? theme.colorScheme.primary
                    : (done ? theme.colorScheme.primary.withValues(alpha: 0.5) : theme.colorScheme.surfaceContainerHighest),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildStepAmount(ThemeData theme) {
    final baseAsync = ref.watch(baseCurrencyProvider);
    final base = baseAsync.valueOrNull;
    final rateAsync = (base != null && base != _currency)
        ? ref.watch(rateToBaseProvider((from: _currency, base: base)))
        : null;
    final rateStr = rateAsync?.valueOrNull;
    final rate = rateStr != null ? Decimal.tryParse(rateStr) : null;
    final amountStr = _amountController.text.trim().replaceAll(',', '.');
    final amountForPreview = Decimal.tryParse(amountStr);
    final convertedPreview = (base != null && base != _currency && rate != null && amountForPreview != null && amountForPreview > Decimal.zero)
        ? (amountForPreview * rate).round(scale: 2)
        : null;

    final rateDisplayAsync = _currency == 'USD' ? null : ref.watch(exchangeRateProvider(_currency));
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount & currency',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
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
            value: _currency,
            decoration: const InputDecoration(labelText: 'Currency'),
            items: kCurrencies.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _currency = v ?? 'USD'),
          ),
          if (convertedPreview != null && base != null) ...[
            const SizedBox(height: 12),
            Text(
              'Converted Amount Preview: ≈ $convertedPreview $base',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_currency != 'USD' && rateDisplayAsync != null) ...[
            const SizedBox(height: 12),
            Text(
              'Live rate: 1 USD = ${rateDisplayAsync.when(
                data: (r) => '$r $_currency',
                loading: () => '…',
                error: (e, st) => '—',
              )}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _rateOverrideController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Manual override (e.g. bank fee)',
                      hintText: '1 USD = ? $_currency',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: () async {
                    final v = _rateOverrideController.text.trim();
                    if (v.isEmpty) {
                      final svc = ref.read(currencyServiceProvider);
                      await svc.clearManualOverride('USD', _currency);
                      ref.invalidate(exchangeRateProvider(_currency));
                      if (mounted) setState(() {});
                      return;
                    }
                    final d = Decimal.tryParse(v.replaceAll(',', '.'));
                    if (d == null || d <= Decimal.zero) return;
                    final svc = ref.read(currencyServiceProvider);
                    await svc.setManualOverride('USD', _currency, d);
                    ref.invalidate(exchangeRateProvider(_currency));
                    if (mounted) setState(() {});
                    HapticUtils.success();
                  },
                  child: const Text('Apply'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStepSplit(ThemeData theme) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to split',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          SegmentedButton<_SplitMode>(
            segments: const [
              ButtonSegment(value: _SplitMode.even, label: Text('Even'), icon: Icon(Icons.equalizer)),
              ButtonSegment(value: _SplitMode.percentage, label: Text('%'), icon: Icon(Icons.percent)),
              ButtonSegment(value: _SplitMode.shares, label: Text('Shares'), icon: Icon(Icons.pie_chart_outline)),
              ButtonSegment(value: _SplitMode.manual, label: Text('Manual'), icon: Icon(Icons.edit)),
            ],
            selected: {_splitMode},
            onSelectionChanged: (Set<_SplitMode> s) {
              HapticUtils.selection();
              setState(() {
                _splitMode = s.isNotEmpty ? s.first : _splitMode;
                for (final c in _customControllers) {
                  c.dispose();
                }
                _customControllers.clear();
                final n = _memberIds.length;
                for (var i = 0; i < n; i++) {
                  if (_splitMode == _SplitMode.percentage) {
                    final p = n > 0 ? (i < n - 1 ? 100 ~/ n : 100 - (100 ~/ n) * (n - 1)) : 0;
                    _customControllers.add(TextEditingController(text: '$p'));
                  } else {
                    _customControllers.add(TextEditingController(text: '1'));
                  }
                }
              });
            },
            style: ButtonStyle(
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return theme.colorScheme.primaryContainer;
                return theme.colorScheme.surfaceContainerHighest;
              }),
            ),
          ),
          if (_splitMode != _SplitMode.even) ...[
            const SizedBox(height: 16),
            Text(
              _splitMode == _SplitMode.percentage
                  ? 'Percentage per person (should sum to 100)'
                  : _splitMode == _SplitMode.shares
                      ? 'Shares per person'
                      : 'Exact amount per person',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            ...List.generate(_memberIds.length, (i) {
              if (_customControllers.length <= i) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        _memberNames.length > i ? _memberNames[i] : 'Member ${i + 1}',
                        style: theme.textTheme.bodyMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 100,
                      child: TextFormField(
                        controller: _customControllers[i],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: InputDecoration(
                          hintText: _splitMode == _SplitMode.percentage ? '%' : _splitMode == _SplitMode.shares ? 'Shares' : 'Amount',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildStepDetails(ThemeData theme) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Details',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            value: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: kExpenseCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _category = v ?? 'General'),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _descriptionController,
            decoration: const InputDecoration(labelText: 'Description (optional)'),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

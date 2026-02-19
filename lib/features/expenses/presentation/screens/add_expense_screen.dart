import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/utils/split_engine.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/repositories/setall_repository.dart';
import '../../../../domain/entities/expense.dart';

// ---------------------------------------------------------------------------
// Currency catalogue (ISO 4217 top-30 by trading volume/prevalence)
// ---------------------------------------------------------------------------
const List<Map<String, String>> kCurrencyList = [
  {'code': 'USD', 'name': 'US Dollar',           'flag': '🇺🇸'},
  {'code': 'EUR', 'name': 'Euro',                 'flag': '🇪🇺'},
  {'code': 'GBP', 'name': 'British Pound',        'flag': '🇬🇧'},
  {'code': 'JPY', 'name': 'Japanese Yen',         'flag': '🇯🇵'},
  {'code': 'AUD', 'name': 'Australian Dollar',    'flag': '🇦🇺'},
  {'code': 'CAD', 'name': 'Canadian Dollar',      'flag': '🇨🇦'},
  {'code': 'CHF', 'name': 'Swiss Franc',          'flag': '🇨🇭'},
  {'code': 'CNY', 'name': 'Chinese Yuan',         'flag': '🇨🇳'},
  {'code': 'HKD', 'name': 'Hong Kong Dollar',     'flag': '🇭🇰'},
  {'code': 'NZD', 'name': 'New Zealand Dollar',   'flag': '🇳🇿'},
  {'code': 'SEK', 'name': 'Swedish Krona',        'flag': '🇸🇪'},
  {'code': 'KRW', 'name': 'South Korean Won',     'flag': '🇰🇷'},
  {'code': 'SGD', 'name': 'Singapore Dollar',     'flag': '🇸🇬'},
  {'code': 'NOK', 'name': 'Norwegian Krone',      'flag': '🇳🇴'},
  {'code': 'MXN', 'name': 'Mexican Peso',         'flag': '🇲🇽'},
  {'code': 'INR', 'name': 'Indian Rupee',         'flag': '🇮🇳'},
  {'code': 'RUB', 'name': 'Russian Ruble',        'flag': '🇷🇺'},
  {'code': 'ZAR', 'name': 'South African Rand',   'flag': '🇿🇦'},
  {'code': 'TRY', 'name': 'Turkish Lira',         'flag': '🇹🇷'},
  {'code': 'BRL', 'name': 'Brazilian Real',       'flag': '🇧🇷'},
  {'code': 'THB', 'name': 'Thai Baht',            'flag': '🇹🇭'},
  {'code': 'DKK', 'name': 'Danish Krone',         'flag': '🇩🇰'},
  {'code': 'PLN', 'name': 'Polish Zloty',         'flag': '🇵🇱'},
  {'code': 'TWD', 'name': 'Taiwan Dollar',        'flag': '🇹🇼'},
  {'code': 'CZK', 'name': 'Czech Koruna',         'flag': '🇨🇿'},
  {'code': 'HUF', 'name': 'Hungarian Forint',     'flag': '🇭🇺'},
  {'code': 'ILS', 'name': 'Israeli Shekel',       'flag': '🇮🇱'},
  {'code': 'MYR', 'name': 'Malaysian Ringgit',    'flag': '🇲🇾'},
  {'code': 'PHP', 'name': 'Philippine Peso',      'flag': '🇵🇭'},
  {'code': 'AED', 'name': 'UAE Dirham',           'flag': '🇦🇪'},
];

List<String> get kCurrencyCodes =>
    kCurrencyList.map((c) => c['code']!).toList();

// ---------------------------------------------------------------------------
// Fintech accent colours (must match dashboard)
// ---------------------------------------------------------------------------
const _teal = Color(0xFF00D9B0);
const _orange = Color(0xFFFF8C42);

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
  final _amountCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _rateOverrideCtrl = TextEditingController();

  int _step = 0;
  static const int _totalSteps = 3;

  String _currency = 'USD';
  String _category = 'General';
  _SplitMode _splitMode = _SplitMode.even;
  bool _isSubmitting = false;

  final List<TextEditingController> _customCtrl = [];
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
      _rebuildControllers();
    });
  }

  void _rebuildControllers() {
    for (final c in _customCtrl) {
      c.dispose();
    }
    _customCtrl.clear();
    final n = _memberIds.length;
    for (var i = 0; i < n; i++) {
      final text = _splitMode == _SplitMode.percentage
          ? '${i < n - 1 ? 100 ~/ n : 100 - (100 ~/ n) * (n - 1)}'
          : '1';
      _customCtrl.add(TextEditingController(text: text));
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descriptionCtrl.dispose();
    _rateOverrideCtrl.dispose();
    for (final c in _customCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------

  void _nextStep() {
    if (_step == 0 && !_validateAmount()) return;
    HapticUtils.primaryTap();
    setState(() { if (_step < _totalSteps - 1) _step++; });
  }

  void _prevStep() {
    HapticUtils.lightTap();
    setState(() { if (_step > 0) _step--; });
  }

  bool _validateAmount() {
    final v = _amountCtrl.text.trim().replaceAll(',', '.');
    final d = Decimal.tryParse(v);
    if (d == null || d <= Decimal.zero) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid amount')),
      );
      return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Submit
  // ---------------------------------------------------------------------------

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final amountStr = _amountCtrl.text.trim().replaceAll(',', '.');
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
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Choose a group first')));
      return;
    }
    if (_memberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No members in this group. Add members first.')),
      );
      return;
    }

    final baseCurrency = await ref.read(balanceServiceProvider).getBaseCurrency();
    final currencyService = ref.read(currencyServiceProvider);

    setState(() => _isSubmitting = true);

    // -- Build split results --------------------------------------------------
    List<SplitResult> results;
    SplitType splitType;

    switch (_splitMode) {
      case _SplitMode.even:
        results = SplitEngine.splitEven(
          total: amount,
          participantIds: _memberIds,
        );
        splitType = SplitType.even;
      case _SplitMode.percentage:
        final percents = _customCtrl
            .map((c) => Decimal.tryParse(c.text.trim()) ?? Decimal.zero)
            .toList();
        final sum = percents.fold(Decimal.zero, (a, b) => a + b);
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
      case _SplitMode.shares:
        final shares = _customCtrl
            .map((c) => Decimal.tryParse(c.text.trim()) ?? Decimal.zero)
            .toList();
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
      case _SplitMode.manual:
        final amounts = _customCtrl
            .map((c) =>
                Decimal.tryParse(c.text.trim().replaceAll(',', '.')) ??
                Decimal.zero)
            .toList();
        final totalManual = amounts.fold(Decimal.zero, (a, b) => a + b);
        if (totalManual != amount) {
          if (mounted) {
            setState(() => _isSubmitting = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Amounts must sum to $amount (got $totalManual)',
                ),
              ),
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
    }

    // -- Currency conversion --------------------------------------------------
    // Always compute base_amount_at_entry regardless of currency match to
    // guarantee the field is set on every new expense (eliminates $104 bug).
    Decimal amountToStore = amount;
    String currencyToStore = _currency;
    Decimal? originalAmount;
    String? originalCurrency;
    String? exchangeRateApplied;
    late Decimal baseAmountAtEntry;
    late List<SplitInsert> splitsToStore;

    if (_currency == baseCurrency) {
      baseAmountAtEntry = amount;
      splitsToStore = results
          .map((r) => SplitInsert(userId: r.userId, amountOwed: r.amountOwed))
          .toList();
    } else {
      final rate = await currencyService.getRate(_currency, baseCurrency);
      amountToStore = (amount * rate).round(scale: 2);
      baseAmountAtEntry = amountToStore;
      originalAmount = amount;
      originalCurrency = _currency;
      exchangeRateApplied = rate.toString();
      splitsToStore = results
          .map((r) => SplitInsert(
                userId: r.userId,
                amountOwed: (r.amountOwed * rate).round(scale: 2),
              ))
          .toList();
      currencyToStore = baseCurrency;
    }

    final expense = await repo.addExpense(
      groupId: widget.groupId,
      payerId: payerId,
      amount: amountToStore,
      description: _descriptionCtrl.text.trim(),
      currency: currencyToStore,
      splitType: splitType,
      splits: splitsToStore,
      category: _category,
      originalAmount: originalAmount,
      originalCurrency: originalCurrency,
      exchangeRateApplied: exchangeRateApplied,
      baseAmountAtEntry: baseAmountAtEntry,
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
          SnackBar(
            content: const Text('Expense saved'),
            backgroundColor: _teal.withValues(alpha: 0.9),
          ),
        );
        context.pop();
      } else {
        HapticUtils.lightTap();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not save expense')),
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Add expense · ${_step + 1}/$_totalSteps',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16.sp),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        scrolledUnderElevation: 0,
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
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          children: [
            if (widget.groupName.isNotEmpty)
              Padding(
                padding: EdgeInsets.only(bottom: 10.h),
                child: Row(
                  children: [
                    Icon(Icons.group_outlined,
                        size: 14.sp,
                        color: theme.colorScheme.onSurfaceVariant),
                    SizedBox(width: 6.w),
                    Text(
                      widget.groupName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12.sp,
                      ),
                    ),
                  ],
                ),
              ),
            _stepIndicator(theme),
            SizedBox(height: 20.h),
            if (_step == 0) _buildStepAmount(theme),
            if (_step == 1) _buildStepSplit(theme),
            if (_step == 2) _buildStepDetails(theme),
            SizedBox(height: 24.h),
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
                    style: FilledButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.black,
                    ),
                    icon: const Icon(Icons.arrow_forward),
                    label: const Text('Next'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _isSubmitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.black,
                    ),
                    icon: _isSubmitting
                        ? SizedBox(
                            width: 18.w,
                            height: 18.w,
                            child: const CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.black54,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(_isSubmitting ? 'Saving…' : 'Save expense'),
                  ),
              ],
            ),
            SizedBox(height: 32.h),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step indicator
  // ---------------------------------------------------------------------------

  Widget _stepIndicator(ThemeData theme) {
    return Row(
      children: List.generate(_totalSteps, (i) {
        final active = i == _step;
        final done = i < _step;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 2.w),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 4.h,
              decoration: BoxDecoration(
                color: active
                    ? _teal
                    : done
                        ? _teal.withValues(alpha: 0.4)
                        : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
          ),
        );
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 1 – Amount & Currency
  // ---------------------------------------------------------------------------

  Widget _buildStepAmount(ThemeData theme) {
    final baseAsync = ref.watch(baseCurrencyProvider);
    final base = baseAsync.valueOrNull;
    final rateAsync = (base != null && base != _currency)
        ? ref.watch(rateToBaseProvider((from: _currency, base: base)))
        : null;
    final rateStr = rateAsync?.valueOrNull;
    final rate = rateStr != null ? Decimal.tryParse(rateStr) : null;
    final amountStr = _amountCtrl.text.trim().replaceAll(',', '.');
    final amountForPreview = Decimal.tryParse(amountStr);
    final convertedPreview = (base != null &&
            base != _currency &&
            rate != null &&
            amountForPreview != null &&
            amountForPreview > Decimal.zero)
        ? (amountForPreview * rate).round(scale: 2)
        : null;

    return GlassCard(
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount & currency',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15.sp,
            ),
          ),
          SizedBox(height: 16.h),

          // Amount field
          TextFormField(
            controller: _amountCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
              fontSize: 22.sp,
              fontWeight: FontWeight.w700,
              color: _teal,
            ),
            decoration: InputDecoration(
              labelText: 'Amount',
              labelStyle: TextStyle(fontSize: 13.sp),
              prefixIcon: const Icon(Icons.attach_money, color: _teal),
              filled: true,
              fillColor:
                  theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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

          // Currency picker
          _CurrencyPicker(
            selected: _currency,
            onChanged: (code) {
              HapticUtils.selection();
              setState(() {
                _currency = code;
                _rateOverrideCtrl.clear();
              });
            },
          ),
          SizedBox(height: 12.h),

          // Conversion preview
          if (convertedPreview != null && base != null)
            _ConversionPreviewChip(
              fromAmount: amountForPreview!,
              fromCurrency: _currency,
              toAmount: convertedPreview,
              toCurrency: base,
            ),

          // DB rate display + manual override
          if (base != null && base != _currency) ...[
            SizedBox(height: 12.h),
            _RateDisplayRow(
              fromCurrency: _currency,
              toCurrency: base,
              rateAsync: rateAsync,
            ),
            SizedBox(height: 8.h),
            _ManualRateRow(
              rateCtrl: _rateOverrideCtrl,
              fromCurrency: _currency,
              toCurrency: base,
              onApply: () async {
                final v = _rateOverrideCtrl.text.trim();
                final svc = ref.read(currencyServiceProvider);
                if (v.isEmpty) {
                  await svc.clearManualOverride(_currency, base);
                } else {
                  final d = Decimal.tryParse(v.replaceAll(',', '.'));
                  if (d != null && d > Decimal.zero) {
                    await svc.setManualOverride(_currency, base, d);
                  }
                }
                ref.invalidate(rateToBaseProvider((from: _currency, base: base)));
                if (mounted) setState(() {});
                HapticUtils.success();
              },
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 2 – Split
  // ---------------------------------------------------------------------------

  Widget _buildStepSplit(ThemeData theme) {
    return GlassCard(
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to split',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15.sp,
            ),
          ),
          SizedBox(height: 14.h),
          SegmentedButton<_SplitMode>(
            segments: [
              ButtonSegment(
                value: _SplitMode.even,
                label: Text('Even', style: TextStyle(fontSize: 11.sp)),
                icon: Icon(Icons.equalizer, size: 14.sp),
              ),
              ButtonSegment(
                value: _SplitMode.percentage,
                label: Text('%', style: TextStyle(fontSize: 11.sp)),
                icon: Icon(Icons.percent, size: 14.sp),
              ),
              ButtonSegment(
                value: _SplitMode.shares,
                label: Text('Shares', style: TextStyle(fontSize: 11.sp)),
                icon: Icon(Icons.pie_chart_outline, size: 14.sp),
              ),
              ButtonSegment(
                value: _SplitMode.manual,
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
          if (_splitMode != _SplitMode.even) ...[
            SizedBox(height: 16.h),
            Text(
              _splitMode == _SplitMode.percentage
                  ? 'Percentage per person (total = 100)'
                  : _splitMode == _SplitMode.shares
                      ? 'Relative shares per person'
                      : 'Exact amount per person',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11.sp,
              ),
            ),
            SizedBox(height: 8.h),
            ...List.generate(_memberIds.length, (i) {
              if (_customCtrl.length <= i) return const SizedBox.shrink();
              return Padding(
                padding: EdgeInsets.only(bottom: 8.h),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        _memberNames.length > i
                            ? _memberNames[i]
                            : 'Member ${i + 1}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontSize: 13.sp),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: 12.w),
                    SizedBox(
                      width: 90.w,
                      child: TextFormField(
                        controller: _customCtrl[i],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: TextStyle(fontSize: 13.sp),
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: _splitMode == _SplitMode.percentage
                              ? '%'
                              : _splitMode == _SplitMode.shares
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
            // Percentage sum indicator
            if (_splitMode == _SplitMode.percentage) ...[
              SizedBox(height: 8.h),
              _PercentageSumIndicator(controllers: _customCtrl),
            ],
            // Manual amount sum indicator
            if (_splitMode == _SplitMode.manual) ...[
              SizedBox(height: 8.h),
              _ManualSumIndicator(
                controllers: _customCtrl,
                total: Decimal.tryParse(
                      _amountCtrl.text.trim().replaceAll(',', '.'),
                    ) ??
                    Decimal.zero,
                currency: _currency,
              ),
            ],
          ] else ...[
            SizedBox(height: 14.h),
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
                    'Split evenly among ${_memberIds.length} members',
                    style: TextStyle(color: _teal, fontSize: 12.sp),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Step 3 – Details
  // ---------------------------------------------------------------------------

  Widget _buildStepDetails(ThemeData theme) {
    return GlassCard(
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Details',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15.sp,
            ),
          ),
          SizedBox(height: 16.h),
          // Category chips
          Text(
            'Category',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11.sp,
            ),
          ),
          SizedBox(height: 8.h),
          Wrap(
            spacing: 8.w,
            runSpacing: 6.h,
            children: kExpenseCategories.map((cat) {
              final selected = _category == cat;
              return FilterChip(
                label: Text(cat, style: TextStyle(fontSize: 11.sp)),
                selected: selected,
                selectedColor: _teal.withValues(alpha: 0.15),
                checkmarkColor: _teal,
                labelStyle: TextStyle(
                  color: selected ? _teal : null,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
                onSelected: (_) {
                  HapticUtils.selection();
                  setState(() => _category = cat);
                },
              );
            }).toList(),
          ),
          SizedBox(height: 16.h),
          TextFormField(
            controller: _descriptionCtrl,
            decoration: InputDecoration(
              labelText: 'Description (optional)',
              labelStyle: TextStyle(fontSize: 13.sp),
              prefixIcon: const Icon(Icons.notes_outlined),
              filled: true,
              fillColor:
                  theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide.none,
              ),
            ),
            maxLines: 2,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable sub-widgets
// ---------------------------------------------------------------------------

class _CurrencyPicker extends StatelessWidget {
  const _CurrencyPicker({
    required this.selected,
    required this.onChanged,
  });

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = kCurrencyList.firstWhere(
      (c) => c['code'] == selected,
      orElse: () => {'code': selected, 'name': selected, 'flag': ''},
    );

    return InkWell(
      onTap: () async {
        HapticUtils.lightTap();
        final result = await showModalBottomSheet<String>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          builder: (_) => _CurrencySearchSheet(selected: selected),
        );
        if (result != null) onChanged(result);
      },
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12.r),
        ),
        child: Row(
          children: [
            Text(entry['flag'] ?? '', style: TextStyle(fontSize: 20.sp)),
            SizedBox(width: 10.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry['code']!,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.sp,
                      color: _teal,
                    ),
                  ),
                  Text(
                    entry['name']!,
                    style: TextStyle(
                      fontSize: 11.sp,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.expand_more,
                color: theme.colorScheme.onSurfaceVariant, size: 18.sp),
          ],
        ),
      ),
    );
  }
}

class _CurrencySearchSheet extends StatefulWidget {
  const _CurrencySearchSheet({required this.selected});
  final String selected;

  @override
  State<_CurrencySearchSheet> createState() => _CurrencySearchSheetState();
}

class _CurrencySearchSheetState extends State<_CurrencySearchSheet> {
  String _query = '';

  List<Map<String, String>> get _filtered {
    if (_query.isEmpty) return kCurrencyList;
    final q = _query.toUpperCase();
    return kCurrencyList
        .where((c) =>
            c['code']!.contains(q) ||
            c['name']!.toUpperCase().contains(_query.toUpperCase()))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, ctrl) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
        ),
        child: Column(
          children: [
            SizedBox(height: 8.h),
            Container(
              width: 36.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search currency…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: ctrl,
                itemCount: _filtered.length,
                itemBuilder: (_, i) {
                  final c = _filtered[i];
                  final isSelected = c['code'] == widget.selected;
                  return ListTile(
                    dense: true,
                    leading: Text(c['flag'] ?? '',
                        style: TextStyle(fontSize: 22.sp)),
                    title: Text(
                      c['code']!,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13.sp,
                        color: isSelected ? _teal : null,
                      ),
                    ),
                    subtitle: Text(
                      c['name']!,
                      style: TextStyle(fontSize: 11.sp),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: _teal)
                        : null,
                    onTap: () {
                      HapticUtils.selection();
                      Navigator.pop(context, c['code']);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversionPreviewChip extends StatelessWidget {
  const _ConversionPreviewChip({
    required this.fromAmount,
    required this.fromCurrency,
    required this.toAmount,
    required this.toCurrency,
  });

  final Decimal fromAmount;
  final String fromCurrency;
  final Decimal toAmount;
  final String toCurrency;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: _teal.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.swap_horiz, color: _teal, size: 14.sp),
          SizedBox(width: 6.w),
          Text(
            '$fromAmount $fromCurrency  →  ≈ $toAmount $toCurrency',
            style: TextStyle(
              color: _teal,
              fontWeight: FontWeight.w600,
              fontSize: 12.sp,
            ),
          ),
        ],
      ),
    );
  }
}

class _RateDisplayRow extends StatelessWidget {
  const _RateDisplayRow({
    required this.fromCurrency,
    required this.toCurrency,
    required this.rateAsync,
  });

  final String fromCurrency;
  final String toCurrency;
  final AsyncValue<String>? rateAsync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rateStr = rateAsync?.when(
          data: (r) => '1 $fromCurrency = $r $toCurrency',
          loading: () => 'Fetching rate…',
          error: (_, _) => 'Rate unavailable',
        ) ??
        '—';

    return Row(
      children: [
        Icon(Icons.bolt, color: _orange, size: 14.sp),
        SizedBox(width: 4.w),
        Text(
          rateStr,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11.sp,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Split sum indicators
// ---------------------------------------------------------------------------

class _PercentageSumIndicator extends StatelessWidget {
  const _PercentageSumIndicator({required this.controllers});
  final List<TextEditingController> controllers;

  @override
  Widget build(BuildContext context) {
    final sum = controllers.fold<Decimal>(
      Decimal.zero,
      (acc, c) => acc + (Decimal.tryParse(c.text.trim()) ?? Decimal.zero),
    );
    final isExact = sum == Decimal.fromInt(100);
    final diff = (Decimal.fromInt(100) - sum).abs();
    final color = isExact ? _teal : _orange;
    final label = isExact
        ? 'Sum: 100% — ready to split'
        : sum < Decimal.fromInt(100)
            ? 'Sum: $sum% — needs $diff% more'
            : 'Sum: $sum% — $diff% over budget';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        children: [
          Icon(
            isExact ? Icons.check_circle_outline : Icons.warning_amber_outlined,
            color: color,
            size: 13.sp,
          ),
          SizedBox(width: 6.w),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11.sp,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualSumIndicator extends StatelessWidget {
  const _ManualSumIndicator({
    required this.controllers,
    required this.total,
    required this.currency,
  });

  final List<TextEditingController> controllers;
  final Decimal total;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final sum = controllers.fold<Decimal>(
      Decimal.zero,
      (acc, c) => acc +
          (Decimal.tryParse(c.text.trim().replaceAll(',', '.')) ?? Decimal.zero),
    );
    final isExact = total > Decimal.zero && sum == total;
    final color = isExact ? _teal : _orange;
    final label = total == Decimal.zero
        ? 'Enter total amount first'
        : isExact
            ? 'Sum: $currency $sum — matches total'
            : sum < total
                ? 'Sum: $currency $sum — ${total - sum} remaining'
                : 'Sum: $currency $sum — ${sum - total} over total';

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8.r),
      ),
      child: Row(
        children: [
          Icon(
            isExact ? Icons.check_circle_outline : Icons.info_outline,
            color: color,
            size: 13.sp,
          ),
          SizedBox(width: 6.w),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualRateRow extends StatelessWidget {
  const _ManualRateRow({
    required this.rateCtrl,
    required this.fromCurrency,
    required this.toCurrency,
    required this.onApply,
  });

  final TextEditingController rateCtrl;
  final String fromCurrency;
  final String toCurrency;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: rateCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(fontSize: 12.sp),
            decoration: InputDecoration(
              labelText: 'Manual rate (bank / cash)',
              hintText: '1 $fromCurrency = ? $toCurrency',
              labelStyle: TextStyle(fontSize: 11.sp),
              isDense: true,
              filled: true,
              fillColor:
                  theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8.r),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        SizedBox(width: 8.w),
        OutlinedButton(
          onPressed: onApply,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: _teal),
            foregroundColor: _teal,
            padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
          ),
          child: Text('Apply', style: TextStyle(fontSize: 12.sp)),
        ),
      ],
    );
  }
}

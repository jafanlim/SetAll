import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/utils/split_engine.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/repositories/setall_repository.dart';
import '../../../../domain/entities/expense.dart';

// ---------------------------------------------------------------------------
// Currency catalogue — "Most Used" first, then alphabetical remainder
// ---------------------------------------------------------------------------
const List<Map<String, String>> kCurrencyList = [
  // ── Most used (shown first in picker) ──
  {'code': 'USD', 'name': 'US Dollar',           'flag': '🇺🇸'},
  {'code': 'EUR', 'name': 'Euro',                'flag': '🇪🇺'},
  {'code': 'GBP', 'name': 'British Pound',       'flag': '🇬🇧'},
  {'code': 'GEL', 'name': 'Georgian Lari',       'flag': '🇬🇪'},
  {'code': 'AED', 'name': 'UAE Dirham',          'flag': '🇦🇪'},
  {'code': 'TRY', 'name': 'Turkish Lira',        'flag': '🇹🇷'},
  {'code': 'PLN', 'name': 'Polish Złoty',        'flag': '🇵🇱'},
  // ── Extended list ──
  {'code': 'AUD', 'name': 'Australian Dollar',   'flag': '🇦🇺'},
  {'code': 'BRL', 'name': 'Brazilian Real',      'flag': '🇧🇷'},
  {'code': 'CAD', 'name': 'Canadian Dollar',     'flag': '🇨🇦'},
  {'code': 'CHF', 'name': 'Swiss Franc',         'flag': '🇨🇭'},
  {'code': 'CNY', 'name': 'Chinese Yuan',        'flag': '🇨🇳'},
  {'code': 'CZK', 'name': 'Czech Koruna',        'flag': '🇨🇿'},
  {'code': 'DKK', 'name': 'Danish Krone',        'flag': '🇩🇰'},
  {'code': 'HKD', 'name': 'Hong Kong Dollar',    'flag': '🇭🇰'},
  {'code': 'HUF', 'name': 'Hungarian Forint',    'flag': '🇭🇺'},
  {'code': 'ILS', 'name': 'Israeli Shekel',      'flag': '🇮🇱'},
  {'code': 'INR', 'name': 'Indian Rupee',        'flag': '🇮🇳'},
  {'code': 'JPY', 'name': 'Japanese Yen',        'flag': '🇯🇵'},
  {'code': 'KRW', 'name': 'South Korean Won',    'flag': '🇰🇷'},
  {'code': 'MXN', 'name': 'Mexican Peso',        'flag': '🇲🇽'},
  {'code': 'MYR', 'name': 'Malaysian Ringgit',   'flag': '🇲🇾'},
  {'code': 'NOK', 'name': 'Norwegian Krone',     'flag': '🇳🇴'},
  {'code': 'NZD', 'name': 'New Zealand Dollar',  'flag': '🇳🇿'},
  {'code': 'PHP', 'name': 'Philippine Peso',     'flag': '🇵🇭'},
  {'code': 'SEK', 'name': 'Swedish Krona',       'flag': '🇸🇪'},
  {'code': 'SGD', 'name': 'Singapore Dollar',    'flag': '🇸🇬'},
  {'code': 'THB', 'name': 'Thai Baht',           'flag': '🇹🇭'},
  {'code': 'TWD', 'name': 'Taiwan Dollar',       'flag': '🇹🇼'},
  {'code': 'ZAR', 'name': 'South African Rand',  'flag': '🇿🇦'},
];

List<String> get kCurrencyCodes =>
    kCurrencyList.map((c) => c['code']!).toList();

/// Returns the ISO currency symbol for [code] using intl's NumberFormat.
/// Falls back to the code itself if the symbol is unavailable.
String currencySymbol(String code) {
  try {
    final format = NumberFormat.simpleCurrency(name: code, decimalDigits: 0);
    final sym = format.currencySymbol;
    // NumberFormat sometimes returns the code itself — still fine.
    return sym.isEmpty ? code : sym;
  } catch (_) {
    return code;
  }
}

// ---------------------------------------------------------------------------
// Fintech accent colours (must match dashboard)
// ---------------------------------------------------------------------------
const _teal = Color(0xFF00D9B0);
const _orange = Color(0xFFFF8C42);


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
  SplitMode _splitMode = SplitMode.even;
  bool _isSubmitting = false;
  bool _isIncome = false;
  String? _payerId;

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
    final uid = await repo.ensureUser();
    final members = await repo.getGroupMembers(widget.groupId);
    if (!mounted) return;

    var ids   = members.map((m) => m.id).toList();
    var names = members.map((m) => m.name).toList();

    debugPrint('[AddExpense] _loadMembers: uid=$uid, members=${ids.length}: $ids');

    // Guarantee the current user is always a participant in the split.
    // This guards against the offline-first race where the local SQLite
    // group_members row is written but the creator's profile row isn't
    // cached yet, causing getGroupMembers to return an empty list.
    if (uid != null && !ids.contains(uid)) {
      final profile = await repo.getCurrentUserProfile();
      ids   = [uid,                       ...ids];
      names = [profile?.name ?? 'You', ...names];
      debugPrint('[AddExpense] _loadMembers: prepended current user, now ${ids.length} members');
    }

    setState(() {
      _memberIds   = ids;
      _memberNames = names;
      _payerId ??= uid; // default payer = current user
      _rebuildControllers();
    });
  }

  void _rebuildControllers() {
    for (final c in _customCtrl) {
      c.dispose();
    }
    _customCtrl.clear();
    final n = _memberIds.length;
    if (_splitMode == SplitMode.percentage) {
      // Use 1 decimal place. Assign remainder to payer so it always sums to 100.
      final payerIndex = _memberIds.indexOf(_payerId ?? '');
      // Compute each share to 1 dp, then give payer the residual.
      final baseVal = (1000 ~/ n) / 10.0; // e.g. 33.3 for n=3
      final baseFormatted = baseVal.toStringAsFixed(1);
      final sumOthers = baseVal * (n - 1);
      final payerVal = 100.0 - sumOthers;
      final payerFormatted = payerVal.toStringAsFixed(1);
      for (var i = 0; i < n; i++) {
        final isPayer = i == payerIndex || (payerIndex == -1 && i == 0);
        _customCtrl.add(TextEditingController(
          text: isPayer ? payerFormatted : baseFormatted,
        ));
      }
    } else {
      for (var i = 0; i < n; i++) {
        _customCtrl.add(TextEditingController(text: '1'));
      }
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
    setState(() { if (_step < _effectiveTotalSteps - 1) _step++; });
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
    final currentUid = await repo.ensureUser();
    final payerId = _payerId ?? currentUid;
    if (!mounted) return;
    if (payerId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not get user. Try again.')),
        );
      }
      return;
    }

    final isPersonal = widget.groupId.isEmpty;

    if (!isPersonal && _memberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No members in this group. Add members first.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    debugPrint('[AddExpense] _submit: payerId=$payerId currentUid=$currentUid memberIds=${_memberIds.length}: $_memberIds, splitMode=$_splitMode, amount=$amount');

    // -- Personal (wallet) mode — no splits -----------------------------------
    if (isPersonal) {
      final expense = await repo.addExpense(
        groupId: null,
        payerId: payerId,
        amount: amount,
        description: _descriptionCtrl.text.trim(),
        currency: _currency,
        splitType: SplitType.even,
        splits: [],
        category: _category,
        isIncome: _isIncome,
      );
      if (mounted) {
        setState(() => _isSubmitting = false);
        if (expense != null) {
          HapticUtils.success();
          ref.invalidate(walletBalanceProvider);
          ref.invalidate(personalExpensesProvider);
          ref.invalidate(recentExpensesProvider);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isIncome ? 'Income recorded' : 'Personal expense saved'),
              backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.9),
            ),
          );
          context.pop();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not save entry')),
          );
        }
      }
      return;
    }

    // -- Build split results --------------------------------------------------
    List<SplitResult> results;
    SplitType splitType;

    switch (_splitMode) {
      case SplitMode.even:
        results = SplitEngine.splitEven(
          total: amount,
          participantIds: _memberIds,
          payerId: payerId,
        );
        splitType = SplitType.even;
      case SplitMode.percentage:
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
      case SplitMode.shares:
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
      case SplitMode.manual:
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

          // Map splits to SplitInsert objects
          final splitsToStore = results.map((r) {
            return SplitInsert(userId: r.userId, universalUsdOwed: r.amountOwed);
          }).toList();
        debugPrint('[AddExpense] splits generated: ${splitsToStore.map((s) => '${s.userId}=${s.universalUsdOwed}').join(', ')}');
        final expense = await repo.addExpense(
      groupId: widget.groupId.isEmpty ? null : widget.groupId,
      payerId: payerId,
      amount: amount,
      description: _descriptionCtrl.text.trim(),
      currency: _currency,
      splitType: splitType,
      splits: splitsToStore,
      category: _category,
      isIncome: _isIncome,
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
          'Add expense · ${_step + 1}/$_effectiveTotalSteps',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          children: [
            if (widget.groupName.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Icon(Icons.group_outlined,
                        size: 14,
                        color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      widget.groupName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            _stepIndicator(theme),
            const SizedBox(height: 20),
            if (_step == 0) _buildStepAmount(theme),
          if (_step == 1 && widget.groupId.isNotEmpty) _buildStepSplit(theme),
          if ((_step == 1 && widget.groupId.isEmpty) || _step == 2) _buildStepDetails(theme),
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
                if (_step < _effectiveTotalSteps - 1)
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
                            width: 18,
                            height: 18,
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
            const SizedBox(height: 32),
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
      children: List.generate(_effectiveTotalSteps, (i) {
        final active = i == _step;
        final done = i < _step;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 4,
              decoration: BoxDecoration(
                color: active
                    ? _teal
                    : done
                        ? _teal.withValues(alpha: 0.4)
                        : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        );
      }),
    );
  }

  // ---------------------------------------------------------------------------
  // Step helpers
  // ---------------------------------------------------------------------------

  int get _effectiveTotalSteps => widget.groupId.isEmpty ? 2 : _totalSteps;

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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Amount & currency',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 16),

          // Amount field
          TextFormField(
            controller: _amountCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _teal,
            ),
            decoration: InputDecoration(
              labelText: 'Amount',
              labelStyle: const TextStyle(fontSize: 13),
              prefixIcon: _CurrencySymbolIcon(currency: _currency),
              filled: true,
              fillColor:
                  theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
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
          const SizedBox(height: 12),

          // Currency picker
          CurrencyPickerField(
            selected: _currency,
            onChanged: (code) {
              HapticUtils.selection();
              setState(() {
                _currency = code;
                _rateOverrideCtrl.clear();
              });
            },
          ),
          const SizedBox(height: 12),

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
            const SizedBox(height: 12),
            _RateDisplayRow(
              fromCurrency: _currency,
              toCurrency: base,
              rateAsync: rateAsync,
            ),
            const SizedBox(height: 8),
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

          // ── Income toggle (personal wallet mode only) ──────────────────
          if (widget.groupId.isEmpty) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _isIncome
                    ? const Color(0xFF22C55E).withValues(alpha: 0.10)
                    : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(12),
                border: _isIncome
                    ? Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.4))
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    _isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                    size: 18,
                    color: _isIncome ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mark as Income',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: _isIncome ? const Color(0xFF22C55E) : theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          _isIncome ? 'This entry adds to your wallet balance' : 'This entry subtracts from your wallet balance',
                          style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _isIncome,
                    onChanged: (v) {
                      HapticUtils.selection();
                      setState(() => _isIncome = v);
                    },
                    activeThumbColor: const Color(0xFF22C55E),
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
  // Step 2 – Split
  // ---------------------------------------------------------------------------

  Widget _buildStepSplit(ThemeData theme) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How to split',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 14),
          SegmentedButton<SplitMode>(
            segments: [
              ButtonSegment(
                value: SplitMode.even,
                label: Text('Even', style: const TextStyle(fontSize: 11)),
                icon: const Icon(Icons.equalizer, size: 14),
              ),
              ButtonSegment(
                value: SplitMode.percentage,
                label: Text('%', style: const TextStyle(fontSize: 11)),
                icon: const Icon(Icons.percent, size: 14),
              ),
              ButtonSegment(
                value: SplitMode.shares,
                label: Text('Shares', style: const TextStyle(fontSize: 11)),
                icon: const Icon(Icons.pie_chart_outline, size: 14),
              ),
              ButtonSegment(
                value: SplitMode.manual,
                label: Text('Manual', style: const TextStyle(fontSize: 11)),
                icon: const Icon(Icons.edit, size: 14),
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
            const SizedBox(height: 16),
            Text(
              _splitMode == SplitMode.percentage
                  ? 'Percentage per person (total = 100)'
                  : _splitMode == SplitMode.shares
                      ? 'Relative shares per person'
                      : 'Exact amount per person',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 8),
            ...List.generate(_memberIds.length, (i) {
              if (_customCtrl.length <= i) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: Text(
                        _memberNames.length > i
                            ? _memberNames[i]
                            : 'Member ${i + 1}',
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 90,
                      child: TextFormField(
                        controller: _customCtrl[i],
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        style: const TextStyle(fontSize: 13),
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
                            borderRadius: BorderRadius.circular(8),
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
            if (_splitMode == SplitMode.percentage) ...[
              const SizedBox(height: 8),
              _PercentageSumIndicator(controllers: _customCtrl),
            ],
            // Manual amount sum indicator
            if (_splitMode == SplitMode.manual) ...[
              const SizedBox(height: 8),
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
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _teal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.equalizer, color: _teal, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Split evenly among ${_memberIds.length} members',
                    style: const TextStyle(color: _teal, fontSize: 12),
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
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Details',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 16),
          // Category chips
          Text(
            'Category',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: kExpenseCategories.map((cat) {
              final selected = _category == cat;
              return FilterChip(
                label: Text(cat, style: const TextStyle(fontSize: 11)),
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
          const SizedBox(height: 16),
          if (_memberIds.length > 1) ...
            [
              Text(
                'Paid by',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: _memberIds.contains(_payerId) ? _payerId : null,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
                items: List.generate(_memberIds.length, (i) {
                  return DropdownMenuItem(
                    value: _memberIds[i],
                    child: Text(
                      _memberNames.length > i ? _memberNames[i] : _memberIds[i],
                      style: const TextStyle(fontSize: 13),
                    ),
                  );
                }),
                onChanged: (v) => setState(() => _payerId = v),
              ),
              const SizedBox(height: 16),
            ],
          TextFormField(
            controller: _descriptionCtrl,
            decoration: InputDecoration(
              labelText: 'Description (optional)',
              labelStyle: const TextStyle(fontSize: 13),
              prefixIcon: const Icon(Icons.notes_outlined),
              filled: true,
              fillColor:
                  theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
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

class CurrencyPickerField extends StatelessWidget {
  const CurrencyPickerField({
    super.key,
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
          builder: (_) => CurrencySearchSheet(selected: selected),
        );
        if (result != null) onChanged(result);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color:
              theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Text(entry['flag'] ?? '', style: const TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry['code']!,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: _teal,
                    ),
                  ),
                  Text(
                    entry['name']!,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.expand_more,
                color: theme.colorScheme.onSurfaceVariant, size: 18),
          ],
        ),
      ),
    );
  }
}

class CurrencySearchSheet extends StatefulWidget {
  const CurrencySearchSheet({super.key, required this.selected});
  final String selected;

  @override
  State<CurrencySearchSheet> createState() => _CurrencySearchSheetState();
}

class _CurrencySearchSheetState extends State<CurrencySearchSheet> {
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
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search currency…',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
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
                        style: const TextStyle(fontSize: 22)),
                    title: Text(
                      c['code']!,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: isSelected ? _teal : null,
                      ),
                    ),
                    subtitle: Text(
                      c['name']!,
                      style: const TextStyle(fontSize: 11),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: _teal.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.swap_horiz, color: _teal, size: 14),
          const SizedBox(width: 6),
          Text(
            '$fromAmount $fromCurrency  →  ≈ $toAmount $toCurrency',
            style: const TextStyle(
              color: _teal,
              fontWeight: FontWeight.w600,
              fontSize: 12,
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
        const Icon(Icons.bolt, color: _orange, size: 14),
        const SizedBox(width: 4),
        Text(
          rateStr,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isExact ? Icons.check_circle_outline : Icons.warning_amber_outlined,
            color: color,
            size: 13,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            isExact ? Icons.check_circle_outline : Icons.info_outline,
            color: color,
            size: 13,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 11,
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
            style: const TextStyle(fontSize: 12),
            decoration: InputDecoration(
              labelText: 'Manual rate (bank / cash)',
              hintText: '1 $fromCurrency = ? $toCurrency',
              labelStyle: const TextStyle(fontSize: 11),
              isDense: true,
              filled: true,
              fillColor:
                  theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        OutlinedButton(
          onPressed: onApply,
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: _teal),
            foregroundColor: _teal,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          ),
          child: const Text('Apply', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Dynamic currency symbol prefix icon
// ---------------------------------------------------------------------------
class _CurrencySymbolIcon extends StatelessWidget {
  const _CurrencySymbolIcon({required this.currency});
  final String currency;

  @override
  Widget build(BuildContext context) {
    final sym = currencySymbol(currency);
    // If symbol is longer than 2 chars (e.g. "GEL" → "₾" or the code itself),
    // shrink the font so it fits in the prefix icon area.
    final fontSize = sym.length > 2 ? 11.0 : 16.0;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Center(
        widthFactor: 1,
        child: Text(
          sym,
          style: TextStyle(
            color: _teal,
            fontWeight: FontWeight.w800,
            fontSize: fontSize,
          ),
        ),
      ),
    );
  }
}

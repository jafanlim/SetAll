import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:uuid/uuid.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/attachment_processor.dart';
import '../../../../core/utils/category_utils.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/utils/input_sanitizer.dart';
import '../../../../core/utils/split_engine.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/wallet_entry_model.dart';
import '../../../../data/repositories/setall_repository.dart';
import '../../../../domain/entities/expense.dart';

// Currency catalogue re-exported via setall_providers.dart → currencies.dart.
// kAllSupportedCurrencies / kMostUsedCurrencies / kMostUsedCurrencyCodes are
// all available through the setall_providers import above.
//
// Alias kept for backward compat within this file:
const kCurrencyList = kAllSupportedCurrencies;

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
    this.groupName = '',
    this.initialIsIncome = false,
    this.existingWalletEntry,
    this.initialCurrency,
  });

  final String groupId;
  final String groupName;
  final bool   initialIsIncome;
  final WalletEntryModel? existingWalletEntry;
  /// Pre-selected currency — set to the group's defaultCurrency when navigating
  /// from a group screen so new expenses default to the group currency.
  final String? initialCurrency;

  @override
  ConsumerState<AddExpenseScreen> createState() => _AddExpenseScreenState();
}

class _AddExpenseScreenState extends ConsumerState<AddExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl       = TextEditingController();
  final _descriptionCtrl  = TextEditingController();
  final _notesCtrl        = TextEditingController();
  final _rateOverrideCtrl = TextEditingController();
  int _step = 0;
  static const int _totalSteps = 3;

  String _currency = 'USD';
  String _category = 'General';
  SplitMode _splitMode = SplitMode.even;
  bool _isSubmitting = false;
  late bool _isIncome;
  DateTime _selectedDate = DateTime.now();
  String? _payerId;

  // Icon + color
  IconData _entryIcon  = Icons.category_outlined;
  Color    _entryColor = const Color(0xFF8B5CF6);

  final List<String> _attachmentPaths = [];

  final List<TextEditingController> _customCtrl = [];
  List<String> _memberIds = [];
  List<String> _memberNames = [];

  @override
  void initState() {
    super.initState();
    final existing = widget.existingWalletEntry;
    if (existing != null) {
      _isIncome = existing.isIncome;
      _amountCtrl.text       = existing.amount;
      _descriptionCtrl.text  = existing.description;
      _notesCtrl.text        = existing.notes ?? '';
      _currency              = existing.currency;
      _category              = existing.category;
      _entryColor = existing.iconColor != null
          ? Color(existing.iconColor!)
          : (_isIncome ? const Color(0xFF22C55E) : const Color(0xFF8B5CF6));
      _entryIcon = existing.iconCodepoint != null
          ? IconData(existing.iconCodepoint!, fontFamily: 'MaterialIcons')
          : (_isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded);
      if (existing.createdAt != null) {
        _selectedDate = DateTime.tryParse(existing.createdAt!) ?? DateTime.now();
      }
    } else {
      _isIncome   = widget.initialIsIncome;
      _entryColor = _isIncome ? const Color(0xFF22C55E) : const Color(0xFF8B5CF6);
      _entryIcon  = _isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded;
      if (widget.initialCurrency != null && widget.initialCurrency!.isNotEmpty) {
        _currency = widget.initialCurrency!;
      }
    }
    _loadMembers();
  }

  Future<void> _showIconPicker() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EntryIconColorPicker(
        selectedIcon:    _entryIcon,
        selectedColor:   _entryColor,
        onIconSelected:  (ic) => setState(() => _entryIcon  = ic),
        onColorSelected: (c)  => setState(() => _entryColor = c),
      ),
    );
  }

  Future<void> _loadMembers() async {
    final repo = ref.read(setAllRepositoryProvider);
    final uid = await repo.ensureUser();
    // wallet mode — no group, no members to load; skip the Supabase call
    // entirely to avoid sending '' as a UUID which Postgres rejects.
    final members = widget.groupId.isEmpty
        ? await Future.value(<dynamic>[])
        : await repo.getGroupMembers(widget.groupId);
    if (!mounted) return;

    var ids   = members.map((m) => m.id   as String).toList();
    var names = members.map((m) => m.name as String).toList();

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

    if (!mounted) return;
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

  Future<void> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final xFile = await picker.pickImage(source: source, imageQuality: 85);
    if (xFile == null || !mounted) return;
    setState(() => _attachmentPaths.add(xFile.path));
    HapticUtils.success();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      type: FileType.any,
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final path = result.files.first.path;
    if (path == null) return;
    if (!AttachmentProcessor.isAllowed(path)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('add_expense.unsupported_file'.tr()),
      ));
      return;
    }
    if (AttachmentProcessor.isTextFile(path)) {
      try {
        final content = await File(path).readAsString();
        setState(() => _notesCtrl.text = content);
        HapticUtils.success();
      } catch (_) {}
      return;
    }
    setState(() => _attachmentPaths.add(path));
    HapticUtils.success();
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descriptionCtrl.dispose();
    _notesCtrl.dispose();
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
        SnackBar(content: Text('add_expense.enter_valid_amount'.tr())),
      );
      return false;
    }
    if (d > Decimal.fromInt(10000000)) {
      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          content: Text('add_expense.amount_unusually_large'.tr()),
          leading: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF8C42)),
          actions: [
            TextButton(
              onPressed: () {
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                setState(() => _step++);
              },
              child: Text('common.continue_anyway'.tr()),
            ),
            TextButton(
              onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
              child: Text('common.cancel'.tr()),
            ),
          ],
        ),
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
        SnackBar(content: Text('add_expense.enter_valid_amount'.tr())),
      );
      return;
    }
    if (amount > Decimal.fromInt(10000000)) return;

    final repo = ref.read(setAllRepositoryProvider);
    final currentUid = await repo.ensureUser();
    final payerId = _payerId ?? currentUid;
    if (!mounted) return;
    if (payerId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('add_expense.could_not_get_user'.tr())),
        );
      }
      return;
    }

    final isPersonal = widget.groupId.isEmpty;

    if (!isPersonal && _memberIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('add_expense.no_members'.tr())),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    debugPrint('[AddExpense] _submit: payerId=$payerId currentUid=$currentUid memberIds=${_memberIds.length}: $_memberIds, splitMode=$_splitMode, amount=$amount');

    // -- Personal (wallet) mode — no splits -----------------------------------
    if (isPersonal) {
      final existing = widget.existingWalletEntry;
      final entryId = existing?.id ?? const Uuid().v4();
      final now = DateTime.now().toUtc().toIso8601String();

      // Compute USD equivalent for totals / sorting.
      final rateToUsd = await repo.resolveRateToUsd(_currency);
      final usdAmount = (amount * rateToUsd).round(scale: 6);

      final entry = WalletEntryModel(
        id:          entryId,
        userId:      payerId,
        amount:      amount.toString(),
        isIncome:    _isIncome,
        description: InputSanitizer.sanitize(_descriptionCtrl.text.trim()),
        currency:    _currency,
        category:    _category,
        iconCodepoint: _entryIcon.codePoint,
        iconColor:   _entryColor.toARGB32(),
        notes:       _notesCtrl.text.trim().isEmpty ? null : InputSanitizer.sanitize(_notesCtrl.text.trim()),
        createdAt:   existing?.createdAt ?? now,
        updatedAt:   now,
        universalUsdAmount: usdAmount.toString(),
      );
      await repo.upsertWalletEntry(entry);
      if (mounted) {
        setState(() => _isSubmitting = false);
        HapticUtils.success(); // HAPTIC-01: wallet creation — heavy confirms high-value action
        ref.invalidate(walletEntriesProvider);
        ref.invalidate(walletEntryTotalsProvider);
        ref.invalidate(recentExpensesProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_isIncome ? 'add_expense.income_recorded'.tr() : 'add_expense.expense_saved'.tr()),
            backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.9),
          ),
        );
        // For wallet (personal) entries, go directly to /wallet to clear
        // the WalletEntryTypeScreen from the navigation stack.
        context.go('/wallet');
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
              SnackBar(content: Text('add_expense.percentages_must_sum'.tr())),
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
              SnackBar(content: Text('add_expense.enter_share'.tr())),
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
                  'add_expense.amounts_must_sum'.tr(namedArgs: {'amount': amount.toString(), 'total': totalManual.toString()}),
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
      description: InputSanitizer.sanitize(_descriptionCtrl.text.trim()),
      currency: _currency,
      splitType: splitType,
      splits: splitsToStore,
      category: _category,
      isIncome: _isIncome,
      iconCodepoint: _entryIcon.codePoint,
      iconColor: _entryColor.toARGB32(),
      attachmentPaths: List.unmodifiable(_attachmentPaths),
      notes: _notesCtrl.text.trim().isEmpty ? null : InputSanitizer.sanitize(_notesCtrl.text.trim()),
    );


    if (mounted) {
      setState(() => _isSubmitting = false);
      if (expense != null) {
        HapticUtils.primaryTap(); // HAPTIC-01: expense saved — medium confirms data was committed
        ref.invalidate(balanceSummaryProvider);
        ref.invalidate(recentExpensesProvider);
        ref.invalidate(groupExpensesProvider(widget.groupId));
        ref.invalidate(groupBalanceSummaryProvider(widget.groupId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('add_expense.group_expense_saved'.tr()),
            backgroundColor: _teal.withValues(alpha: 0.9),
          ),
        );
        if (context.canPop()) {
          context.pop();
        } else {
          context.go('/');
        }
      } else {
        HapticUtils.lightTap();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('add_expense.could_not_save_expense'.tr())),
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
          '${_isIncome ? 'add_expense.title_income'.tr() : 'add_expense.title_expense'.tr()} · ${_step + 1}/$_effectiveTotalSteps',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            HapticUtils.lightTap();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Row(
          children: [
            if (_step > 0)
              TextButton.icon(
                onPressed: _prevStep,
                icon: const Icon(Icons.arrow_back),
                label: Text('add_expense.back'.tr()),
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
                label: Text('add_expense.next'.tr()),
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
                label: Text(_isSubmitting ? 'add_expense.saving'.tr() : (_isIncome ? 'add_expense.save_income'.tr() : 'add_expense.save_expense'.tr())),
              ),
          ],
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
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
            const SizedBox(height: 16),
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
            'add_expense.amount_currency'.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 16),

          // Amount field
          TextFormField(
            controller: _amountCtrl,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _teal,
            ),
            decoration: InputDecoration(
              labelText: 'add_expense.amount_label'.tr(),
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
            onChanged: (_) { HapticUtils.lightTap(); setState(() {}); },
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
              labelOverride: 'add_expense.manual_rate_optional'.tr(),
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

          // ── Date picker ───────────────────────────────────────────────
          const SizedBox(height: 12),
          _DatePickerField(
            selectedDate: _selectedDate,
            onDateChanged: (d) => setState(() => _selectedDate = d),
          ),

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
            'add_expense.how_to_split'.tr(),
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
                label: Text('add_expense.split_even'.tr(), style: const TextStyle(fontSize: 11)),
                icon: const Icon(Icons.equalizer, size: 14),
              ),
              ButtonSegment(
                value: SplitMode.percentage,
                label: Text('add_expense.split_percent'.tr(), style: const TextStyle(fontSize: 11)),
                icon: const Icon(Icons.percent, size: 14),
              ),
              ButtonSegment(
                value: SplitMode.shares,
                label: Text('add_expense.split_shares'.tr(), style: const TextStyle(fontSize: 11)),
                icon: const Icon(Icons.pie_chart_outline, size: 14),
              ),
              ButtonSegment(
                value: SplitMode.manual,
                label: Text('add_expense.split_manual'.tr(), style: const TextStyle(fontSize: 11)),
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
                  ? 'add_expense.split_hint_percent'.tr()
                  : _splitMode == SplitMode.shares
                      ? 'add_expense.split_hint_shares'.tr()
                      : 'add_expense.split_hint_manual'.tr(),
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
                            : 'add_expense.member_n'.tr(namedArgs: {'n': '${i + 1}'}),
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
                    'add_expense.split_evenly_members'.tr(namedArgs: {'count': '${_memberIds.length}'}),
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

  Future<void> _showCreateCategoryDialog(ThemeData theme) async {
    final ctrl = TextEditingController();
    String catType = _isIncome ? 'income' : 'expense';
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('add_expense.category_label'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'add_expense.category_label'.tr(),
                  hintText: 'e.g. Gym, Salary…',
                ),
              ),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'expense', label: Text('add_expense.title_expense'.tr(), style: const TextStyle(fontSize: 12))),
                  ButtonSegment(value: 'income',  label: Text('add_expense.title_income'.tr(),  style: const TextStyle(fontSize: 12))),
                ],
                selected: {catType},
                onSelectionChanged: (s) => setDlg(() => catType = s.first),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: Text('common.cancel'.tr())),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
              onPressed: () {
                final name = ctrl.text.trim();
                if (name.isNotEmpty) Navigator.of(ctx).pop({'name': name, 'type': catType});
              },
              child: Text('common.save'.tr()),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (result == null || !mounted) return;
    final repo = ref.read(setAllRepositoryProvider);
    final ok = await repo.createUserCategory(name: result['name']!, type: result['type']!);
    if (!mounted) return;
    if (ok) {
      HapticUtils.success();
      ref.invalidate(userCategoriesProvider);
      setState(() => _category = result['name']!);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('add_expense.could_not_save'.tr())),
      );
    }
  }

  Widget _buildStepDetails(ThemeData theme) {
    final userCatsAsync = ref.watch(userCategoriesProvider);
    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'add_expense.details'.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 15,
            ),
          ),
          const SizedBox(height: 16),

          // ── Icon & Colour ─────────────────────────────────────────────
          Row(
            children: [
              GestureDetector(
                onTap: _showIconPicker,
                child: Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color: _entryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                        color: _entryColor.withValues(alpha: 0.4)),
                  ),
                  child: Icon(_entryIcon, color: _entryColor, size: 24),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('add_expense.icon_colour'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        )),
                    const SizedBox(height: 2),
                    TextButton.icon(
                      onPressed: _showIconPicker,
                      icon: const Icon(Icons.palette_outlined, size: 14),
                      label: Text('add_expense.change_icon'.tr(),
                          style: const TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: _teal,
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Category section header with "+" button
          Row(
            children: [
              Text(
                'add_expense.category_label'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              InkWell(
                onTap: () => _showCreateCategoryDialog(theme),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.add, size: 14, color: _teal),
                      const SizedBox(width: 4),
                      Text('add_expense.new_category_btn'.tr(), style: const TextStyle(color: _teal, fontSize: 11, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Standard categories
          Text(
            'add_expense.standard_categories'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: kExpenseCategories.map((cat) {
              final selected = _category == cat;
              return FilterChip(
                label: Text(categoryTr(cat), style: const TextStyle(fontSize: 11)),
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
          // User categories
          userCatsAsync.when(
            data: (cats) {
              if (cats.isEmpty) return const SizedBox.shrink();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 12),
                  Text(
                    'add_expense.your_categories'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: cats.map((cat) {
                      final name = cat['name'] ?? '';
                      final selected = _category == name;
                      final isIncomeCat = cat['type'] == 'income';
                      return FilterChip(
                        avatar: Icon(
                          isIncomeCat ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                          size: 12,
                          color: selected
                              ? (isIncomeCat ? const Color(0xFF22C55E) : _teal)
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        label: Text(name, style: const TextStyle(fontSize: 11)),
                        selected: selected,
                        selectedColor: (isIncomeCat
                                ? const Color(0xFF22C55E)
                                : _teal)
                            .withValues(alpha: 0.15),
                        checkmarkColor: isIncomeCat ? const Color(0xFF22C55E) : _teal,
                        labelStyle: TextStyle(
                          color: selected
                              ? (isIncomeCat ? const Color(0xFF22C55E) : _teal)
                              : null,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                        onSelected: (_) {
                          HapticUtils.selection();
                          setState(() {
                            _category = name;
                            if (isIncomeCat) _isIncome = true;
                          });
                        },
                      );
                    }).toList(),
                  ),
                ],
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (e, s) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 16),
          if (_memberIds.length > 1) ...
            [
              Text(
                'add_expense.payer_label'.tr(),
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
              labelText: 'add_expense.description_label'.tr(),
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
          const SizedBox(height: 16),

          // ── Attachments ─────────────────────────────────────────────────
          Row(
            children: [
              Text(
                'common.attachments'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              const Spacer(),
              if (!kIsWeb && (Platform.isIOS || Platform.isAndroid)) ...[
                AttachButton(
                  icon: Icons.photo_camera_outlined,
                  label: 'common.camera'.tr(),
                  onTap: () => _pickImage(ImageSource.camera),
                ),
                const SizedBox(width: 8),
              ],
              AttachButton(
                icon: Icons.photo_library_outlined,
                label: 'common.gallery'.tr(),
                onTap: () => _pickImage(ImageSource.gallery),
              ),
              const SizedBox(width: 8),
              AttachButton(
                icon: Icons.attach_file_outlined,
                label: 'common.file'.tr(),
                onTap: _pickFile,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Notes ───────────────────────────────────────────────────────
          TextFormField(
            controller: _notesCtrl,
            decoration: InputDecoration(
              labelText: 'add_expense.notes_label'.tr(),
              hintText: 'Additional details, or import a .txt / .md file above',
              prefixIcon: const Icon(Icons.notes_outlined),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            maxLines: 3,
            minLines: 1,
          ),

          if (_attachmentPaths.isNotEmpty) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 80,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _attachmentPaths.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (_, i) {
                  final path = _attachmentPaths[i];
                  final isLocalPath = path.startsWith('/') || path.contains('\\');
                  final isImage = isLocalPath && (path.endsWith('.jpg') ||
                      path.endsWith('.jpeg') ||
                      path.endsWith('.png') ||
                      path.endsWith('.webp'));
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: isImage
                            ? Image.file(
                                File(path),
                                width: 80, height: 80,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 80, height: 80,
                                color: theme.colorScheme.surfaceContainerHighest,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.insert_drive_file_outlined, size: 28),
                                    const SizedBox(height: 4),
                                    Text(
                                      path.split('.').last.toUpperCase(),
                                      style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      Positioned(
                        top: 2, right: 2,
                        child: GestureDetector(
                          onTap: () => setState(() => _attachmentPaths.removeAt(i)),
                          child: Container(
                            width: 20, height: 20,
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close, size: 12, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
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

// ---------------------------------------------------------------------------
// Advanced Currency Search Sheet
// Ordering: Default → Recently Used → Majors → A–Z
// Features: search bar + vertical A–Z alphabet strip for fast scrolling
// ---------------------------------------------------------------------------

/// Persistent store for recently used currency codes (in-memory for session).
final _recentlyUsed = <String>[];

class CurrencySearchSheet extends StatefulWidget {
  const CurrencySearchSheet({
    super.key,
    required this.selected,
    this.defaultCurrency,
  });
  final String selected;
  final String? defaultCurrency;

  @override
  State<CurrencySearchSheet> createState() => _CurrencySearchSheetState();
}

class _CurrencySearchSheetState extends State<CurrencySearchSheet> {
  String _query = '';
  final _listCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    // Ensure the currently selected currency always appears in "Recently Used"
    // so it is visible at the top even before the user picks anything new.
    final sel = widget.selected;
    if (sel.isNotEmpty && !_recentlyUsed.contains(sel)) {
      _recentlyUsed.insert(0, sel);
      if (_recentlyUsed.length > 5) _recentlyUsed.removeLast();
    }
  }

  static const _kHeader   = '__HEADER__';
  static const _alphabet  = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';

  // Build ordered list: Default → Recently Used → Majors → A-Z
  // Each section preceded by a header sentinel.
  List<Map<String, String>> get _orderedItems {
    final defaultCode = widget.defaultCurrency ?? widget.selected;

    // 1. Default currency (single entry)
    final defaultEntry = kCurrencyList.where((c) => c['code'] == defaultCode).toList();

    // 2. Recently used (exclude only if it is the explicit default entry shown above)
    final explicitDefault = widget.defaultCurrency;
    final recentEntries = _recentlyUsed
        .where((code) => code != (explicitDefault ?? ''))
        .map((code) => kCurrencyList.firstWhere(
              (c) => c['code'] == code,
              orElse: () => <String, String>{},
            ))
        .where((c) => c.isNotEmpty)
        .toList();

    // 3. Majors (excluding default + recent)
    final majorEntries = kCurrencyList
        .where((c) =>
            kMostUsedCurrencyCodes.contains(c['code']) &&
            c['code'] != defaultCode &&
            !_recentlyUsed.contains(c['code']))
        .toList();

    // 4. A–Z (excluding already listed)
    final listed = {defaultCode, ..._recentlyUsed, ...kMostUsedCurrencyCodes};
    final azEntries = kCurrencyList
        .where((c) => !listed.contains(c['code']))
        .toList()
      ..sort((a, b) => (a['name'] ?? '').compareTo(b['name'] ?? ''));

    return [
      if (defaultEntry.isNotEmpty) ...[
        {'code': _kHeader, 'name': 'Default Currency', 'flag': ''},
        ...defaultEntry,
      ],
      if (recentEntries.isNotEmpty) ...[
        {'code': _kHeader, 'name': 'Recently Used', 'flag': ''},
        ...recentEntries,
      ],
      if (majorEntries.isNotEmpty) ...[
        {'code': _kHeader, 'name': 'Major Currencies', 'flag': ''},
        ...majorEntries,
      ],
      {'code': _kHeader, 'name': 'All Currencies A–Z', 'flag': ''},
      ...azEntries,
    ];
  }

  List<Map<String, String>> get _items {
    if (_query.isNotEmpty) {
      final q = _query.toUpperCase();
      return kCurrencyList
          .where((c) =>
              c['code']!.toUpperCase().contains(q) ||
              c['name']!.toUpperCase().contains(q))
          .toList()
        ..sort((a, b) {
          // Exact code match first
          final aExact = a['code']!.toUpperCase() == q;
          final bExact = b['code']!.toUpperCase() == q;
          if (aExact && !bExact) return -1;
          if (!aExact && bExact) return 1;
          return (a['name'] ?? '').compareTo(b['name'] ?? '');
        });
    }
    return _orderedItems;
  }

  /// Map from first letter → index in the full _orderedItems list (A-Z section only).
  Map<String, int> get _letterIndex {
    final items = _orderedItems;
    final map = <String, int>{};
    for (var i = 0; i < items.length; i++) {
      final c = items[i];
      if (c['code'] == _kHeader) continue;
      final first = (c['name'] ?? c['code'] ?? '').toUpperCase();
      if (first.isEmpty) continue;
      final letter = first[0];
      if (!map.containsKey(letter)) map[letter] = i;
    }
    return map;
  }

  void _scrollToLetter(String letter) {
    final index = _letterIndex[letter];
    if (index == null) return;
    HapticUtils.selection();
    _listCtrl.animateTo(
      // each ListTile ≈ 60px, each header ≈ 36px — approximate
      index * 58.0,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void dispose() {
    _listCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _items;
    final isSearching = _query.isNotEmpty;

    return DraggableScrollableSheet(
      initialChildSize: 0.80,
      maxChildSize: 0.95,
      minChildSize: 0.4,
      builder: (_, sheetCtrl) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Search currency…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () => setState(() => _query = ''),
                        )
                      : null,
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

            // List + A-Z strip
            Expanded(
              child: Row(
                children: [
                  // ── Currency list ────────────────────────────────────────
                  Expanded(
                    child: ListView.builder(
                      controller: isSearching ? sheetCtrl : _listCtrl,
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final c = items[i];
                        if (c['code'] == _kHeader) {
                          return Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Text(
                              c['name']!,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                fontSize: 10,
                              ),
                            ),
                          );
                        }
                        final isSelected = c['code'] == widget.selected;
                        return ListTile(
                          dense: true,
                          leading: Text(
                            c['flag'] ?? '',
                            style: const TextStyle(fontSize: 22),
                          ),
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
                              ? const Icon(Icons.check_circle, color: _teal, size: 18)
                              : null,
                          onTap: () {
                            HapticUtils.selection();
                            // Track recently used
                            _recentlyUsed
                              ..remove(c['code'])
                              ..insert(0, c['code']!);
                            if (_recentlyUsed.length > 5) {
                              _recentlyUsed.removeLast();
                            }
                            Navigator.pop(context, c['code']);
                          },
                        );
                      },
                    ),
                  ),

                  // ── A-Z alphabet strip (hidden when searching) ───────────
                  if (!isSearching)
                    ScrollConfiguration(
                      // Disable native scrollbars + prevent the strip from
                      // swallowing macOS trackpad / mouse-wheel events.
                      behavior: ScrollConfiguration.of(context).copyWith(
                        scrollbars: false,
                        physics: const NeverScrollableScrollPhysics(),
                      ),
                      child: SizedBox(
                        width: 24,
                        child: ListView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _alphabet.length,
                          itemBuilder: (_, i) {
                            final letter = _alphabet[i];
                            final hasEntries = _letterIndex.containsKey(letter);
                            return GestureDetector(
                              onTap: hasEntries
                                  ? () => _scrollToLetter(letter)
                                  : null,
                              child: SizedBox(
                                height: 20,
                                child: Center(
                                  child: Text(
                                    letter,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: hasEntries
                                          ? _teal
                                          : theme.colorScheme.onSurfaceVariant
                                              .withValues(alpha: 0.3),
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                ],
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
        ? 'add_expense.manual_enter_total'.tr()
        : isExact
            ? 'add_expense.manual_sum_matches'.tr(namedArgs: {'currency': currency, 'sum': sum.toString()})
            : sum < total
                ? 'add_expense.manual_sum_remaining'.tr(namedArgs: {'currency': currency, 'sum': sum.toString(), 'diff': (total - sum).toString()})
                : 'add_expense.manual_sum_over'.tr(namedArgs: {'currency': currency, 'sum': sum.toString(), 'diff': (sum - total).toString()});

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
    this.labelOverride,
  });

  final TextEditingController rateCtrl;
  final String fromCurrency;
  final String toCurrency;
  final VoidCallback onApply;
  final String? labelOverride;

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
              labelText: labelOverride ?? 'add_expense.manual_rate_label'.tr(),
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
          child: Text('add_expense.apply'.tr(), style: const TextStyle(fontSize: 12)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Dynamic currency symbol prefix icon
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Date Picker Field
// ---------------------------------------------------------------------------
class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.selectedDate,
    required this.onDateChanged,
  });

  final DateTime selectedDate;
  final ValueChanged<DateTime> onDateChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = _fmt(selectedDate);
    final isToday = _isToday(selectedDate);
    return InkWell(
      onTap: () async {
        HapticUtils.lightTap();
        final picked = await showDatePicker(
          context: context,
          initialDate: selectedDate,
          firstDate: DateTime(2000),
          lastDate: DateTime.now().add(const Duration(days: 1)),
          builder: (ctx, child) => Theme(
            data: Theme.of(ctx).copyWith(
              colorScheme: Theme.of(ctx).colorScheme.copyWith(
                primary: _teal,
                onPrimary: Colors.black,
              ),
            ),
            child: child!,
          ),
        );
        if (picked != null) onDateChanged(picked);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_outlined,
              size: 16,
              color: isToday ? _teal : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                isToday ? '${'common.today_prefix'.tr()} · $label' : label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isToday ? _teal : theme.colorScheme.onSurface,
                ),
              ),
            ),
            Icon(Icons.expand_more, size: 18, color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  static String _fmt(DateTime dt) {
    const months = [
      'Jan','Feb','Mar','Apr','May','Jun',
      'Jul','Aug','Sep','Oct','Nov','Dec'
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  static bool _isToday(DateTime dt) {
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }
}

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

// ---------------------------------------------------------------------------
// Entry icon + color catalogue (shared with AddExpenseScreen picker)
// ---------------------------------------------------------------------------
const List<IconData> _kAddEntryIcons = [
  Icons.category_outlined, Icons.restaurant_outlined, Icons.directions_car_outlined,
  Icons.movie_outlined, Icons.receipt_long_outlined, Icons.shopping_bag_outlined,
  Icons.flight_outlined, Icons.local_cafe_outlined, Icons.fitness_center_outlined,
  Icons.medical_services_outlined, Icons.school_outlined, Icons.home_outlined,
  Icons.pets_outlined, Icons.sports_esports_outlined, Icons.music_note_outlined,
  Icons.attach_money, Icons.savings_outlined, Icons.card_giftcard_outlined,
  Icons.arrow_downward_rounded, Icons.arrow_upward_rounded,
];

const List<Color> _kAddEntryColors = [
  Color(0xFF8B5CF6), Color(0xFF22C55E), Color(0xFF00D9B0), Color(0xFFEF4444),
  Color(0xFF3B82F6), Color(0xFFF59E0B), Color(0xFFEC4899), Color(0xFF06B6D4),
  Color(0xFFA855F7), Color(0xFFF97316), Color(0xFF10B981), Color(0xFF6366F1),
];

// ---------------------------------------------------------------------------
// Icon + Color picker bottom sheet (used by AddExpenseScreen)
// ---------------------------------------------------------------------------
class _EntryIconColorPicker extends StatefulWidget {
  const _EntryIconColorPicker({
    required this.selectedIcon,
    required this.selectedColor,
    required this.onIconSelected,
    required this.onColorSelected,
  });

  final IconData  selectedIcon;
  final Color     selectedColor;
  final ValueChanged<IconData> onIconSelected;
  final ValueChanged<Color>    onColorSelected;

  @override
  State<_EntryIconColorPicker> createState() => _EntryIconColorPickerState();
}

class _EntryIconColorPickerState extends State<_EntryIconColorPicker> {
  late IconData _icon;
  late Color    _color;

  @override
  void initState() {
    super.initState();
    _icon  = widget.selectedIcon;
    _color = widget.selectedColor;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  color: _color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: _color.withValues(alpha: 0.5), width: 2),
                ),
                child: Icon(_icon, color: _color, size: 30),
              ),
            ),
            const SizedBox(height: 20),
            Text('add_expense.colour_label'.tr(), style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700, fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            )),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10, runSpacing: 10,
              children: _kAddEntryColors.map((c) {
                final sel = _color.toARGB32() == c.toARGB32();
                return GestureDetector(
                  onTap: () {
                    setState(() => _color = c);
                    widget.onColorSelected(c);
                  },
                  child: Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: sel ? Border.all(color: Colors.white, width: 3) : null,
                      boxShadow: sel
                          ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 6)]
                          : null,
                    ),
                    child: sel ? const Icon(Icons.check, size: 16, color: Colors.white) : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            Text('add_expense.icon_label'.tr(), style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700, fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
            )),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10, runSpacing: 10,
              children: _kAddEntryIcons.map((ic) {
                final sel = _icon == ic;
                return GestureDetector(
                  onTap: () {
                    setState(() => _icon = ic);
                    widget.onIconSelected(ic);
                  },
                  child: Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: sel
                          ? _color.withValues(alpha: 0.2)
                          : theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      border: sel ? Border.all(color: _color, width: 2) : null,
                    ),
                    child: Icon(ic,
                      size: 20,
                      color: sel ? _color : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Done', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Attachment button
// ---------------------------------------------------------------------------
class AttachButton extends StatelessWidget {
  const AttachButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData    icon;
  final String      label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _teal.withValues(alpha: 0.25),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: _teal),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _teal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

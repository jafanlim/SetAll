import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import '../../../../core/providers/setall_providers.dart';
import '../../../../core/services/date_format_service.dart';
import '../../../../core/utils/attachment_processor.dart';
import '../../../../core/utils/category_utils.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/utils/input_sanitizer.dart';
import '../../../../core/utils/split_engine.dart';
import '../../../../data/models/expense_model.dart';
import '../../../../data/models/profile_model.dart';
import '../../../../data/models/split_model.dart';
import '../../../../data/repositories/setall_repository.dart';
import '../../../../domain/entities/expense.dart';
import 'add_expense_screen.dart' show CurrencyPickerField, AttachButton;

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

const _teal = Color(0xFF00D9B0);

// ---------------------------------------------------------------------------
// Entry icon + color catalogue
// ---------------------------------------------------------------------------
const List<IconData> _kEntryIcons = [
  Icons.category_outlined, Icons.restaurant_outlined, Icons.directions_car_outlined,
  Icons.movie_outlined, Icons.receipt_long_outlined, Icons.shopping_bag_outlined,
  Icons.flight_outlined, Icons.local_cafe_outlined, Icons.fitness_center_outlined,
  Icons.medical_services_outlined, Icons.school_outlined, Icons.home_outlined,
  Icons.pets_outlined, Icons.sports_esports_outlined, Icons.music_note_outlined,
  Icons.attach_money, Icons.savings_outlined, Icons.card_giftcard_outlined,
];

const List<Color> _kEntryColors = [
  Color(0xFF8B5CF6), Color(0xFF22C55E), Color(0xFF00D9B0), Color(0xFFEF4444),
  Color(0xFF3B82F6), Color(0xFFF59E0B), Color(0xFFEC4899), Color(0xFF06B6D4),
  Color(0xFFA855F7), Color(0xFFF97316), Color(0xFF10B981), Color(0xFF6366F1),
];

class _EditExpenseScreenState extends ConsumerState<EditExpenseScreen> {
  final _formKey             = GlobalKey<FormState>();
  final _amountController      = TextEditingController();
  final _descriptionController = TextEditingController();
  final _notesController       = TextEditingController();

  String    _currency    = 'USD';
  String    _category    = 'General';
  SplitMode _splitMode   = SplitMode.even;
  bool      _isLoading   = true;
  bool      _isSubmitting = false;
  ExpenseModel?        _expense;
  List<ProfileModel>   _members = [];
  String?              _payerId;

  // Date + time
  DateTime  _entryDate   = DateTime.now();

  // Icon + color
  IconData  _entryIcon   = Icons.category_outlined;
  Color     _entryColor  = const Color(0xFF8B5CF6);

  // Attachments
  final List<String> _attachmentPaths = [];

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
    _notesController.dispose();
    for (final c in _customCtrl.values) { c.dispose(); }
    super.dispose();
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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Unsupported file type. Allowed: images, PDF, TXT, MD.'),
      ));
      return;
    }
    if (AttachmentProcessor.isTextFile(path)) {
      try {
        final content = await File(path).readAsString();
        setState(() => _notesController.text = content);
        HapticUtils.success();
      } catch (_) {}
      return;
    }
    setState(() => _attachmentPaths.add(path));
    HapticUtils.success();
  }

  Future<void> _pickDateTime() async {
    HapticUtils.lightTap();
    final date = await showDatePicker(
      context: context,
      initialDate: _entryDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
            primary: _teal, onPrimary: Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_entryDate),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: Theme.of(ctx).colorScheme.copyWith(
            primary: _teal, onPrimary: Colors.black,
          ),
        ),
        child: child!,
      ),
    );
    if (!mounted) return;
    setState(() {
      _entryDate = DateTime(
        date.year, date.month, date.day,
        time?.hour ?? _entryDate.hour,
        time?.minute ?? _entryDate.minute,
      );
    });
  }

  Future<void> _showIconPicker() async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _IconColorPicker(
        selectedIcon:  _entryIcon,
        selectedColor: _entryColor,
        onIconSelected:  (ic) => setState(() => _entryIcon  = ic),
        onColorSelected: (c)  => setState(() => _entryColor = c),
      ),
    );
  }


  Future<void> _load() async {
    final repo       = ref.read(setAllRepositoryProvider);
    final expense    = await repo.getExpense(widget.expenseId);
    final splits     = await repo.getSplitsForExpense(widget.expenseId);
    final currentUid = await repo.ensureUser();

    // Wallet entries have no groupId — skip getGroupMembers entirely (avoids
    // Supabase calls with empty group_id which hang on Windows without timeout).
    List<ProfileModel> members = [];
    if (widget.groupId.isNotEmpty) {
      members = await repo.getGroupMembers(widget.groupId);
    }

    // Wallet entry — no group, so use the current user as sole member.
    if (members.isEmpty && currentUid != null) {
      final profile = await repo.getCurrentUserProfile();
      if (profile != null) members = [profile];
    }

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
          : expense.splitType == SplitType.parts
              ? SplitMode.shares
              : SplitMode.manual;
      _payerId   = expense.payerId.isNotEmpty ? expense.payerId : currentUid;
      if (expense.createdAt != null) {
        _entryDate = DateTime.tryParse(expense.createdAt!)?.toLocal() ?? DateTime.now();
      }
      if (expense.iconCodepoint != null) {
        _entryIcon = IconData(expense.iconCodepoint!, fontFamily: 'MaterialIcons');
      }
      if (expense.iconColor != null) {
        _entryColor = Color(expense.iconColor!);
      }
      if (expense.attachmentUrls != null && expense.attachmentUrls!.isNotEmpty) {
        _attachmentPaths.addAll(expense.attachmentUrls!);
      }
      if (expense.notes != null && expense.notes!.isNotEmpty) {
        _notesController.text = expense.notes!;
      }

      // Pre-fill custom controllers based on split mode.
      final rate     = Decimal.tryParse(expense.exchangeRateApplied ?? '') ?? Decimal.one;
      final totalUsd = splits.fold<Decimal>(Decimal.zero,
          (acc, s) => acc + (Decimal.tryParse(s.universalUsdOwed) ?? Decimal.zero));
      for (final m in members) {
        SplitModel? split;
        try { split = splits.firstWhere((s) => s.userId == m.id); } catch (_) {}
        String initial = '';
        if (split != null) {
          final usdAmt = Decimal.tryParse(split.universalUsdOwed) ?? Decimal.zero;
          switch (_splitMode) {
            case SplitMode.percentage:
              // Percentage of total based on USD ratio.
              if (totalUsd > Decimal.zero) {
                initial = ((usdAmt / totalUsd).toDecimal(scaleOnInfinitePrecision: 4)
                    * Decimal.fromInt(100)).round(scale: 2).toString();
              }
            case SplitMode.shares:
              // Original weights are not stored; default every member to 1.
              initial = '1';
            case SplitMode.manual:
              // Use stored entry-currency amount when available, else reverse-convert.
              if (split.entryAmountOwed != null) {
                initial = Decimal.parse(split.entryAmountOwed!)
                    .toStringAsFixed(2);
              } else if (rate > Decimal.zero) {
                initial = (usdAmt / rate)
                    .toDecimal(scaleOnInfinitePrecision: 2)
                    .round(scale: 2)
                    .toString();
              } else {
                initial = split.universalUsdOwed;
              }
            case SplitMode.even:
              initial = ''; // not shown
          }
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
    if (amount > Decimal.fromInt(10000000)) {
      ScaffoldMessenger.of(context).showMaterialBanner(
        MaterialBanner(
          content: const Text('Amount is unusually large (>10,000,000). Are you sure?'),
          leading: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF8C42)),
          actions: [
            TextButton(
              onPressed: () async {
                ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
                await _submitConfirmed(amount);
              },
              child: const Text('Continue'),
            ),
            TextButton(
              onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
              child: const Text('Cancel'),
            ),
          ],
        ),
      );
      return;
    }
    await _submitConfirmed(amount);
  }

  Future<void> _submitConfirmed(Decimal amount) async {
    final repo       = ref.read(setAllRepositoryProvider);
    final currentUid = await repo.ensureUser();
    final payerId    = _payerId ?? currentUid;
    if (payerId == null) {
      if (mounted) { ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Could not get user. Try again.'))); }
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
          if (mounted) { ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Percentages must sum to 100'))); }
          return;
        }
        results   = SplitEngine.splitCustom(total: amount, participantIds: participantIds, weights: percents);
        splitType = SplitType.parts;
      case SplitMode.shares:
        final shares = participantIds
            .map((id) => Decimal.tryParse(_customCtrl[id]?.text.trim() ?? '') ?? Decimal.zero)
            .toList();
        if (shares.every((s) => s <= Decimal.zero)) {
          if (mounted) { ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Enter at least one share'))); }
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
          if (mounted) { ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('add_expense.amounts_must_sum'.tr(namedArgs: {'amount': amount.toString(), 'total': totalManual.toString()})))); }
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
      expenseId:      widget.expenseId,
      groupId:        widget.groupId,
      payerId:        payerId,
      amount:         amount,
      description:    InputSanitizer.sanitize(_descriptionController.text.trim()),
      currency:       _currency,
      splitType:      splitType,
      splits:         splits,
      category:       _category,
      isIncome:       _expense?.isIncome ?? false,
      iconCodepoint:  _entryIcon.codePoint,
      iconColor:      _entryColor.toARGB32(),
      attachmentPaths: List.unmodifiable(_attachmentPaths),
      notes: _notesController.text.trim().isEmpty ? null : InputSanitizer.sanitize(_notesController.text.trim()),
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (updated != null) {
        ref.invalidate(balanceSummaryProvider);
        ref.invalidate(recentExpensesProvider);
        ref.invalidate(groupExpensesProvider(widget.groupId));
        ref.invalidate(groupBalanceSummaryProvider(widget.groupId));
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('edit_expense.expense_updated'.tr())));
        context.pop();
      } else {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('edit_expense.could_not_update'.tr())));
      }
    }
  }

  // ── Payer selector ──────────────────────────────────────────────────────
  List<Widget> _buildPayerSection(ThemeData theme) {
    return [
      Row(children: [
        Text('add_expense.payer_label'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
      ]),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _members.map((m) {
            final selected = _payerId == m.id;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(m.name, style: const TextStyle(fontSize: 12)),
                selected: selected,
                selectedColor: _teal.withValues(alpha: 0.18),
                checkmarkColor: _teal,
                labelStyle: TextStyle(
                  color: selected ? _teal : null,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.normal,
                ),
                onSelected: (_) => setState(() => _payerId = m.id),
              ),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  // ── Split mode + per-member inputs ──────────────────────────────────────
  List<Widget> _buildSplitSection(ThemeData theme) {
    final modes = [
      (SplitMode.even,       'add_expense.split_even'.tr()),
      (SplitMode.shares,     'add_expense.split_shares'.tr()),
      (SplitMode.percentage, 'add_expense.split_percent'.tr()),
      (SplitMode.manual,     'add_expense.split_manual'.tr()),
    ];
    final suffix = _splitMode == SplitMode.percentage
        ? '%'
        : _splitMode == SplitMode.shares
            ? '×'
            : _currency;

    return [
      Row(children: [
        Text('add_expense.split_label'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
      ]),
      const SizedBox(height: 8),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: modes.map((entry) {
            final (mode, label) = entry;
            final sel = _splitMode == mode;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(label, style: const TextStyle(fontSize: 12)),
                selected: sel,
                selectedColor: _teal.withValues(alpha: 0.18),
                checkmarkColor: _teal,
                labelStyle: TextStyle(
                  color: sel ? _teal : null,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.normal,
                ),
                onSelected: (_) => setState(() {
                  _splitMode = mode;
                  for (final c in _customCtrl.values) { c.clear(); }
                }),
              ),
            );
          }).toList(),
        ),
      ),
      if (_splitMode != SplitMode.even) ...[
        const SizedBox(height: 12),
        ..._members.map((m) {
          _customCtrl.putIfAbsent(m.id, TextEditingController.new);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: _teal.withValues(alpha: 0.15),
                  child: Text(
                    m.name.isNotEmpty ? m.name[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 11, color: _teal,
                        fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(m.name,
                      style: theme.textTheme.bodyMedium?.copyWith(fontSize: 13)),
                ),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: _customCtrl[m.id],
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    decoration: InputDecoration(
                      suffixText: suffix,
                      suffixStyle: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant),
                      isDense: true,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 8),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
      const SizedBox(height: 4),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text('edit_expense.title'.tr())),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_expense == null) {
      return Scaffold(
        appBar: AppBar(title: Text('edit_expense.title'.tr())),
        body: Center(child: Text('edit_expense.not_found'.tr())),
      );
    }

    final userCatsAsync = ref.watch(userCategoriesProvider);
    final dateLabel = DateFormatService.instance.formatWithTime(_entryDate);
    final isToday = () {
      final now = DateTime.now();
      return _entryDate.year == now.year &&
          _entryDate.month == now.month &&
          _entryDate.day == now.day;
    }();

    return Scaffold(
      appBar: AppBar(
        title: Text('edit_expense.title'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
            if (widget.groupName.isNotEmpty && widget.groupName != 'Wallet') ...[
              Text(
                widget.groupName,
                style: theme.textTheme.titleMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
            ],

            // ── Icon / Avatar + Color ──────────────────────────────────────
            Row(
              children: [
                GestureDetector(
                  onTap: _showIconPicker,
                  child: Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: _entryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _entryColor.withValues(alpha: 0.4)),
                    ),
                    child: Icon(_entryIcon, color: _entryColor, size: 26),
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
                            fontSize: 10, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
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

            // ── Date & Time ────────────────────────────────────────────
            InkWell(
              onTap: _pickDateTime,
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
                        isToday ? '${'common.today_prefix'.tr()} · $dateLabel' : dateLabel,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isToday ? _teal : theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                    Icon(Icons.expand_more, size: 18,
                        color: theme.colorScheme.onSurfaceVariant),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ── Amount ──────────────────────────────────────────────
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: _teal),
              decoration: InputDecoration(
                labelText: 'add_expense.amount_label'.tr(),
                labelStyle: const TextStyle(fontSize: 13),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (_) => setState(() {}),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'add_expense.amount_label'.tr();
                final d = Decimal.tryParse(v.trim().replaceAll(',', '.'));
                if (d == null || d <= Decimal.zero) return 'add_expense.enter_valid_amount'.tr();
                return null;
              },
            ),
            const SizedBox(height: 12),

            // ── Currency ───────────────────────────────────────────────
            CurrencyPickerField(
              selected: _currency,
              onChanged: (code) {
                HapticUtils.selection();
                setState(() => _currency = code);
              },
            ),
            const SizedBox(height: 16),

            // ── Category chips (standard + user) ─────────────────────────
            Row(
              children: [
                Text('add_expense.category_label'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            Text('add_expense.standard_categories'.tr(),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 10, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8, runSpacing: 6,
              children: kExpenseCategories.map((cat) {
                final sel = _category == cat;
                return FilterChip(
                  label: Text(categoryTr(cat), style: const TextStyle(fontSize: 11)),
                  selected: sel,
                  selectedColor: _teal.withValues(alpha: 0.15),
                  checkmarkColor: _teal,
                  labelStyle: TextStyle(
                    color: sel ? _teal : null,
                    fontWeight: sel ? FontWeight.w600 : FontWeight.normal,
                  ),
                  onSelected: (_) {
                    HapticUtils.selection();
                    setState(() => _category = cat);
                  },
                );
              }).toList(),
            ),
            userCatsAsync.when(
              data: (cats) {
                if (cats.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 10),
                    Text('add_expense.your_categories'.tr(),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                          fontSize: 10, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8, runSpacing: 6,
                      children: cats.map((cat) {
                        final name = cat['name'] ?? '';
                        final sel  = _category == name;
                        final isIncomeCat = cat['type'] == 'income';
                        final catColor = isIncomeCat
                            ? const Color(0xFF22C55E)
                            : _teal;
                        return FilterChip(
                          avatar: Icon(
                            isIncomeCat
                                ? Icons.arrow_downward_rounded
                                : Icons.arrow_upward_rounded,
                            size: 12,
                            color: sel ? catColor
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                          label: Text(name,
                              style: const TextStyle(fontSize: 11)),
                          selected: sel,
                          selectedColor: catColor.withValues(alpha: 0.15),
                          checkmarkColor: catColor,
                          labelStyle: TextStyle(
                            color: sel ? catColor : null,
                            fontWeight: sel
                                ? FontWeight.w600
                                : FontWeight.normal,
                          ),
                          onSelected: (_) {
                            HapticUtils.selection();
                            setState(() => _category = name);
                          },
                        );
                      }).toList(),
                    ),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 16),

            // ── Description ──────────────────────────────────────────────
            TextFormField(
              controller: _descriptionController,
              decoration: InputDecoration(
                labelText: 'add_expense.description_label'.tr(),
                prefixIcon: const Icon(Icons.notes_outlined),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            // ── Attachments ─────────────────────────────────────────────
            Row(
              children: [
                Text('common.attachments'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
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
                    final isImg = isLocalPath && (path.endsWith('.jpg') ||
                        path.endsWith('.jpeg') ||
                        path.endsWith('.png') ||
                        path.endsWith('.webp'));
                    return Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: isImg
                              ? Image.file(File(path),
                                  width: 80, height: 80, fit: BoxFit.cover)
                              : Container(
                                  width: 80, height: 80,
                                  color: theme.colorScheme.surfaceContainerHighest,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      const Icon(Icons.insert_drive_file_outlined, size: 28),
                                      const SizedBox(height: 4),
                                      Text(path.split('.').last.toUpperCase(),
                                          style: const TextStyle(
                                              fontSize: 9, fontWeight: FontWeight.w700)),
                                    ],
                                  ),
                                ),
                        ),
                        Positioned(
                          top: 2, right: 2,
                          child: GestureDetector(
                            onTap: () => setState(
                                () => _attachmentPaths.removeAt(i)),
                            child: Container(
                              width: 20, height: 20,
                              decoration: const BoxDecoration(
                                  color: Colors.black54,
                                  shape: BoxShape.circle),
                              child: const Icon(Icons.close,
                                  size: 12, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 12),

            // ── Notes ───────────────────────────────────────────────────
            TextFormField(
              controller: _notesController,
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

            const SizedBox(height: 16),

            // ── Payer selector (group expenses only) ─────────────────────
            if (widget.groupId.isNotEmpty && _members.isNotEmpty) ..._buildPayerSection(theme),

            // ── Split mode + per-member inputs ───────────────────────────
            if (widget.groupId.isNotEmpty && _members.length > 1) ..._buildSplitSection(theme),

            const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: FilledButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 22, width: 22,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                        )
                      : Text('edit_expense.save_changes'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Icon + Color picker bottom sheet
// ---------------------------------------------------------------------------
class _IconColorPicker extends StatefulWidget {
  const _IconColorPicker({
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
  State<_IconColorPicker> createState() => _IconColorPickerState();
}

class _IconColorPickerState extends State<_IconColorPicker> {
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
          // Preview
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
          Text('Colour', style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700, fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          )),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: _kEntryColors.map((c) {
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
                    border: sel
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                    boxShadow: sel
                        ? [BoxShadow(color: c.withValues(alpha: 0.5), blurRadius: 6)]
                        : null,
                  ),
                  child: sel
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          Text('Icon', style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700, fontSize: 11,
            color: theme.colorScheme.onSurfaceVariant,
          )),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10, runSpacing: 10,
            children: _kEntryIcons.map((ic) {
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
                    border: sel
                        ? Border.all(color: _color, width: 2)
                        : null,
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

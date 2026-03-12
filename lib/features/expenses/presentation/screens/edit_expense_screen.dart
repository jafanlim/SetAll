import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
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

const _teal   = Color(0xFF00D9B0);
const _orange = Color(0xFFFF8C42);

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
      type: FileType.custom,
      allowedExtensions: ['pdf', 'doc', 'docx', 'xlsx', 'csv', 'txt'],
    );
    if (result == null || result.files.isEmpty || !mounted) return;
    final path = result.files.first.path;
    if (path != null) {
      setState(() => _attachmentPaths.add(path));
      HapticUtils.success();
    }
  }

  Future<void> _pickDateTime() async {
    HapticUtils.lightTap();
    final date = await showDatePicker(
      context: context,
      initialDate: _entryDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
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

  void _rebuildControllers() {
    for (final c in _customCtrl.values) { c.dispose(); }
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
    final currentUid = await repo.ensureUser();
    var members      = await repo.getGroupMembers(widget.groupId);

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
          : SplitMode.manual;
      _payerId   = expense.payerId.isNotEmpty ? expense.payerId : currentUid;
      if (expense.createdAt != null) {
        _entryDate = DateTime.tryParse(expense.createdAt!)?.toLocal() ?? DateTime.now();
      }

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
            SnackBar(content: Text('Amounts must sum to $amount (got $totalManual)'))); }
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
      isIncome:    _expense?.isIncome ?? false,
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

    final userCatsAsync = ref.watch(userCategoriesProvider);
    final dateLabel = DateFormat('EEE, d MMM yyyy  HH:mm').format(_entryDate);
    final isToday = () {
      final now = DateTime.now();
      return _entryDate.year == now.year &&
          _entryDate.month == now.month &&
          _entryDate.day == now.day;
    }();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit entry'),
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
                      Text('Icon & Colour',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: _showIconPicker,
                        icon: const Icon(Icons.palette_outlined, size: 14),
                        label: const Text('Change icon & colour',
                            style: TextStyle(fontSize: 12)),
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
                        isToday ? 'Today · $dateLabel' : dateLabel,
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
                labelText: 'Amount',
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
                if (v == null || v.trim().isEmpty) return 'Enter amount';
                final d = Decimal.tryParse(v.trim().replaceAll(',', '.'));
                if (d == null || d <= Decimal.zero) return 'Enter a valid amount';
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
                Text('Category',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Standard',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 10, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8, runSpacing: 6,
              children: kExpenseCategories.map((cat) {
                final sel = _category == cat;
                return FilterChip(
                  label: Text(cat, style: const TextStyle(fontSize: 11)),
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
                    Text('Your Categories',
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
                labelText: 'Description (optional)',
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
                Text('Attachments',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                const Spacer(),
                AttachButton(
                  icon: Icons.photo_camera_outlined,
                  label: 'Camera',
                  onTap: () => _pickImage(ImageSource.camera),
                ),
                const SizedBox(width: 8),
                AttachButton(
                  icon: Icons.photo_library_outlined,
                  label: 'Gallery',
                  onTap: () => _pickImage(ImageSource.gallery),
                ),
                const SizedBox(width: 8),
                AttachButton(
                  icon: Icons.attach_file_outlined,
                  label: 'File',
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
                    final isImg = path.endsWith('.jpg') ||
                        path.endsWith('.jpeg') ||
                        path.endsWith('.png') ||
                        path.endsWith('.webp');
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
            const SizedBox(height: 16),

            // ── Paid by ───────────────────────────────────────────────
            if (_members.length > 1) ...[
              DropdownButtonFormField<String>(
                initialValue: _members.any((m) => m.id == _payerId) ? _payerId : null,
                decoration: InputDecoration(
                  labelText: 'Paid by',
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  isDense: true,
                ),
                items: _members
                    .map((m) => DropdownMenuItem(value: m.id, child: Text(m.name)))
                    .toList(),
                onChanged: (v) => setState(() => _payerId = v),
              ),
              const SizedBox(height: 16),
            ],

            // ── Split mode ───────────────────────────────────────────────────
            Text(
              'How to split',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
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
              ..._members.map((m) {
                final c = _customCtrl[m.id];
                if (c == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          m.name,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 90,
                        child: TextFormField(
                          controller: c,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              if (_splitMode == SplitMode.manual) ...[
                const SizedBox(height: 8),
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
                      fontSize: 11,
                      color: ok ? _teal : _orange,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                }),
              ],
            ] else ...[
              const SizedBox(height: 12),
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
                      'Split evenly among ${_members.length} members',
                      style: const TextStyle(color: _teal, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 40),
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      height: 22, width: 22,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black54),
                    )
                  : const Text('Save changes', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 32),
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
    );
  }
}

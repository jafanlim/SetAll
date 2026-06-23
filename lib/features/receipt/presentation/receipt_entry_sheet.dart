import 'dart:io' show Directory, File;

import 'package:cunning_document_scanner/cunning_document_scanner.dart';
import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:pdfx/pdfx.dart';
import 'package:uuid/uuid.dart';

import '../../../core/models/receipt_ingest_result.dart';
import '../../../core/providers/setall_providers.dart';
import '../../../core/services/receipt_cache_service.dart';
import '../../../core/services/receipt_ingest_service.dart';
import '../../../core/utils/haptic_utils.dart';
import '../../../data/models/wallet_entry_model.dart';
import '../../../data/models/profile_model.dart';
import '../../../data/repositories/setall_repository.dart' show SplitInsert;
import '../../../domain/entities/expense.dart' show SplitType;

// ── Brand colours ──────────────────────────────────────────────────────────
const _teal        = Color(0xFF00D9B0);
const _purple      = Color(0xFF7C3AED);
const _orange      = Color(0xFFFF8C42);
const _blue = Color(0xFF3B82F6);
const _surfaceDark = Color(0xFF0F172A);

enum ReceiptEntryState { scanning, processing, confirming, saving, done, error }

enum _ScanSource { camera, gallery, file }

class ReceiptEntrySheet extends ConsumerStatefulWidget {
  const ReceiptEntrySheet({
    super.key,
    this.groupId,
    required this.defaultCurrency,
  });

  /// null = wallet entry; non-null = group expense.
  final String? groupId;
  final String defaultCurrency;

  @override
  ConsumerState<ReceiptEntrySheet> createState() => _ReceiptEntrySheetState();
}

class _ReceiptEntrySheetState extends ConsumerState<ReceiptEntrySheet> {
  ReceiptEntryState _state = ReceiptEntryState.scanning;
  String _errorMsg = '';

  // Compressed image bytes (kept for caching after save).
  List<int>? _webpBytes;
  // Path to the scanned image file for preview.
  String? _imagePath;

  // Parsed draft from AI.
  ReceiptDraft? _draft;

  // Editable fields.
  final _amountCtrl  = TextEditingController();
  final _descCtrl    = TextEditingController();
  String? _selectedPayerId;
  String _editCurrency = 'USD';
  String _editCategory = 'General';
  DateTime _editDate = DateTime.now();
  String? _originalDescription;
  List<_EditableLineItem> _lineItems = [];

  // Clarification target.
  String? _clarifyField;

  static const _commonCurrencies = [
    'USD', 'AED', 'GEL', 'EUR', 'GBP', 'RUB', 'CNY', 'VND', 'INR',
  ];

  @override
  void initState() {
    super.initState();
    _amountCtrl.addListener(_onItemFieldChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    for (final li in _lineItems) {
      li.dispose();
    }
    super.dispose();
  }

  // ── Core flow ──────────────────────────────────────────────────────────

  Future<_ScanSource?> _chooseSource() async {
    return showModalBottomSheet<_ScanSource>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: _surfaceDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle
              Padding(
                padding: const EdgeInsets.only(top: 12, bottom: 8),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Title
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 4, 24, 16),
                child: Text(
                  'receipt.source_title'.tr(),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              // Camera
              _sourceTile(
                icon: Icons.document_scanner_rounded,
                color: _purple,
                title: 'receipt.source_camera'.tr(),
                onTap: () => Navigator.pop(context, _ScanSource.camera),
              ),
              // Gallery
              _sourceTile(
                icon: Icons.photo_library_rounded,
                color: _blue,
                title: 'receipt.source_gallery'.tr(),
                onTap: () => Navigator.pop(context, _ScanSource.gallery),
              ),
              // File
              _sourceTile(
                icon: Icons.insert_drive_file_rounded,
                color: _orange,
                title: 'receipt.source_file'.tr(),
                onTap: () => Navigator.pop(context, _ScanSource.file),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sourceTile({
    required IconData icon,
    required Color color,
    required String title,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Colors.white24,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        tileColor: Colors.white.withValues(alpha: 0.04),
        onTap: onTap,
      ),
    );
  }

  Future<void> _startScan() async {
    if (!mounted) return;

    final source = await _chooseSource();
    if (!mounted) return;
    if (source == null) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _state = ReceiptEntryState.scanning);

    String? path;

    switch (source) {
      case _ScanSource.camera:
        path = await _captureCamera();
      case _ScanSource.gallery:
        path = await _pickGallery();
      case _ScanSource.file:
        path = await _pickFile();
    }

    if (path == null || path.isEmpty) {
      if (mounted) {
        setState(() {
          _state = ReceiptEntryState.error;
          _errorMsg = 'receipt.scan_failed'.tr();
        });
      }
      return;
    }

    _imagePath = path;
    await _processReceipt(path);
  }

  Future<String?> _captureCamera() async {
    if (kIsWeb) {
      try {
        final xfile = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        return xfile?.path;
      } catch (_) {
        return null;
      }
    }

    // Native: cunning_document_scanner.
    try {
      final pictures = await CunningDocumentScanner.getPictures(
        noOfPages: 1,
        isGalleryImportAllowed: false,
      );
      if (pictures != null && pictures.isNotEmpty) return pictures.first;
    } catch (_) {
      // Fallback to image_picker camera on native.
      try {
        final xfile = await ImagePicker().pickImage(
          source: ImageSource.camera,
          imageQuality: 85,
        );
        return xfile?.path;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<String?> _pickGallery() async {
    try {
      final xfile = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
      return xfile?.path;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'webp'],
      );
      if (result == null || result.files.isEmpty) return null;

      final file = result.files.first;
      final filePath = file.path;
      if (filePath == null) return null;

      // If PDF, rasterize page 1 to PNG.
      final ext = file.extension?.toLowerCase();
      if (ext == 'pdf') {
        return await _rasterizePdf(filePath);
      }

      return filePath;
    } catch (_) {
      return null;
    }
  }

  Future<String?> _rasterizePdf(String pdfPath) async {
    try {
      final doc = await PdfDocument.openFile(pdfPath);
      try {
        final page = await doc.getPage(1);
        try {
          final img = await page.render(
            width: page.width * 2,
            height: page.height * 2,
            format: PdfPageImageFormat.png,
            backgroundColor: '#FFFFFF',
          );
          if (img == null) return null;

          final dir = Directory.systemTemp.createTempSync('receipt_');
          final pngPath = '${dir.path}/r_${const Uuid().v4()}.png';
          File(pngPath).writeAsBytesSync(img.bytes);
          return pngPath;
        } finally {
          await page.close();
        }
      } finally {
        await doc.close();
      }
    } catch (_) {
      return null;
    }
  }

  Future<void> _processReceipt(String imagePath) async {
    if (!mounted) return;
    setState(() => _state = ReceiptEntryState.processing);

    // Capture locale before any async gap (lint: use_build_context_synchronously).
    final locale = context.locale.languageCode;

    try {
      // 1. Compress.
      final bytes = await ReceiptIngestService.instance.compressReceipt(imagePath);
      if (bytes == null || bytes.isEmpty) {
        if (mounted) {
          setState(() {
            _state    = ReceiptEntryState.error;
            _errorMsg = 'receipt.compress_failed'.tr();
          });
        }
        return;
      }
      _webpBytes = bytes;

      // 2. Build localized categories (mirror voice_entry_sheet:178-194).
      final translatedCategories = [
        'categories.food_drink'.tr(),
        'categories.transport'.tr(),
        'categories.travel'.tr(),
        'categories.entertainment'.tr(),
        'categories.bills_utilities'.tr(),
        'categories.shopping'.tr(),
        'categories.general'.tr(),
        'categories.other'.tr(),
      ];

      final timezone = DateTime.now().timeZoneName;

      // 3. Ingest.
      final response = await ReceiptIngestService.instance.ingest(
        bytes,
        groupId: widget.groupId,
        defaultCurrency: widget.defaultCurrency,
        knownCategories: translatedCategories,
        timezone: timezone,
        locale: locale,
      );

      if (!mounted) return;

      // 4. Handle clarification.
      if (response.hasClarification) {
        _draft = response.partial ?? ReceiptDraft(
          amount: Decimal.zero,
          currency: widget.defaultCurrency,
          description: '',
          category: 'General',
          isIncome: false,
          merchantName: '',
          lineItems: const [],
          entryDate: DateTime.now(),
          confidence: 0.0,
        );
        _clarifyField = response.needsClarification;
        _populateEditableFields(_draft!);
        // Focus the field that needs clarification.
        setState(() => _state = ReceiptEntryState.confirming);
        return;
      }

      if (response.hasDraft && response.draft != null) {
        _draft = response.draft!;
        _populateEditableFields(_draft!);
        setState(() => _state = ReceiptEntryState.confirming);
      } else {
        setState(() {
          _state    = ReceiptEntryState.error;
          _errorMsg = 'receipt.parse_empty'.tr();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state    = ReceiptEntryState.error;
          _errorMsg = e.toString().contains('Rate limit')
              ? 'receipt.rate_limit'.tr()
              : 'receipt.error_title'.tr();
        });
      }
    }
  }

  void _populateEditableFields(ReceiptDraft draft) {
    _editCurrency  = draft.currency.isNotEmpty ? draft.currency : widget.defaultCurrency;
    _editCategory  = draft.category.isNotEmpty ? draft.category : 'General';
    _editDate      = draft.entryDate;
    _amountCtrl.text = draft.amount > Decimal.zero
        ? draft.amount.toStringAsFixed(2)
        : '';
    _descCtrl.text   = draft.description;
    _originalDescription = draft.originalDescription;
    // Dispose any existing line-item controllers before replacing.
    for (final li in _lineItems) {
      li.dispose();
    }
    _lineItems = draft.lineItems
        .map((li) => _EditableLineItem(
              id: const Uuid().v4(),
              nameCtrl: TextEditingController(text: li.name),
              originalName: li.originalName,
              amountCtrl: TextEditingController(
                text: li.amount > Decimal.zero ? li.amount.toStringAsFixed(2) : '',
              ),
              qtyCtrl: TextEditingController(text: li.quantity.toString()),
            ))
        .toList();
    for (final li in _lineItems) {
      li.amountCtrl.addListener(_onItemFieldChanged);
      li.qtyCtrl.addListener(_onItemFieldChanged);
    }
  }

  // ── Save ───────────────────────────────────────────────────────────────

  Future<void> _confirm() async {
    HapticUtils.primaryTap();

    final amountText = _amountCtrl.text.trim();
    if (amountText.isEmpty) {
      setState(() {
        _state    = ReceiptEntryState.error;
        _errorMsg = 'receipt.missing_amount'.tr();
      });
      return;
    }
    final amount = Decimal.tryParse(amountText);
    if (amount == null || amount <= Decimal.zero) {
      setState(() {
        _state    = ReceiptEntryState.error;
        _errorMsg = 'receipt.invalid_amount'.tr();
      });
      return;
    }

    setState(() => _state = ReceiptEntryState.saving);

    try {
      final repo = ref.read(setAllRepositoryProvider);
      final uid  = await repo.ensureUser();
      if (uid == null) throw Exception('Not authenticated');

      final description = _descCtrl.text.trim().isNotEmpty
          ? _descCtrl.text.trim()
          : _draft?.merchantName ?? 'Receipt entry';
      final category = _editCategory;
      final currency = _editCurrency;
      final isIncome = _draft?.isIncome ?? false;

      String expenseId;

      if (widget.groupId != null) {
        // ── Group expense ──
        final members =
            ref.read(groupMembersProvider(widget.groupId!)).valueOrNull ?? [];
        final payerId = _resolvePayerId(members, uid);
        final splits = <SplitInsert>[
          SplitInsert(userId: payerId, universalUsdOwed: amount),
        ];

        final expense = await repo.addExpense(
          groupId:     widget.groupId,
          payerId:     payerId,
          amount:      amount,
          description: description,
          currency:    currency,
          splitType:   SplitType.manual,
          splits:      splits,
          category:    category,
          isIncome:    isIncome,
          entryDate:   _editDate,
        );
        if (expense == null) throw Exception('Failed to save group expense');
        expenseId = expense.id;
      } else {
        // ── Wallet entry ──
        final entry = WalletEntryModel(
          id:          const Uuid().v4(),
          userId:      uid,
          amount:      amount.toString(),
          isIncome:    isIncome,
          description: description,
          category:    category,
          currency:    currency,
          createdAt:   _editDate.toUtc().toIso8601String(),
        );
        final saved = await repo.upsertWalletEntry(entry);
        expenseId = saved.id;
      }

      // Cache the receipt image.
      if (_webpBytes != null) {
        await ReceiptCacheService.instance.cache(expenseId, _webpBytes!);
      }

      // Write-back memory (fire-and-forget).
      final merchantName = _draft?.merchantName ?? description;
      final firstLineItemName = _lineItems.isNotEmpty
          ? _lineItems.first.nameCtrl.text.trim()
          : null;
      ReceiptIngestService.instance.writeBackMemory(
        merchantName: merchantName,
        category: category,
        groupId: widget.groupId,
        itemName: (firstLineItemName != null && firstLineItemName.isNotEmpty)
            ? firstLineItemName
            : null,
      );

      // Invalidate relevant providers.
      ref.invalidate(balanceSummaryProvider);
      ref.invalidate(recentExpensesProvider);

      if (!mounted) return;
      setState(() => _state = ReceiptEntryState.done);
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (mounted) Navigator.of(context).pop();
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _state    = ReceiptEntryState.error;
          _errorMsg = 'receipt.save_failed'.tr();
        });
      }
    }
  }

  // ── Line item helpers ───────────────────────────────────────────────────

  void _addLineItem() {
    final li = _EditableLineItem(
      id: const Uuid().v4(),
      nameCtrl: TextEditingController(),
      amountCtrl: TextEditingController(),
      qtyCtrl: TextEditingController(text: '1'),
    );
    li.amountCtrl.addListener(_onItemFieldChanged);
    li.qtyCtrl.addListener(_onItemFieldChanged);
    setState(() => _lineItems.add(li));
  }

  void _onItemFieldChanged() {
    setState(() {});
  }

  Decimal _computeItemsTotal() {
    Decimal total = Decimal.zero;
    for (final li in _lineItems) {
      final price = Decimal.tryParse(li.amountCtrl.text.trim()) ?? Decimal.zero;
      if (price > Decimal.zero) {
        total += price;
      }
    }
    return total;
  }

  String _resolvePayerId(List<ProfileModel> members, String currentUserId) {
    if (_selectedPayerId != null &&
        members.any((m) => m.id == _selectedPayerId)) {
      return _selectedPayerId!;
    }
    if (_draft?.payerLabel != null && _draft!.payerLabel!.isNotEmpty) {
      final label = _draft!.payerLabel!.toLowerCase();
      final match = members.cast<ProfileModel?>().firstWhere(
            (m) =>
                m!.name.toLowerCase() == label ||
                (m.nickname?.toLowerCase() ?? '') == label,
            orElse: () => null,
          );
      if (match != null) return match.id;
    }
    if (members.any((m) => m.id == currentUserId)) return currentUserId;
    if (members.isNotEmpty) return members.first.id;
    return currentUserId;
  }

  void _removeLineItem(String id) {
    setState(() {
      final idx = _lineItems.indexWhere((li) => li.id == id);
      if (idx != -1) {
        _lineItems[idx].dispose();
        _lineItems.removeAt(idx);
      }
    });
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      builder: (context, scrollController) => Container(
        decoration: const BoxDecoration(
          color: _surfaceDark,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            _buildHandle(),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => FocusScope.of(context).unfocus(),
                child: SingleChildScrollView(
                  controller: scrollController,
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
                  child: _buildBody(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Container(
        width: 40, height: 4,
        decoration: BoxDecoration(
          color: Colors.white24,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildBody() {
    switch (_state) {
      case ReceiptEntryState.scanning:   return _buildScanning();
      case ReceiptEntryState.processing: return _buildProcessing();
      case ReceiptEntryState.confirming: return _buildConfirming();
      case ReceiptEntryState.saving:     return _buildSaving();
      case ReceiptEntryState.done:       return _buildDone();
      case ReceiptEntryState.error:      return _buildError();
    }
  }

  // ── SCANNING ────────────────────────────────────────────────────────────

  Widget _buildScanning() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 40),
        Container(
          width: 72, height: 72,
          decoration: BoxDecoration(
            color: _purple.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: _purple.withValues(alpha: 0.4), width: 2),
          ),
          child: const Icon(Icons.document_scanner_rounded, color: _purple, size: 34),
        ),
        const SizedBox(height: 20),
        Text(
          'receipt.scanning'.tr(),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'receipt.opening_scanner'.tr(),
          style: const TextStyle(fontSize: 13, color: Colors.white54),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ── PROCESSING ───────────────────────────────────────────────────────────

  Widget _buildProcessing() {
    return Column(
      children: [
        const SizedBox(height: 60),
        const CircularProgressIndicator(color: _teal),
        const SizedBox(height: 24),
        Text(
          'receipt.processing'.tr(),
          style: const TextStyle(fontSize: 16, color: Colors.white70),
        ),
        const SizedBox(height: 8),
        Text(
          'receipt.analyzing'.tr(),
          style: const TextStyle(fontSize: 12, color: Colors.white38),
        ),
        const SizedBox(height: 60),
      ],
    );
  }

  // ── CONFIRMING ──────────────────────────────────────────────────────────

  Widget _buildConfirming() {
    final amountColor = (_draft?.isIncome ?? false) ? _teal : _orange;
    final sign        = (_draft?.isIncome ?? false) ? '+' : '-';

    final currencyValue = _commonCurrencies.contains(_editCurrency)
        ? _editCurrency
        : _commonCurrencies.first;

    final parsedAmount = Decimal.tryParse(_amountCtrl.text) ?? Decimal.zero;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),

        // ── Scanned image preview ──
        if (_imagePath != null && File(_imagePath!).existsSync()) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(_imagePath!),
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Amount & Currency ──
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Merchant / header
              if (_draft?.merchantName != null && _draft!.merchantName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    _draft!.merchantName,
                    style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: Colors.white54, letterSpacing: 0.5,
                    ),
                  ),
                ),

              Text(
                '$sign$_editCurrency ${parsedAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 28, fontWeight: FontWeight.w800, color: amountColor,
                ),
              ),
              const SizedBox(height: 14),

              // Amount + currency row
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: 3,
                    child: _darkField(
                      controller: _amountCtrl,
                      label: 'voice_entry.amount_label'.tr(),
                      keyboard: const TextInputType.numberWithOptions(decimal: true),
                      hint: _clarifyField == 'amount'
                          ? 'receipt.clarify_amount'.tr()
                          : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: currencyValue,
                          dropdownColor: const Color(0xFF1E293B),
                          style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600,
                          ),
                          items: _commonCurrencies
                              .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _editCurrency = v);
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Description
              _darkField(
                controller: _descCtrl,
                label: 'voice_entry.description_label'.tr(),
              ),
              if (_originalDescription != null &&
                  _originalDescription!.isNotEmpty &&
                  _originalDescription != _descCtrl.text)
                Padding(
                  padding: const EdgeInsets.only(left: 4, top: 2),
                  child: Text(
                    _originalDescription!,
                    style: const TextStyle(
                        fontSize: 10, color: Colors.white38),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(height: 10),

              // Payer selector (group only)
              if (widget.groupId != null)
                _buildPayerDropdown(),

              // Category chip selector
              Text(
                'receipt.category'.tr(),
                style: const TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              _buildCategoryChips(),
              const SizedBox(height: 12),

              // Date picker
              Row(
                children: [
                  const Icon(Icons.calendar_today_rounded, size: 14, color: Colors.white38),
                  const SizedBox(width: 6),
                  Text(
                    'receipt.date'.tr(),
                    style: const TextStyle(fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _editDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 1)),
                        builder: (ctx, child) => Theme(
                          data: Theme.of(ctx).copyWith(
                            colorScheme: const ColorScheme.dark(
                              primary: _teal,
                              onPrimary: Colors.black,
                              surface: _surfaceDark,
                              onSurface: Colors.white,
                            ),
                          ),
                          child: child!,
                        ),
                      );
                      if (picked != null) setState(() => _editDate = picked);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${_editDate.year}-${_editDate.month.toString().padLeft(2, '0')}-${_editDate.day.toString().padLeft(2, '0')}',
                        style: const TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Confidence badge
              if (_draft?.confidence != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _teal.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'receipt.confidence'.tr(namedArgs: {
                      'pct': (_draft!.confidence * 100).toStringAsFixed(0),
                    }),
                    style: const TextStyle(fontSize: 10, color: _teal),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // ── Line items ──
        Row(
          children: [
            Text(
              'receipt.line_items'.tr(),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white70),
            ),
            const Spacer(),
            TextButton.icon(
              onPressed: _addLineItem,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text('receipt.add_item'.tr(), style: const TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: _teal, padding: EdgeInsets.zero),
            ),
          ],
        ),
        if (_lineItems.isNotEmpty) ...[
          const SizedBox(height: 4),
          _buildItemsTotal(),
        ],
        if (_lineItems.isNotEmpty) ...[
          const SizedBox(height: 6),
          ..._lineItems.map((li) => _buildLineItemRow(li)),
        ],

        const SizedBox(height: 20),

        // ── Confirm button ──
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _confirm,
            icon: const Icon(Icons.check_rounded),
            label: Text(
              'voice_entry.confirm_btn'.tr(),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () {
              HapticUtils.lightTap();
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.white38),
            child: Text('voice_entry.cancel_btn'.tr()),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryChips() {
    final categories = [
      'categories.food_drink'.tr(),
      'categories.transport'.tr(),
      'categories.travel'.tr(),
      'categories.entertainment'.tr(),
      'categories.bills_utilities'.tr(),
      'categories.shopping'.tr(),
      'categories.general'.tr(),
      'categories.other'.tr(),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: categories.map((cat) {
        final selected = _editCategory == cat;
        return GestureDetector(
          onTap: () => setState(() => _editCategory = cat),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: selected ? _purple.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? _purple.withValues(alpha: 0.5) : Colors.white24,
              ),
            ),
            child: Text(
              cat,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: selected ? _purple : Colors.white54,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildPayerDropdown() {
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId!));
    final currentUserId = ref.watch(currentUserIdProvider);

    return membersAsync.when(
      data: (members) => _buildPayerSelector(members, currentUserId),
      loading: () => _buildPayerLoading(),
      error: (_, _) => _buildPayerFallback(currentUserId),
    );
  }

  Widget _buildPayerSelector(List<ProfileModel> members, String? currentUserId) {
    // Resolve effective payer ID.
    String? effectiveId = _selectedPayerId;
    if (effectiveId == null &&
        _draft?.payerLabel != null &&
        _draft!.payerLabel!.isNotEmpty) {
      final label = _draft!.payerLabel!.toLowerCase();
      effectiveId = members
          .cast<ProfileModel?>()
          .firstWhere(
            (m) =>
                m!.name.toLowerCase() == label ||
                (m.nickname?.toLowerCase() ?? '') == label,
            orElse: () => null,
          )
          ?.id;
    }
    effectiveId ??= currentUserId;
    if (effectiveId != null && !members.any((m) => m.id == effectiveId)) {
      effectiveId = currentUserId;
    }
    if (effectiveId == null && members.isNotEmpty) {
      effectiveId = members.first.id;
    }
    if (effectiveId == null) {
      return _buildPayerFallback(currentUserId);
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'receipt.paid_by_member'.tr(),
            style: const TextStyle(
                fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(10),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: effectiveId,
                dropdownColor: const Color(0xFF1E293B),
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600),
                isExpanded: true,
                items: members
                    .map((m) => DropdownMenuItem(
                          value: m.id,
                          child: Text(
                            m.nickname ?? m.name,
                            style: const TextStyle(fontSize: 14),
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _selectedPayerId = v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayerLoading() {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: SizedBox(
        height: 44,
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
          ),
        ),
      ),
    );
  }

  Widget _buildPayerFallback(String? currentUserId) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'receipt.paid_by_member'.tr(),
            style: const TextStyle(
                fontSize: 11, color: Colors.white38, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              currentUserId ?? '—',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsTotal() {
    final itemsTotal = _computeItemsTotal();
    final parsedAmount =
        Decimal.tryParse(_amountCtrl.text.trim()) ?? Decimal.zero;
    final diff = (parsedAmount - itemsTotal).abs();
    final showDiff = itemsTotal > Decimal.zero &&
        diff > Decimal.parse('0.01');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${'receipt.items_total'.tr()}: ${itemsTotal.toStringAsFixed(2)} $_editCurrency',
          style: const TextStyle(fontSize: 11, color: Colors.white54),
        ),
        if (showDiff)
          Row(
            children: [
              Flexible(
                child: Text(
                  '${'receipt.entered_total'.tr()} ${parsedAmount.toStringAsFixed(2)} $_editCurrency · ${'receipt.items_total_diff'.tr(namedArgs: {'diff': diff.toStringAsFixed(2)})}',
                  style: const TextStyle(fontSize: 10, color: _orange),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  _amountCtrl.text = itemsTotal.toStringAsFixed(2);
                  setState(() {});
                },
                child: Text(
                  'receipt.use_this'.tr(),
                  style: const TextStyle(
                      fontSize: 11,
                      color: _teal,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline),
                ),
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildLineItemRow(_EditableLineItem li) {
    final showOriginalName = li.originalName != null &&
        li.originalName!.isNotEmpty &&
        li.originalName != li.nameCtrl.text;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment:
            showOriginalName ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 36,
                  child: TextField(
                    controller: li.nameCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'receipt.item_name'.tr(),
                      hintStyle:
                          const TextStyle(color: Colors.white30, fontSize: 12),
                      filled: true,
                      fillColor: Colors.white10,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 10),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                if (showOriginalName)
                  Padding(
                    padding: const EdgeInsets.only(left: 4, top: 2),
                    child: Text(
                      li.originalName!,
                      style: const TextStyle(
                          fontSize: 10, color: Colors.white38),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 80,
            height: 36,
            child: TextField(
              controller: li.amountCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                hintText: '0.00',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                filled: true,
                fillColor: Colors.white10,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 44,
            height: 36,
            child: TextField(
              controller: li.qtyCtrl,
              style: const TextStyle(color: Colors.white, fontSize: 13),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: 'x1',
                hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
                filled: true,
                fillColor: Colors.white10,
                contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: () => _removeLineItem(li.id),
            child: const Icon(Icons.close_rounded, size: 18, color: Colors.white38),
          ),
        ],
      ),
    );
  }

  // ── SAVING ───────────────────────────────────────────────────────────────

  Widget _buildSaving() {
    return Column(
      children: [
        const SizedBox(height: 60),
        const SizedBox(
          width: 28, height: 28,
          child: CircularProgressIndicator(color: _teal, strokeWidth: 2.5),
        ),
        const SizedBox(height: 20),
        Text(
          'receipt.saving'.tr(),
          style: const TextStyle(fontSize: 16, color: Colors.white70),
        ),
        const SizedBox(height: 60),
      ],
    );
  }

  // ── DONE ─────────────────────────────────────────────────────────────────

  Widget _buildDone() {
    return Column(
      children: [
        const SizedBox(height: 48),
        const Icon(Icons.check_circle_rounded, color: _teal, size: 64),
        const SizedBox(height: 16),
        Text(
          'receipt.saved'.tr(),
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
        ),
        const SizedBox(height: 48),
      ],
    );
  }

  // ── ERROR ─────────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Column(
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 52),
        const SizedBox(height: 16),
        Text(
          _errorMsg,
          style: const TextStyle(fontSize: 15, color: Colors.white70),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _startScan,
            style: FilledButton.styleFrom(
              backgroundColor: _purple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('voice_entry.error_retry'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: TextButton(
            onPressed: () {
              HapticUtils.lightTap();
              Navigator.of(context).pop();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.white38),
            child: Text('receipt.enter_manually'.tr()),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ── Shared field widget ───────────────────────────────────────────────────

  Widget _darkField({
    required TextEditingController controller,
    required String label,
    TextInputType keyboard = TextInputType.text,
    String? hint,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        hintStyle: const TextStyle(color: Colors.white30, fontSize: 12),
        filled: true,
        fillColor: Colors.white10,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: _teal),
        ),
      ),
    );
  }
}

// ── Editable line item model ─────────────────────────────────────────────

class _EditableLineItem {
  final String id;
  final TextEditingController nameCtrl;
  final String? originalName;
  final TextEditingController amountCtrl;
  final TextEditingController qtyCtrl;

  _EditableLineItem({
    required this.id,
    required this.nameCtrl,
    this.originalName,
    required this.amountCtrl,
    required this.qtyCtrl,
  });

  void dispose() {
    nameCtrl.dispose();
    amountCtrl.dispose();
    qtyCtrl.dispose();
  }
}

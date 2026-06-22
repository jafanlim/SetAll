import 'dart:async' show unawaited;
import 'dart:io' as io;
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:pdfx/pdfx.dart';

import '../../../../core/services/date_format_service.dart';
import '../../../../core/services/receipt_cache_service.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/wallet_entry_model.dart';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const _purple      = Color(0xFF8B5CF6);
const _teal        = Color(0xFF00D9B0);
const _green       = Color(0xFF22C55E);
const _brandOrange = Color(0xFFF97316);

// Category icons
const Map<String, IconData> _kCategoryIcons = {
  'Food & drink':      Icons.restaurant_outlined,
  'Transport':         Icons.directions_car_outlined,
  'Entertainment':     Icons.movie_outlined,
  'Bills & utilities': Icons.receipt_long_outlined,
  'Shopping':          Icons.shopping_bag_outlined,
  'Travel':            Icons.flight_outlined,
  'General':           Icons.category_outlined,
  'Other':             Icons.category_outlined,
};

// Category colors
const Map<String, Color> _kCategoryColors = {
  'Food & drink':      Color(0xFFEF4444),
  'Transport':         Color(0xFF3B82F6),
  'Entertainment':     Color(0xFFA855F7),
  'Bills & utilities': Color(0xFFF59E0B),
  'Shopping':          Color(0xFFEC4899),
  'Travel':            Color(0xFF06B6D4),
  'General':           Color(0xFF8B5CF6),
  'Other':             Color(0xFF94A3B8),
};

/// Detail / information screen for a single wallet entry.
/// Shows the sum breakdown, mini analytics gauge, category badge,
/// and prominent [Edit] / [Delete] action buttons.
class WalletEntryDetailScreen extends ConsumerStatefulWidget {
  const WalletEntryDetailScreen({
    super.key,
    required this.expense,
  });

  final WalletEntryModel expense;

  @override
  ConsumerState<WalletEntryDetailScreen> createState() =>
      _WalletEntryDetailScreenState();
}

class _WalletEntryDetailScreenState
    extends ConsumerState<WalletEntryDetailScreen> {
  String? _receiptPath;

  @override
  void initState() {
    super.initState();
    _loadReceipt();
  }

  Future<void> _loadReceipt() async {
    final path = await ReceiptCacheService.instance.pathFor(widget.expense.id);
    if (mounted) setState(() => _receiptPath = path);
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete entry?'),
        content: const Text('This wallet entry will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _brandOrange,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(setAllRepositoryProvider).deleteWalletEntry(widget.expense.id);
    if (!mounted) return;
    unawaited(ref.read(syncServiceProvider).writeWidgetData());
    HapticUtils.success();
    ref.invalidate(walletEntriesProvider);
    ref.invalidate(walletEntryTotalsProvider);
    ref.invalidate(balanceSummaryProvider);
    ref.invalidate(omniActivityProvider);
    if (context.canPop()) context.pop();
  }

  void _edit() {
    HapticUtils.primaryTap();
    context.push(
      '/wallet/entry/edit/${widget.expense.id}',
      extra: widget.expense,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final expense     = widget.expense;
    final isIncome    = expense.isIncome;
    final accentColor = isIncome ? _green : _purple;

    final amt    = Decimal.tryParse(expense.amount) ?? Decimal.zero;
    final usdAmt = Decimal.tryParse(expense.universalUsdAmount) ?? Decimal.zero;
    final ccy    = expense.currency.isEmpty ? 'USD' : expense.currency;

    final baseCcyAsync = ref.watch(baseCurrencyProvider);
    final baseCcy      = baseCcyAsync.valueOrNull ?? 'USD';

    final categoryColor = _kCategoryColors[expense.category] ?? _purple;
    final categoryIcon  = _kCategoryIcons[expense.category] ?? Icons.category_outlined;

    // Use saved icon/color if available; otherwise fall back to default
    final entryColor = expense.iconColor != null ? Color(expense.iconColor!) : accentColor;
    final entryIcon  = expense.iconCodepoint != null
        ? IconData(expense.iconCodepoint!, fontFamily: 'MaterialIcons')
        : (isIncome ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded);

    // Mini analytics: wallet entries for category gauge
    final entriesAsync = ref.watch(walletEntriesProvider);
    final expenses = entriesAsync.valueOrNull ?? [];

    // Monthly spend for this category
    final now        = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    Decimal catMonthSpend  = Decimal.zero;
    Decimal totalMonthSpend = Decimal.zero;
    for (final e in expenses) {
      if (e.isIncome != isIncome) continue;  // match same type
      final createdAt = DateTime.tryParse(e.createdAt ?? '') ?? DateTime(2000);
      if (createdAt.isBefore(monthStart)) continue;
      final eAmt = Decimal.tryParse(e.universalUsdAmount) ?? Decimal.zero;
      totalMonthSpend += eAmt;
      if (e.category == expense.category) catMonthSpend += eAmt;
    }

    final gaugeRatio = (totalMonthSpend > Decimal.zero)
        ? (catMonthSpend / totalMonthSpend)
            .toDecimal(scaleOnInfinitePrecision: 4)
            .toDouble()
            .clamp(0.0, 1.0)
        : 0.0;

    // Date formatting
    final dateStr = expense.createdAt != null
        ? () {
            try {
              final dt = DateTime.parse(expense.createdAt!).toLocal();
              return DateFormatService.instance.formatWithTime(dt);
            } catch (_) { return expense.createdAt!; }
          }()
        : '—';

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          isIncome ? 'Income Entry' : 'Expense Entry',
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          // Edit button
          TextButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit'),
            style: TextButton.styleFrom(foregroundColor: _teal),
          ),
          // Delete button
          TextButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: _brandOrange),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [

          // ── Hero Amount Card ─────────────────────────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: entryColor.withAlpha(36),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(entryIcon, color: entryColor, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            expense.description.isEmpty ? 'Wallet entry' : expense.description,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700, fontSize: 15,
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // SUM BREAKDOWN
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      // Entry currency amount (large)
                      Text(
                        '${isIncome ? '+' : '-'}$ccy ${amt.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          color: accentColor,
                        ),
                      ),
                      // Default currency equivalent
                      if (ccy != baseCcy) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.swap_horiz, size: 14, color: Color(0xFF94A3B8)),
                            const SizedBox(width: 4),
                            Text(
                              '≈ $baseCcy ${usdAmt.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (expense.exchangeRateApplied != null && ccy != baseCcy) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Rate at entry: 1 $ccy = ${expense.exchangeRateApplied} $baseCcy',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Receipt thumbnail (from local cache, resets 30-day TTL) ──────
          if (_receiptPath != null) ...[
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.receipt_long_rounded, size: 16, color: _teal),
                      const SizedBox(width: 6),
                      Text(
                        'Scanned receipt',
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      showDialog(
                        context: context,
                        builder: (_) => Dialog(
                          backgroundColor: Colors.transparent,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: Image.file(
                              io.File(_receiptPath!),
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      );
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        io.File(_receiptPath!),
                        height: 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Category Card ────────────────────────────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(categoryIcon, color: categoryColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Category',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        expense.category.isEmpty ? 'General' : expense.category,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: categoryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                // Type badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    isIncome ? 'INCOME' : 'EXPENSE',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: accentColor,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Mini Analytics ───────────────────────────────────────────────
          if (true) ...[
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bar_chart_rounded, size: 16, color: accentColor),
                      const SizedBox(width: 6),
                      Text(
                        'Monthly ${isIncome ? 'Income' : 'Spending'} — ${expense.category.isEmpty ? 'General' : expense.category}',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700, fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // Gauge bar
                  Stack(
                    children: [
                      Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: gaugeRatio,
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: categoryColor,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _AnalyticPill(
                        label: expense.category.isEmpty ? 'General' : expense.category,
                        value: '≈ $baseCcy ${catMonthSpend.toStringAsFixed(0)}',
                        color: categoryColor,
                      ),
                      _AnalyticPill(
                        label: 'All categories',
                        value: '≈ $baseCcy ${totalMonthSpend.toStringAsFixed(0)}',
                        color: accentColor,
                      ),
                      _AnalyticPill(
                        label: 'Share',
                        value: '${(gaugeRatio * 100).toStringAsFixed(1)}%',
                        color: _teal,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Figures are approximated in $baseCcy using the USD anchor.',
                    style: TextStyle(
                      fontSize: 9,
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Attachments ──────────────────────────────────────────────────
          if ((expense.attachmentUrls ?? []).isNotEmpty) ...[
            _AttachmentsCard(expense: expense),
            const SizedBox(height: 12),
          ],

          // ── Notes ────────────────────────────────────────────────────────
          if (expense.notes != null && expense.notes!.trim().isNotEmpty) ...[
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.notes_outlined, size: 16, color: _teal),
                      const SizedBox(width: 6),
                      Text(
                        'Notes',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700, fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    expense.notes!.trim(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      height: 1.5,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Meta info ────────────────────────────────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _MetaRow(label: 'Entry ID',   value: widget.expense.id, mono: true),
                const Divider(height: 16),
                _MetaRow(label: 'Created',    value: dateStr),
                if (expense.originalCurrency != null && expense.originalCurrency != ccy) ...[
                  const Divider(height: 16),
                  _MetaRow(
                    label: 'Original',
                    value: '${expense.originalCurrency} ${expense.originalAmount ?? '—'}',
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helper widgets
// ---------------------------------------------------------------------------

class _AttachmentsCard extends ConsumerStatefulWidget {
  const _AttachmentsCard({required this.expense});
  final WalletEntryModel expense;

  @override
  ConsumerState<_AttachmentsCard> createState() => _AttachmentsCardState();
}

class _AttachmentsCardState extends ConsumerState<_AttachmentsCard> {
  final Map<String, String> _signedUrls = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _generateUrls();
  }

  Future<void> _generateUrls() async {
    final paths = widget.expense.attachmentUrls ?? [];
    if (paths.isEmpty) return;
    setState(() => _loading = true);
    final repo = ref.read(setAllRepositoryProvider);
    for (final path in paths) {
      final url = await repo.generateAttachmentSignedUrl(path);
      if (url != null && mounted) {
        setState(() => _signedUrls[path] = url);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  static const _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'};

  String _ext(String path) => path.split('.').last.toLowerCase();
  bool _isImage(String path) => _imageExts.contains(_ext(path));
  bool _isPdf(String path)   => _ext(path) == 'pdf';

  IconData _iconFor(String path) {
    if (_isImage(path)) return Icons.image_outlined;
    if (_isPdf(path))   return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }

  void _previewFile(String path, String signedUrl) {
    final filename = path.split('/').last;
    if (_isImage(path)) {
      _showImagePreview(filename, signedUrl);
    } else if (_isPdf(path)) {
      _showPdfPreview(filename, signedUrl);
    } else {
      _launchExternal(signedUrl);
    }
  }

  void _showImagePreview(String filename, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(filename,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
          body: InteractiveViewer(
            minScale: 0.5,
            maxScale: 6.0,
            child: Center(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(color: _teal)),
                errorBuilder: (context, error, stack) => const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.white54, size: 64)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Fetches remote bytes using dart:io (no extra package needed).
  Future<Uint8List> _fetchBytes(String url) async {
    final request = await io.HttpClient().getUrl(Uri.parse(url));
    final response = await request.close();
    final chunks = <List<int>>[];
    await for (final chunk in response) {
      chunks.add(chunk);
    }
    return Uint8List.fromList(chunks.expand((c) => c).toList());
  }

  void _showPdfPreview(String filename, String url) {
    final ctrl = PdfControllerPinch(
      document: _fetchBytes(url).then(PdfDocument.openData),
    );
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: const Color(0xFF1E293B),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E293B),
            foregroundColor: Colors.white,
            title: Text(filename,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                ctrl.dispose();
                Navigator.of(ctx).pop();
              },
            ),
          ),
          body: PdfViewPinch(controller: ctrl),
        ),
      ),
    );
  }

  Future<void> _launchExternal(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open attachment')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final paths  = widget.expense.attachmentUrls ?? [];

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attach_file_outlined, size: 16, color: _teal),
              const SizedBox(width: 6),
              Text(
                'Attachments (${paths.length})',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700, fontSize: 12,
                ),
              ),
              if (_loading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          ...paths.map((path) {
            final filename = path.split('/').last;
            final signedUrl = _signedUrls[path];
            return InkWell(
              onTap: signedUrl != null ? () => _previewFile(path, signedUrl) : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    // Thumbnail for images, icon for PDFs/files
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: signedUrl != null && _isImage(path)
                          ? Image.network(
                              signedUrl,
                              width: 52, height: 52,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stack) => Container(
                                width: 52, height: 52,
                                color: _teal.withAlpha(24),
                                child: const Icon(Icons.broken_image_outlined,
                                    size: 22, color: _teal),
                              ),
                            )
                          : Container(
                              width: 52, height: 52,
                              color: _teal.withAlpha(24),
                              child: Icon(_iconFor(path), size: 22, color: _teal),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            filename,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: signedUrl != null
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (signedUrl == null)
                            Text('Loading…',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.onSurfaceVariant,
                                )),
                        ],
                      ),
                    ),
                    if (signedUrl != null)
                      const Icon(Icons.fullscreen, size: 16, color: _teal),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _AnalyticPill extends StatelessWidget {
  const _AnalyticPill({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 9, color: theme.colorScheme.onSurfaceVariant),
          maxLines: 1, overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value, this.mono = false});
  final String label;
  final String value;
  final bool   mono;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface,
              fontFamily: mono ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }
}

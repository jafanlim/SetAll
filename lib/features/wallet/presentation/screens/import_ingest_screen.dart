// setall-ingestion-pipeline: bank statement import → AI classify → per-row review → commit.
// Web path (task 1.1–1.5): file picker via file_picker, extraction + classification via ingest.js.
// Nothing writes to DB until the user approves rows and taps commit.

import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../domain/entities/expense.dart';
import '../../data/ingest_row.dart';
import '../../data/ingest_service.dart';

// ---------------------------------------------------------------------------
// Palette (matches wallet screen)
// ---------------------------------------------------------------------------
const _purple    = Color(0xFF8B5CF6);
const _teal      = Color(0xFF00D9B0);
const _red       = Color(0xFFEF4444);
const _green     = Color(0xFF22C55E);
const _brandOrange = Color(0xFFF97316);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class ImportIngestScreen extends ConsumerStatefulWidget {
  const ImportIngestScreen({super.key});

  @override
  ConsumerState<ImportIngestScreen> createState() => _ImportIngestScreenState();
}

class _ImportIngestScreenState extends ConsumerState<ImportIngestScreen> {
  bool   _loading  = false;
  String _loadMsg  = '';
  String? _error;

  // ── File pick + ingest ───────────────────────────────────────────────────
  Future<void> _pickAndIngest(String format) async {
    HapticUtils.lightTap();
    setState(() { _loading = true; _error = null; _loadMsg = 'ingest.uploading'.tr(); });

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: format == 'csv' ? FileType.custom : FileType.custom,
        allowedExtensions: format == 'csv' ? ['csv'] : ['pdf'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        setState(() { _loading = false; });
        return;
      }

      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        setState(() { _loading = false; _error = 'ingest.error_no_file'.tr(); });
        return;
      }

      final svc = ref.read(ingestServiceProvider);
      setState(() { _loadMsg = 'ingest.classifying'.tr(); });

      List<IngestRow> rows;
      if (format == 'csv') {
        final text = String.fromCharCodes(bytes);
        rows = await svc.ingestCsv(text);
      } else {
        rows = await svc.ingestPdf(bytes);
      }

      if (rows.isEmpty) {
        setState(() { _loading = false; _error = 'ingest.no_rows'.tr(); });
        return;
      }

      // All rows start as approved so user can just reject what they don't want.
      // Run dedupe first: pre-reject and badge rows that already exist in wallet.
      final deduped = await svc.flagDuplicates(rows);
      ref.read(ingestRowsProvider.notifier).setRows(
        deduped.map((r) => r.isDuplicate ? r : r.copyWith(status: IngestRowStatus.approved)).toList(),
      );
      setState(() { _loading = false; });
    } on IngestException catch (e) {
      setState(() { _loading = false; _error = e.message; });
    } catch (e) {
      setState(() { _loading = false; _error = 'ingest.error_server'.tr(namedArgs: {'msg': e.toString()}); });
    }
  }

  // ── Commit approved rows ─────────────────────────────────────────────────
  Future<void> _commit() async {
    final rows = ref.read(ingestRowsProvider);
    final approvedCount = rows.where((r) => r.status == IngestRowStatus.approved).length;
    if (approvedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('ingest.nothing_approved'.tr())),
      );
      return;
    }

    HapticUtils.primaryTap();
    setState(() { _loading = true; _loadMsg = 'ingest.committing'.tr(); });
    try {
      final svc = ref.read(ingestServiceProvider);
      final committed = await svc.commitApproved(rows);
      if (!mounted) return;

      // Invalidate wallet providers so the wallet screen refreshes.
      ref.invalidate(walletEntriesProvider);
      ref.invalidate(walletEntryTotalsProvider);
      ref.invalidate(balanceSummaryProvider);
      ref.read(ingestRowsProvider.notifier).clear();

      HapticUtils.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('ingest.committed'.tr(namedArgs: {'count': committed.toString()})),
          backgroundColor: _green,
        ),
      );
      if (context.mounted) Navigator.of(context).pop();
    } on IngestException catch (e) {
      setState(() { _loading = false; _error = e.message; });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'ingest.error_server'.tr(namedArgs: {'msg': e.toString()});
      });
    }
  }

  // ── Start over ───────────────────────────────────────────────────────────
  void _startOver() {
    ref.read(ingestRowsProvider.notifier).clear();
    setState(() { _error = null; });
  }

  // ── Build ────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows  = ref.watch(ingestRowsProvider);
    final hasRows = rows.isNotEmpty;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'ingest.title'.tr(),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.3),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        actions: hasRows && !_loading
            ? [
                TextButton(
                  onPressed: _startOver,
                  child: Text('ingest.start_over'.tr()),
                ),
              ]
            : null,
      ),
      body: _loading
          ? _buildLoading()
          : hasRows
              ? _buildReviewPane(rows, theme)
              : _buildPickPane(theme),
    );
  }

  // ── Loading overlay ──────────────────────────────────────────────────────
  Widget _buildLoading() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(color: _purple, strokeWidth: 2.5),
        const SizedBox(height: 16),
        Text(_loadMsg, style: const TextStyle(fontSize: 14, color: _purple)),
      ],
    ),
  );

  // ── Pick pane (initial) ──────────────────────────────────────────────────
  Widget _buildPickPane(ThemeData theme) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 32, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.upload_file_outlined, size: 56, color: _purple.withValues(alpha: 0.7)),
          const SizedBox(height: 20),
          Text(
            'ingest.review_title'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800, letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'ingest.review_subtitle'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 40),
          _PickButton(
            icon: Icons.table_chart_outlined,
            color: const Color(0xFF0EA5E9),
            label: 'ingest.pick_csv'.tr(),
            onTap: () => _pickAndIngest('csv'),
          ),
          const SizedBox(height: 14),
          _PickButton(
            icon: Icons.picture_as_pdf_outlined,
            color: _brandOrange,
            label: 'ingest.pick_pdf'.tr(),
            onTap: () => _pickAndIngest('pdf'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _red.withValues(alpha: 0.3)),
              ),
              child: Text(_error!, style: const TextStyle(color: _red, fontSize: 13)),
            ),
          ],
        ],
      ),
    ),
  );

  // ── Review pane ──────────────────────────────────────────────────────────
  Widget _buildReviewPane(List<IngestRow> rows, ThemeData theme) {
    final approvedCount = rows.where((r) => r.status == IngestRowStatus.approved).length;
    final allApproved   = approvedCount == rows.length;

    return Column(
      children: [
        // Header bar
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text(
                'ingest.rows_found'.tr(namedArgs: {'count': rows.length.toString()}),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant, fontSize: 12,
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: allApproved
                    ? null
                    : () { HapticUtils.selection(); ref.read(ingestRowsProvider.notifier).approveAll(); },
                child: Text('ingest.approve_all'.tr(),
                    style: TextStyle(fontSize: 12, color: allApproved ? theme.disabledColor : _teal)),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        // Row list
        Expanded(
          child: ListView.builder(
            itemCount: rows.length,
            itemBuilder: (ctx, i) => _IngestRowTile(
              row: rows[i],
              onToggle: () => ref.read(ingestRowsProvider.notifier).toggleStatus(rows[i].id),
              onEdit:   () => _showEditSheet(rows[i]),
            ),
          ),
        ),
        // Commit bar
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(_error!, style: const TextStyle(color: _red, fontSize: 12)),
          ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: approvedCount > 0 ? _commit : null,
              style: FilledButton.styleFrom(
                backgroundColor: _purple,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.check_circle_outline, size: 18),
              label: Text(
                'ingest.commit'.tr(namedArgs: {'count': approvedCount.toString()}),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Edit bottom sheet ────────────────────────────────────────────────────
  Future<void> _showEditSheet(IngestRow row) async {
    HapticUtils.selection();
    final descCtrl = TextEditingController(text: row.description);
    String category = row.category;
    bool isIncome   = row.isIncome;

    // Build union of fixed + user categories
    final userCats = await ref.read(setAllRepositoryProvider).getUserCategories();
    final allCats  = [
      ...kExpenseCategories,
      ...userCats.map((c) => c['name'] ?? '').where((n) => n.isNotEmpty),
    ];

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('ingest.edit_row_title'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
              const SizedBox(height: 16),
              TextField(
                controller: descCtrl,
                decoration: InputDecoration(
                  labelText: 'ingest.description_label'.tr(),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: allCats.contains(category) ? category : allCats.first,
                decoration: InputDecoration(
                  labelText: 'ingest.category_label'.tr(),
                  border: const OutlineInputBorder(),
                ),
                items: allCats.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) { if (v != null) setSheetState(() => category = v); },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text('ingest.type_label'.tr(),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  ChoiceChip(
                    label: Text('ingest.expense'.tr()),
                    selected: !isIncome,
                    selectedColor: _purple.withValues(alpha: 0.15),
                    onSelected: (_) => setSheetState(() => isIncome = false),
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('ingest.income'.tr()),
                    selected: isIncome,
                    selectedColor: _teal.withValues(alpha: 0.15),
                    onSelected: (_) => setSheetState(() => isIncome = true),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: () {
                  ref.read(ingestRowsProvider.notifier).editRow(
                    row.id,
                    description: descCtrl.text.trim().isEmpty ? row.rawDescription : descCtrl.text.trim(),
                    category:    category,
                    isIncome:    isIncome,
                  );
                  Navigator.of(ctx).pop();
                },
                style: FilledButton.styleFrom(backgroundColor: _purple),
                child: const Text('Save', style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
      ),
    );
    descCtrl.dispose();
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _PickButton extends StatelessWidget {
  const _PickButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final Color    color;
  final String   label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 20),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          border: Border.all(color: color.withValues(alpha: 0.3)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  )),
            ),
            Icon(Icons.chevron_right_rounded, color: color.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}

class _IngestRowTile extends StatelessWidget {
  const _IngestRowTile({
    required this.row,
    required this.onToggle,
    required this.onEdit,
  });
  final IngestRow    row;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final approved = row.status == IngestRowStatus.approved;
    final rejected = row.status == IngestRowStatus.rejected;

    Color statusColor;
    IconData statusIcon;
    if (approved) { statusColor = _teal; statusIcon = Icons.check_circle_rounded; }
    else if (rejected) { statusColor = _red; statusIcon = Icons.cancel_rounded; }
    else { statusColor = theme.colorScheme.onSurfaceVariant; statusIcon = Icons.radio_button_unchecked; }

    return Opacity(
      opacity: rejected ? 0.45 : 1.0,
      child: InkWell(
        onTap: onToggle,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(row.description,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ),
                        if (row.isDuplicate) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: _brandOrange.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'ingest.duplicate'.tr(),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: _brandOrange),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${row.date}  ·  ${row.category}',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${row.isIncome ? '+' : '-'}${row.currency} ${row.amount}',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: row.isIncome ? _teal : theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: onEdit,
                    child: Text('Edit',
                        style: TextStyle(
                          fontSize: 11,
                          color: _purple.withValues(alpha: 0.8),
                          fontWeight: FontWeight.w600,
                        )),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

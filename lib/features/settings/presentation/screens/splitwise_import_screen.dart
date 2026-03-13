import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/repositories/setall_repository.dart';
import '../../../../domain/entities/expense.dart';

const _teal  = Color(0xFF00D9B0);
const _slate = Color(0xFF94A3B8);

// ---------------------------------------------------------------------------
// Parsed row from Splitwise CSV
// ---------------------------------------------------------------------------
class _SplitwiseRow {
  const _SplitwiseRow({
    required this.date,
    required this.description,
    required this.category,
    required this.cost,
    required this.currency,
  });

  final DateTime date;
  final String   description;
  final String   category;
  final Decimal  cost;
  final String   currency;
}

// ---------------------------------------------------------------------------
// SplitwiseImportScreen
// ---------------------------------------------------------------------------
class SplitwiseImportScreen extends ConsumerStatefulWidget {
  const SplitwiseImportScreen({super.key});

  @override
  ConsumerState<SplitwiseImportScreen> createState() => _SplitwiseImportScreenState();
}

class _SplitwiseImportScreenState extends ConsumerState<SplitwiseImportScreen> {
  List<_SplitwiseRow> _rows    = [];
  List<String>        _errors  = [];
  bool _parsing   = false;
  bool _importing = false;
  int  _imported  = 0;
  String? _fileName;

  // ── CSV Parsing ────────────────────────────────────────────────────────────
  Future<void> _pickAndParse() async {
    setState(() { _parsing = true; _rows = []; _errors = []; _fileName = null; });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['csv'],
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) {
        setState(() => _parsing = false);
        return;
      }

      final file = result.files.first;
      setState(() => _fileName = file.name);

      String raw;
      if (kIsWeb) {
        raw = String.fromCharCodes(file.bytes!);
      } else {
        raw = await File(file.path!).readAsString();
      }

      final parsed  = _parseCsv(raw);
      setState(() {
        _rows    = parsed.$1;
        _errors  = parsed.$2;
        _parsing = false;
      });
    } catch (e) {
      setState(() {
        _errors  = ['Failed to read file: ${e.toString()}'];
        _parsing = false;
      });
    }
  }

  // Returns (rows, errors).
  (List<_SplitwiseRow>, List<String>) _parseCsv(String raw) {
    final lines  = raw.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) return ([], ['Empty file']);

    // Find header row — Splitwise exports have: Date,Description,Category,Cost,Currency,...
    int headerIdx = -1;
    List<String> headers = [];
    for (int i = 0; i < lines.length; i++) {
      final cols = _splitCsvLine(lines[i]);
      if (cols.length >= 4) {
        final lower = cols.map((c) => c.toLowerCase().trim()).toList();
        if (lower.contains('date') && lower.contains('description') &&
            lower.contains('cost') && lower.contains('currency')) {
          headerIdx = i;
          headers   = lower;
          break;
        }
      }
    }
    if (headerIdx < 0) {
      return ([], ['Could not find a header row with: Date, Description, Cost, Currency']);
    }

    final dateIdx        = headers.indexOf('date');
    final descIdx        = headers.indexOf('description');
    final catIdx         = headers.indexWhere((h) => h.contains('category'));
    final costIdx        = headers.indexOf('cost');
    final currencyIdx    = headers.indexOf('currency');

    final rows   = <_SplitwiseRow>[];
    final errors = <String>[];

    for (int i = headerIdx + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final cols = _splitCsvLine(line);
      if (cols.length <= costIdx || cols.length <= currencyIdx) continue;

      // Skip "Total balance" / summary rows Splitwise appends at the bottom
      final rawDate = _col(cols, dateIdx);
      if (rawDate.toLowerCase().contains('total') || rawDate.isEmpty) continue;

      // Parse date
      DateTime? date;
      for (final fmt in ['yyyy-MM-dd', 'MM/dd/yyyy', 'dd/MM/yyyy', 'yyyy/MM/dd']) {
        try { date = DateFormat(fmt).parseStrict(rawDate.trim()); break; } catch (_) {}
      }
      if (date == null) {
        errors.add('Row ${i + 1}: unrecognised date "$rawDate" — skipped');
        continue;
      }

      // Parse cost — Splitwise uses negative for expenses paid by you, positive for credits
      final rawCost = _col(cols, costIdx).replaceAll(RegExp(r'[,\s]'), '');
      Decimal? cost;
      try {
        cost = Decimal.parse(rawCost.isEmpty ? '0' : rawCost);
      } catch (_) {
        errors.add('Row ${i + 1}: invalid cost "$rawCost" — skipped');
        continue;
      }
      if (cost == Decimal.zero) continue; // skip zero-cost rows

      final description = _col(cols, descIdx).isEmpty ? 'Imported expense' : _col(cols, descIdx);
      final category    = catIdx >= 0 ? _col(cols, catIdx) : 'General';
      final currency    = _col(cols, currencyIdx).isEmpty ? 'USD' : _col(cols, currencyIdx).toUpperCase();

      rows.add(_SplitwiseRow(
        date:        date,
        description: description,
        category:    category.isEmpty ? 'General' : category,
        cost:        cost.abs(),
        currency:    currency,
      ));
    }

    return (rows, errors);
  }

  String _col(List<String> cols, int idx) =>
      idx >= 0 && idx < cols.length ? cols[idx].trim() : '';

  // Handles quoted CSV fields.
  List<String> _splitCsvLine(String line) {
    final result  = <String>[];
    final buffer  = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    result.add(buffer.toString());
    return result;
  }

  // ── Import ─────────────────────────────────────────────────────────────────
  Future<void> _doImport() async {
    if (_rows.isEmpty) return;
    setState(() { _importing = true; _imported = 0; });
    HapticUtils.primaryTap();

    final repo = ref.read(setAllRepositoryProvider);
    final uid  = await repo.ensureUser();
    if (uid == null) {
      if (mounted) setState(() => _importing = false);
      return;
    }

    int count = 0;
    for (final row in _rows) {
      await repo.addExpense(
        groupId:     null,
        payerId:     uid,
        amount:      row.cost,
        description: row.description,
        currency:    row.currency,
        splitType:   SplitType.even,
        splits:      [SplitInsert(userId: uid, universalUsdOwed: row.cost)],
        category:    _mapCategory(row.category),
        isIncome:    false,
      );
      count++;
      if (mounted) setState(() => _imported = count);
    }

    if (mounted) {
      setState(() => _importing = false);
      ref.invalidate(personalExpensesProvider);
      ref.invalidate(omniActivityProvider);
      ref.invalidate(balanceSummaryProvider);
      ref.invalidate(walletBalanceProvider);
      HapticUtils.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported $count expenses from Splitwise'),
          backgroundColor: _teal.withValues(alpha: 0.9),
        ),
      );
      setState(() { _rows = []; _fileName = null; });
    }
  }

  String _mapCategory(String raw) {
    final lower = raw.toLowerCase();
    if (lower.contains('food') || lower.contains('drink') || lower.contains('dining')) return 'Food & drink';
    if (lower.contains('transport') || lower.contains('uber') || lower.contains('car')) return 'Transport';
    if (lower.contains('entertain') || lower.contains('movie') || lower.contains('fun')) return 'Entertainment';
    if (lower.contains('bill') || lower.contains('util')) return 'Bills & utilities';
    if (lower.contains('shop')) return 'Shopping';
    if (lower.contains('travel') || lower.contains('hotel') || lower.contains('flight')) return 'Travel';
    return raw.isNotEmpty ? raw : 'General';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Import from Splitwise',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── How-to ────────────────────────────────────────────────────
          _InfoBanner(
            icon: Icons.info_outline_rounded,
            body: 'Export your Splitwise data: Account → Export to CSV, then choose the downloaded .csv file below.',
          ),
          const SizedBox(height: 16),

          // ── File picker ───────────────────────────────────────────────
          _picking
              ? const Center(child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(color: _teal)))
              : OutlinedButton.icon(
                  onPressed: _importing ? null : _pickAndParse,
                  icon: const Icon(Icons.upload_file_rounded, color: _teal),
                  label: Text(
                    _fileName ?? 'Choose CSV file',
                    style: const TextStyle(color: _teal, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _teal),
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),

          // ── Parse errors ──────────────────────────────────────────────
          if (_errors.isNotEmpty) ...[
            const SizedBox(height: 12),
            GlassCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 16),
                    const SizedBox(width: 6),
                    Text('${_errors.length} warning${_errors.length == 1 ? '' : 's'}',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.orangeAccent, fontSize: 12)),
                  ]),
                  const SizedBox(height: 6),
                  ..._errors.map((e) => Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(e, style: const TextStyle(fontSize: 11, color: _slate)),
                  )),
                ],
              ),
            ),
          ],

          // ── Preview table ─────────────────────────────────────────────
          if (_rows.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(children: [
              const Icon(Icons.checklist_rounded, color: _teal, size: 18),
              const SizedBox(width: 6),
              Text('${_rows.length} expenses found — review before importing',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 10),
            GlassCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  // Header row
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                    ),
                    child: Row(
                      children: const [
                        Expanded(flex: 2, child: Text('Date', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _slate))),
                        Expanded(flex: 3, child: Text('Description', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _slate))),
                        Expanded(flex: 2, child: Text('Category', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _slate))),
                        Expanded(flex: 2, child: Align(alignment: Alignment.centerRight, child: Text('Amount', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _slate)))),
                      ],
                    ),
                  ),
                  // Data rows (max 50 preview)
                  ...(_rows.take(50).toList().asMap().entries.map((entry) {
                    final idx = entry.key;
                    final row = entry.value;
                    final isLast = idx == (_rows.length > 50 ? 49 : _rows.length - 1);
                    return Column(
                      children: [
                        if (idx > 0) const Divider(height: 1, indent: 14, endIndent: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Row(
                            children: [
                              Expanded(flex: 2, child: Text(
                                DateFormat('dd MMM yy').format(row.date),
                                style: const TextStyle(fontSize: 11),
                              )),
                              Expanded(flex: 3, child: Text(
                                row.description,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                                overflow: TextOverflow.ellipsis,
                              )),
                              Expanded(flex: 2, child: Text(
                                row.category,
                                style: const TextStyle(fontSize: 10, color: _slate),
                                overflow: TextOverflow.ellipsis,
                              )),
                              Expanded(flex: 2, child: Align(
                                alignment: Alignment.centerRight,
                                child: Text(
                                  '${row.currency} ${row.cost.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: _teal,
                                  ),
                                ),
                              )),
                            ],
                          ),
                        ),
                        if (isLast && _rows.length > 50)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '… and ${_rows.length - 50} more',
                              style: const TextStyle(fontSize: 11, color: _slate),
                            ),
                          ),
                      ],
                    );
                  })),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Confirm import button ─────────────────────────────────
            if (_importing) ...[
              Center(
                child: Column(
                  children: [
                    const CircularProgressIndicator(color: _teal),
                    const SizedBox(height: 8),
                    Text('Importing $_imported / ${_rows.length}…',
                        style: const TextStyle(fontSize: 13, color: _slate)),
                  ],
                ),
              ),
            ] else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _doImport,
                  icon: const Icon(Icons.check_circle_outline, size: 18),
                  label: Text(
                    'Import ${_rows.length} expense${_rows.length == 1 ? '' : 's'} into Wallet',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
          ],

          if (_rows.isEmpty && !_parsing && _fileName != null && _errors.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 20),
              child: Center(
                child: Text('No importable rows found in $_fileName',
                    style: const TextStyle(color: _slate, fontSize: 13)),
              ),
            ),

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  bool get _picking => _parsing;
}

// ---------------------------------------------------------------------------
// Info banner
// ---------------------------------------------------------------------------
class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.body});
  final IconData icon;
  final String body;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0x1400D9B0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x3300D9B0)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _teal, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(body, style: const TextStyle(fontSize: 12, color: _slate)),
            ),
          ],
        ),
      );
}

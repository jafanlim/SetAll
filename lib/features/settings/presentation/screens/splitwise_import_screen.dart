import 'dart:io' if (dart.library.html) '../../../../core/stubs/io_stub.dart';

import 'package:decimal/decimal.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/utils/split_engine.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/group_model.dart';
import '../../../../data/models/profile_model.dart';
import '../../../../data/repositories/setall_repository.dart';
import '../../../../domain/entities/expense.dart';

const _teal  = Color(0xFF00D9B0);
const _slate = Color(0xFF94A3B8);

enum _Destination { wallet, group }

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
    required this.csvNames,
  });

  final DateTime     date;
  final String       description;
  final String       category;
  final Decimal      cost;
  final String       currency;
  final List<String> csvNames;
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
  // Step 0=destination, 1=pick file, 2=map names, 3=importing
  int _step = 0;

  _Destination       _destination  = _Destination.wallet;
  GroupModel?        _selectedGroup;
  List<ProfileModel> _groupMembers = [];

  List<_SplitwiseRow>        _rows    = [];
  List<String>               _errors  = [];
  bool    _parsing   = false;
  bool    _importing = false;
  int     _imported  = 0;
  String? _fileName;

  List<String>               _csvNames = [];
  Map<String, ProfileModel?> _nameMap  = {};

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

      final parsed   = _parseCsv(raw);
      final rows     = parsed.$1;
      final errors   = parsed.$2;

      // Collect unique names across all rows
      final nameSet = <String>{};
      for (final r in rows) { nameSet.addAll(r.csvNames); }
      final csvNames = nameSet.toList()..sort();

      // Auto-map by name similarity
      final autoMap = <String, ProfileModel?>{};
      for (final n in csvNames) { autoMap[n] = _tryAutoMap(n); }

      setState(() {
        _rows     = rows;
        _errors   = errors;
        _parsing  = false;
        _csvNames = csvNames;
        _nameMap  = autoMap;
      });

      if (_destination == _Destination.group && csvNames.isNotEmpty) {
        setState(() => _step = 2);
      }
    } catch (e) {
      setState(() {
        _errors  = ['Failed to read file: ${e.toString()}'];
        _parsing = false;
      });
    }
  }

  ProfileModel? _tryAutoMap(String csvName) {
    final lower = csvName.toLowerCase();
    for (final m in _groupMembers) {
      if (m.name.toLowerCase() == lower) return m;
      if ((m.nickname ?? '').toLowerCase() == lower) return m;
      final parts  = lower.split(' ');
      final mParts = m.name.toLowerCase().split(' ');
      if (parts.isNotEmpty && mParts.isNotEmpty && parts.first == mParts.first) return m;
    }
    return null;
  }

  // Returns (rows, errors).
  (List<_SplitwiseRow>, List<String>) _parseCsv(String raw) {
    final lines = raw.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) return ([], ['Empty file']);

    int headerIdx = -1;
    List<String> headers         = [];
    List<String> originalHeaders = [];
    for (int i = 0; i < lines.length; i++) {
      final cols = _splitCsvLine(lines[i]);
      if (cols.length >= 4) {
        final lower = cols.map((c) => c.toLowerCase().trim()).toList();
        if (lower.contains('date') && lower.contains('description') &&
            lower.contains('cost') && lower.contains('currency')) {
          headerIdx       = i;
          headers         = lower;
          originalHeaders = cols.map((c) => c.trim()).toList();
          break;
        }
      }
    }
    if (headerIdx < 0) {
      return ([], ['Could not find a header row with: Date, Description, Cost, Currency']);
    }

    final dateIdx     = headers.indexOf('date');
    final descIdx     = headers.indexOf('description');
    final catIdx      = headers.indexWhere((h) => h.contains('category'));
    final costIdx     = headers.indexOf('cost');
    final currencyIdx = headers.indexOf('currency');

    // Detect person-amount columns: any column whose header doesn't match
    // known Splitwise fixed fields is treated as a participant name.
    const fixedCols = {
      'date', 'description', 'category', 'cost', 'currency',
      'balance', 'id', 'notes', 'for you', 'your share', 'net balance',
    };
    final personCols = <int, String>{};
    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].trim();
      if (h.isNotEmpty && !fixedCols.any((f) => h.contains(f))) {
        personCols[i] = originalHeaders[i];
      }
    }

    final rows   = <_SplitwiseRow>[];
    final errors = <String>[];

    for (int i = headerIdx + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final cols = _splitCsvLine(line);
      if (cols.length <= costIdx || cols.length <= currencyIdx) continue;

      final rawDate = _col(cols, dateIdx);
      if (rawDate.toLowerCase().contains('total') || rawDate.isEmpty) continue;

      DateTime? date;
      for (final fmt in ['yyyy-MM-dd', 'MM/dd/yyyy', 'dd/MM/yyyy', 'yyyy/MM/dd']) {
        try { date = DateFormat(fmt).parseStrict(rawDate.trim()); break; } catch (_) {}
      }
      if (date == null) {
        errors.add('Row ${i + 1}: unrecognised date "$rawDate" — skipped');
        continue;
      }

      final rawCost = _col(cols, costIdx).replaceAll(RegExp(r'[,\s]'), '');
      Decimal? cost;
      try {
        cost = Decimal.parse(rawCost.isEmpty ? '0' : rawCost);
      } catch (_) {
        errors.add('Row ${i + 1}: invalid cost "$rawCost" — skipped');
        continue;
      }
      if (cost == Decimal.zero) continue;

      final description = _col(cols, descIdx).isEmpty ? 'Imported expense' : _col(cols, descIdx);
      final category    = catIdx >= 0 ? _col(cols, catIdx) : 'General';
      final currency    = _col(cols, currencyIdx).isEmpty ? 'USD' : _col(cols, currencyIdx).toUpperCase();

      // Names that have a non-zero value in this row
      final rowNames = <String>[];
      for (final entry in personCols.entries) {
        final val = _col(cols, entry.key).replaceAll(RegExp(r'[,\s]'), '');
        if (val.isNotEmpty && val != '0' && val != '0.00') {
          rowNames.add(entry.value);
        }
      }

      rows.add(_SplitwiseRow(
        date:        date,
        description: description,
        category:    category.isEmpty ? 'General' : category,
        cost:        cost.abs(),
        currency:    currency,
        csvNames:    rowNames,
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
    setState(() { _importing = true; _imported = 0; _step = 3; });
    HapticUtils.primaryTap();

    final repo = ref.read(setAllRepositoryProvider);
    final uid  = await repo.ensureUser();
    if (uid == null) {
      if (mounted) setState(() { _importing = false; _step = 1; });
      return;
    }

    int count = 0;

    if (_destination == _Destination.wallet) {
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
        ref.invalidate(personalExpensesProvider);
        ref.invalidate(omniActivityProvider);
        ref.invalidate(balanceSummaryProvider);
        ref.invalidate(walletBalanceProvider);
      }
    } else {
      final groupId = _selectedGroup!.id;
      for (final row in _rows) {
        // Build participant list: mapped members + always include payer
        final participantIds = <String>{};
        participantIds.add(uid);
        for (final csvName in row.csvNames) {
          final profile = _nameMap[csvName];
          if (profile != null) participantIds.add(profile.id);
        }
        final ids = participantIds.toList();

        // Use SplitEngine for precise even splits with remainder on payer
        final splitResults = SplitEngine.splitEven(
          total:          row.cost,
          participantIds: ids,
          payerId:        uid,
        );
        final splits = splitResults
            .map((s) => SplitInsert(userId: s.userId, universalUsdOwed: s.amountOwed))
            .toList();

        await repo.addExpense(
          groupId:     groupId,
          payerId:     uid,
          amount:      row.cost,
          description: row.description,
          currency:    row.currency,
          splitType:   SplitType.even,
          splits:      splits,
          category:    _mapCategory(row.category),
          isIncome:    false,
        );
        count++;
        if (mounted) setState(() => _imported = count);
      }
      if (mounted) {
        ref.invalidate(myGroupsProvider);
        ref.invalidate(balanceSummaryProvider);
        ref.invalidate(recentExpensesProvider);
      }
    }

    if (mounted) {
      HapticUtils.success();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Imported $count expense${count == 1 ? '' : 's'}'),
          backgroundColor: _teal.withValues(alpha: 0.9),
        ),
      );
      setState(() {
        _importing = false; _step = 0;
        _rows = []; _fileName = null; _csvNames = [];
        _nameMap = {}; _selectedGroup = null;
        _destination = _Destination.wallet;
      });
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

  // ── Build ──────────────────────────────────────────────────────────────────
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
        leading: _step > 0 && !_importing
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  if (_step == 2) {
                    _step = 1;
                  } else {
                    _step -= 1;
                    _rows = []; _errors = []; _fileName = null;
                  }
                }),
              )
            : null,
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: KeyedSubtree(key: ValueKey(_step), child: _buildStep(theme)),
      ),
    );
  }

  Widget _buildStep(ThemeData theme) {
    switch (_step) {
      case 0:  return _buildDestinationStep(theme);
      case 1:  return _buildPickStep(theme);
      case 2:  return _buildMappingStep(theme);
      default: return _buildImportingStep();
    }
  }

  // ── Step 0: Choose destination ─────────────────────────────────────────────
  Widget _buildDestinationStep(ThemeData theme) {
    final groupsAsync = ref.watch(myGroupsProvider);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _InfoBanner(
          icon: Icons.info_outline_rounded,
          body: 'Export your Splitwise data: Account → Export to CSV. Choose where to import below.',
        ),
        const SizedBox(height: 24),
        Text('Import to',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: _slate)),
        const SizedBox(height: 10),
        _DestinationTile(
          icon: Icons.account_balance_wallet_outlined,
          title: 'Personal Wallet',
          subtitle: 'All expenses go to your wallet',
          selected: _destination == _Destination.wallet,
          onTap: () => setState(() { _destination = _Destination.wallet; _selectedGroup = null; }),
        ),
        const SizedBox(height: 10),
        _DestinationTile(
          icon: Icons.group_outlined,
          title: 'Shared Group',
          subtitle: 'Map CSV names to group members and split expenses',
          selected: _destination == _Destination.group,
          onTap: () => setState(() { _destination = _Destination.group; }),
        ),
        if (_destination == _Destination.group) ...[
          const SizedBox(height: 14),
          groupsAsync.when(
            data: (groups) {
              final normal = groups.where((g) => g.type.name == 'normal').toList();
              if (normal.isEmpty) {
                return const _InfoBanner(
                  icon: Icons.warning_amber_rounded,
                  body: 'No shared groups found. Create a group first.',
                );
              }
              return GlassCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: normal.asMap().entries.map((e) {
                    final i = e.key; final g = e.value;
                    final sel = _selectedGroup?.id == g.id;
                    return Column(children: [
                      if (i > 0) const Divider(height: 1, indent: 56),
                      ListTile(
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: _teal.withValues(alpha: sel ? 0.3 : 0.1),
                          child: const Icon(Icons.group, size: 16, color: _teal),
                        ),
                        title: Text(g.name,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        trailing: sel
                            ? const Icon(Icons.check_circle, color: _teal, size: 20)
                            : const Icon(Icons.radio_button_unchecked, color: _slate, size: 20),
                        onTap: () async {
                          setState(() => _selectedGroup = g);
                          final members = await ref
                              .read(setAllRepositoryProvider)
                              .getGroupMembers(g.id);
                          if (mounted) setState(() => _groupMembers = members);
                        },
                      ),
                    ]);
                  }).toList(),
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator(color: _teal)),
            error: (_, e2) => const _InfoBanner(
                icon: Icons.error_outline, body: 'Could not load groups'),
          ),
        ],
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: (_destination == _Destination.group && _selectedGroup == null)
                ? null
                : () => setState(() => _step = 1),
            style: FilledButton.styleFrom(
              backgroundColor: _teal,
              foregroundColor: Colors.black,
              disabledBackgroundColor: _teal.withValues(alpha: 0.3),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              _destination == _Destination.group && _selectedGroup != null
                  ? 'Continue with "${_selectedGroup!.name}"'
                  : 'Continue',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  // ── Step 1: Pick file + preview ────────────────────────────────────────────
  Widget _buildPickStep(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _InfoBanner(
          icon: Icons.info_outline_rounded,
          body: _destination == _Destination.group
              ? 'Choose your Splitwise CSV. Names in the file will be mapped to group members next.'
              : 'Choose your Splitwise CSV export file.',
        ),
        const SizedBox(height: 16),
        _parsing
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
        if (_errors.isNotEmpty) ...[
          const SizedBox(height: 12),
          _ErrorsCard(errors: _errors),
        ],
        if (_rows.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(children: [
            const Icon(Icons.checklist_rounded, color: _teal, size: 18),
            const SizedBox(width: 6),
            Text('${_rows.length} expenses found',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 10),
          _PreviewTable(rows: _rows, theme: theme),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _destination == _Destination.group && _csvNames.isNotEmpty
                  ? () => setState(() => _step = 2)
                  : _doImport,
              icon: Icon(
                _destination == _Destination.group && _csvNames.isNotEmpty
                    ? Icons.arrow_forward : Icons.check_circle_outline,
                size: 18,
              ),
              label: Text(
                _destination == _Destination.group && _csvNames.isNotEmpty
                    ? 'Map Members (${_csvNames.length} name${_csvNames.length == 1 ? '' : 's'} found)'
                    : 'Import ${_rows.length} expense${_rows.length == 1 ? '' : 's'}'
                      '${_destination == _Destination.group ? ' into ${_selectedGroup!.name}' : ' into Wallet'}',
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
    );
  }

  // ── Step 2: Map CSV names → members ───────────────────────────────────────
  Widget _buildMappingStep(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        _InfoBanner(
          icon: Icons.people_alt_outlined,
          body: 'Match each CSV name to a member of "${_selectedGroup!.name}". '
              'Unmapped names are excluded from splits.',
        ),
        const SizedBox(height: 16),
        Text('${_csvNames.length} name${_csvNames.length == 1 ? '' : 's'} found in CSV',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        GlassCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: _csvNames.asMap().entries.map((e) {
              final i = e.key; final csvName = e.value;
              return Column(children: [
                if (i > 0) const Divider(height: 1, indent: 16, endIndent: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(csvName,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                            Text('from CSV',
                                style: TextStyle(fontSize: 11,
                                    color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward, size: 14, color: _slate),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _MemberDropdown(
                          members:  _groupMembers,
                          selected: _nameMap[csvName],
                          onChanged: (m) => setState(() => _nameMap[csvName] = m),
                        ),
                      ),
                    ],
                  ),
                ),
              ]);
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tip: leave unmapped to exclude that person from splits.',
          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _doImport,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: Text(
              'Import ${_rows.length} expense${_rows.length == 1 ? '' : 's'} into ${_selectedGroup!.name}',
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
        const SizedBox(height: 40),
      ],
    );
  }

  // ── Step 3: Importing progress ─────────────────────────────────────────────
  Widget _buildImportingStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: _teal),
            const SizedBox(height: 20),
            Text('Importing $_imported / ${_rows.length}…',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              _destination == _Destination.group
                  ? 'Adding to ${_selectedGroup!.name}'
                  : 'Adding to Personal Wallet',
              style: const TextStyle(fontSize: 13, color: _slate),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Preview table
// ---------------------------------------------------------------------------
class _PreviewTable extends StatelessWidget {
  const _PreviewTable({required this.rows, required this.theme});
  final List<_SplitwiseRow> rows;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('Date',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _slate))),
                Expanded(flex: 3, child: Text('Description',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _slate))),
                Expanded(flex: 2, child: Text('Category',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _slate))),
                Expanded(flex: 2, child: Align(alignment: Alignment.centerRight,
                    child: Text('Amount',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _slate)))),
              ],
            ),
          ),
          ...rows.take(50).toList().asMap().entries.map((entry) {
            final idx  = entry.key;
            final row  = entry.value;
            final isLast = idx == (rows.length > 50 ? 49 : rows.length - 1);
            return Column(children: [
              if (idx > 0) const Divider(height: 1, indent: 14, endIndent: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: Row(children: [
                  Expanded(flex: 2, child: Text(
                      DateFormat('dd MMM yy').format(row.date),
                      style: const TextStyle(fontSize: 11))),
                  Expanded(flex: 3, child: Text(row.description,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis)),
                  Expanded(flex: 2, child: Text(row.category,
                      style: const TextStyle(fontSize: 10, color: _slate),
                      overflow: TextOverflow.ellipsis)),
                  Expanded(flex: 2, child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('${row.currency} ${row.cost.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _teal)),
                  )),
                ]),
              ),
              if (isLast && rows.length > 50)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text('… and ${rows.length - 50} more',
                      style: const TextStyle(fontSize: 11, color: _slate)),
                ),
            ]);
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Errors card
// ---------------------------------------------------------------------------
class _ErrorsCard extends StatelessWidget {
  const _ErrorsCard({required this.errors});
  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 16),
            const SizedBox(width: 6),
            Text('${errors.length} warning${errors.length == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.w700,
                    color: Colors.orangeAccent, fontSize: 12)),
          ]),
          const SizedBox(height: 6),
          ...errors.map((e) => Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(e, style: const TextStyle(fontSize: 11, color: _slate)),
          )),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Destination tile
// ---------------------------------------------------------------------------
class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });
  final IconData     icon;
  final String       title;
  final String       subtitle;
  final bool         selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? _teal.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? _teal : _slate.withValues(alpha: 0.3),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? _teal : _slate, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13,
                          color: selected ? _teal : null)),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 11, color: _slate)),
                ],
              ),
            ),
            if (selected) const Icon(Icons.check_circle, color: _teal, size: 20),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Member dropdown for name mapping
// ---------------------------------------------------------------------------
class _MemberDropdown extends StatelessWidget {
  const _MemberDropdown({
    required this.members,
    required this.selected,
    required this.onChanged,
  });
  final List<ProfileModel>         members;
  final ProfileModel?               selected;
  final ValueChanged<ProfileModel?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<ProfileModel?>(
        value: selected,
        isExpanded: true,
        hint: const Text('— Skip —', style: TextStyle(fontSize: 12, color: _slate)),
        style: const TextStyle(fontSize: 12),
        items: [
          const DropdownMenuItem<ProfileModel?>(
            value: null,
            child: Text('— Skip —', style: TextStyle(fontSize: 12, color: _slate)),
          ),
          ...members.map((m) => DropdownMenuItem<ProfileModel?>(
            value: m,
            child: Text(
              m.nickname?.isNotEmpty == true ? '${m.name} (${m.nickname})' : m.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          )),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info banner
// ---------------------------------------------------------------------------
class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.body});
  final IconData icon;
  final String   body;

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

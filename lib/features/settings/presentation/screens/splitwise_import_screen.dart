import 'dart:io' if (dart.library.html) '../../../../core/stubs/io_stub.dart';

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/services/csv_adapter.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/group_model.dart';
import '../../../../data/models/profile_model.dart';
import '../../../../data/models/wallet_entry_model.dart';
import '../../../../data/repositories/setall_repository.dart';
import '../../../../domain/entities/expense.dart';

const _teal  = Color(0xFF00D9B0);
const _slate = Color(0xFF94A3B8);

enum _Destination { wallet, group }

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

  List<SplitwiseRow>         _rows    = [];
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

      final parsed   = CsvAdapter.parse(raw);
      final rows     = parsed.rows;
      final errors   = parsed.errors;

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
        await repo.upsertWalletEntry(
          WalletEntryModel(
            id:          const Uuid().v4(),
            userId:      uid,
            amount:      row.cost.toString(),
            description: row.description,
            category:    _mapCategory(row.category),
            currency:    row.currency,
            isIncome:    row.isIncome,
            createdAt:   row.date.toUtc().toIso8601String(),
          ),
        );
        count++;
        if (mounted) setState(() => _imported = count);
      }
      if (mounted) {
        ref.invalidate(walletEntriesProvider);
        ref.invalidate(walletEntryTotalsProvider);
        ref.invalidate(omniActivityProvider);
        ref.invalidate(balanceSummaryProvider);
        ref.invalidate(walletBalanceProvider);
      }
    } else {
      final groupId = _selectedGroup!.id;
      for (final row in _rows) {
        // ── Determine payer ──────────────────────────────────────────────────
        // Positive CSV column = that person paid the full cost.
        // If payer maps to a known member use their id, else fall back to uid.
        String payerId = uid;
        if (row.payerCsvName != null) {
          final p = _nameMap[row.payerCsvName!];
          if (p != null) payerId = p.id;
        }

        // ── Build exact splits from CSV amounts ──────────────────────────────
        // |negative amount| = that person's share (what they owe the payer).
        // Payer's share = cost − Σ|negative amounts|.
        final splits = <SplitInsert>[];
        Decimal sumOwed = Decimal.zero;
        for (final entry in row.personAmounts.entries) {
          if (entry.value >= Decimal.zero) continue; // skip payer column here
          final profile = _nameMap[entry.key];
          if (profile == null) continue;
          final share = entry.value.abs();
          splits.add(SplitInsert(userId: profile.id, universalUsdOwed: share));
          sumOwed += share;
        }
        // Add payer's own share (remainder after others' shares).
        final payerShare = row.cost - sumOwed;
        if (payerShare > Decimal.zero) {
          splits.add(SplitInsert(userId: payerId, universalUsdOwed: payerShare));
        }
        // Fall back to full cost on payer if no splits were produced.
        if (splits.isEmpty) {
          splits.add(SplitInsert(userId: payerId, universalUsdOwed: row.cost));
        }

        await repo.addExpense(
          groupId:     groupId,
          payerId:     payerId,
          amount:      row.cost,
          description: row.description,
          currency:    row.currency,
          splitType:   SplitType.manual,
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
          content: Text('settings_ext.csv_imported_ok'.tr(namedArgs: {'count': count.toString()})),
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
        title: Text('settings_ext.csv_title'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
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
          body: 'settings_ext.csv_info_splitwise'.tr(),
        ),
        const SizedBox(height: 24),
        Text('settings_ext.csv_import_to'.tr(),
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700, color: _slate)),
        const SizedBox(height: 10),
        _DestinationTile(
          icon: Icons.account_balance_wallet_outlined,
          title: 'settings_ext.csv_dest_wallet'.tr(),
          subtitle: 'settings_ext.csv_dest_wallet_sub'.tr(),
          selected: _destination == _Destination.wallet,
          onTap: () => setState(() { _destination = _Destination.wallet; _selectedGroup = null; }),
        ),
        const SizedBox(height: 10),
        _DestinationTile(
          icon: Icons.group_outlined,
          title: 'settings_ext.csv_dest_group'.tr(),
          subtitle: 'settings_ext.csv_dest_group_sub'.tr(),
          selected: _destination == _Destination.group,
          onTap: () => setState(() { _destination = _Destination.group; }),
        ),
        if (_destination == _Destination.group) ...[
          const SizedBox(height: 14),
          groupsAsync.when(
            data: (groups) {
              final normal = groups.where((g) => g.type.name == 'normal').toList();
              if (normal.isEmpty) {
                return _InfoBanner(
                  icon: Icons.warning_amber_rounded,
                  body: 'settings_ext.csv_no_groups'.tr(),
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
            error: (_, e2) => _InfoBanner(
                icon: Icons.error_outline, body: 'settings_ext.csv_load_groups_error'.tr()),
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
                  ? 'settings_ext.csv_continue_with'.tr(namedArgs: {'name': _selectedGroup!.name})
                  : 'settings_ext.csv_continue'.tr(),
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
              ? 'settings_ext.csv_info_group'.tr()
              : 'settings_ext.csv_info_wallet'.tr(),
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
                  _fileName ?? 'settings_ext.csv_choose_file'.tr(),
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
            Text('settings_ext.csv_rows_found'.tr(namedArgs: {'count': _rows.length.toString()}),
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
                    ? (_csvNames.length == 1
                        ? 'settings_ext.csv_map_members'.tr(namedArgs: {'count': _csvNames.length.toString()})
                        : 'settings_ext.csv_map_members_plural'.tr(namedArgs: {'count': _csvNames.length.toString()}))
                    : 'settings_ext.csv_import_btn'.tr(namedArgs: {
                        'count': _rows.length.toString(),
                        'type': 'settings_ext.csv_import_entries'.tr(),
                        'dest': _destination == _Destination.group ? _selectedGroup!.name : 'settings_ext.csv_dest_wallet'.tr(),
                      }),
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
              child: Text('settings_ext.csv_no_rows'.tr(namedArgs: {'file': _fileName ?? ''}),
                  // ignore: avoid_redundant_argument_values
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
          body: 'settings_ext.csv_map_title'.tr(namedArgs: {'group': _selectedGroup!.name}),
        ),
        const SizedBox(height: 16),
        Text(_csvNames.length == 1
            ? 'settings_ext.csv_names_found'.tr(namedArgs: {'count': _csvNames.length.toString()})
            : 'settings_ext.csv_names_found_plural'.tr(namedArgs: {'count': _csvNames.length.toString()}),
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
                            Text('settings_ext.csv_from_csv'.tr(),
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
          'settings_ext.csv_map_tip'.tr(),
          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _doImport,
            icon: const Icon(Icons.check_circle_outline, size: 18),
            label: Text(
              'settings_ext.csv_import_group_btn'.tr(namedArgs: {'count': _rows.length.toString(), 'group': _selectedGroup!.name}),
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
            Text('settings_ext.csv_importing'.tr(namedArgs: {'done': _imported.toString(), 'total': _rows.length.toString()}),
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              _destination == _Destination.group
                  ? 'settings_ext.csv_adding_to_group'.tr(namedArgs: {'group': _selectedGroup!.name})
                  : 'settings_ext.csv_adding_to_wallet'.tr(),
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
  final List<SplitwiseRow> rows;
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
            child: Row(
              children: [
                Expanded(flex: 2, child: Text('settings_ext.csv_col_date'.tr(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _slate))),
                Expanded(flex: 3, child: Text('settings_ext.csv_col_description'.tr(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _slate))),
                Expanded(flex: 2, child: Text('settings_ext.csv_col_category'.tr(),
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _slate))),
                Expanded(flex: 2, child: Align(alignment: Alignment.centerRight,
                    child: Text('settings_ext.csv_col_amount'.tr(),
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: _slate)))),
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
                  child: Text('settings_ext.csv_more_rows'.tr(namedArgs: {'count': (rows.length - 50).toString()}),
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
            Text(errors.length == 1
                ? 'settings_ext.csv_warnings'.tr(namedArgs: {'count': errors.length.toString()})
                : 'settings_ext.csv_warnings_plural'.tr(namedArgs: {'count': errors.length.toString()}),
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
        hint: Text('settings_ext.csv_skip'.tr(), style: const TextStyle(fontSize: 12, color: _slate)),
        style: const TextStyle(fontSize: 12),
        items: [
          DropdownMenuItem<ProfileModel?>(
            value: null,
            child: Text('settings_ext.csv_skip'.tr(), style: const TextStyle(fontSize: 12, color: _slate)),
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

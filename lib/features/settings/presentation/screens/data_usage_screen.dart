import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show Share, XFile;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../data/local/local_database.dart';
import '../../../../core/providers/setall_providers.dart';
import '../../../../core/widgets/glass_card.dart';

const _teal = Color(0xFF14B8A6);

class DataUsageScreen extends ConsumerStatefulWidget {
  const DataUsageScreen({super.key});

  @override
  ConsumerState<DataUsageScreen> createState() => _DataUsageScreenState();
}

class _DataUsageScreenState extends ConsumerState<DataUsageScreen> {
  // Local counts
  int _localWallet   = 0;
  int _localExpenses = 0;
  int _localGroups   = 0;
  int _localChats    = 0;

  // Cloud counts
  int? _cloudWallet;
  int? _cloudExpenses;
  int? _cloudGroups;

  bool _cloudLoading = true;
  bool _exporting    = false;

  @override
  void initState() {
    super.initState();
    _loadLocal();
    _loadCloud();
  }

  Future<void> _loadLocal() async {
    final db = LocalDatabase.db;
    final wallet   = await db.rawQuery('SELECT COUNT(*) as c FROM wallet_entries WHERE is_deleted = 0');
    final expenses = await db.rawQuery('SELECT COUNT(*) as c FROM expenses WHERE is_deleted = 0');
    final groups   = await db.rawQuery('SELECT COUNT(*) as c FROM groups WHERE is_deleted = 0');
    final chats    = await db.rawQuery('SELECT COUNT(DISTINCT session_id) as c FROM ai_chat_messages');
    if (!mounted) return;
    setState(() {
      _localWallet   = (wallet.first['c']   as int?) ?? 0;
      _localExpenses = (expenses.first['c'] as int?) ?? 0;
      _localGroups   = (groups.first['c']   as int?) ?? 0;
      _localChats    = (chats.first['c']    as int?) ?? 0;
    });
  }

  Future<void> _loadCloud() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) { setState(() => _cloudLoading = false); return; }

      final wallet   = await client.from('wallet_entries').select('id').eq('user_id', uid).eq('is_deleted', false);
      final expenses = await client.from('expenses').select('id').eq('payer_id', uid);
      final groups   = await client.from('groups').select('id').eq('creator_id', uid);

      if (!mounted) return;
      setState(() {
        _cloudWallet   = (wallet as List).length;
        _cloudExpenses = (expenses as List).length;
        _cloudGroups   = (groups as List).length;
        _cloudLoading  = false;
      });
    } catch (_) {
      if (mounted) setState(() => _cloudLoading = false);
    }
  }

  Future<void> _exportJson() async {
    setState(() => _exporting = true);
    try {
      final repo   = ref.read(setAllRepositoryProvider);
      final client = Supabase.instance.client;
      final uid    = client.auth.currentUser?.id ?? '';

      final profile       = await repo.getCurrentUserProfile();
      final walletEntries = await repo.getWalletEntries();
      final memberships   = await client.from('group_members').select().eq('user_id', uid);
      final groupExpenses = await client.from('expenses').select().eq('payer_id', uid);
      final settlements   = await client
          .from('settlements')
          .select()
          .or('from_user_id.eq.$uid,to_user_id.eq.$uid');

      final data = {
        'exported_at': DateTime.now().toUtc().toIso8601String(),
        'account': {
          'id':    uid,
          'email': client.auth.currentUser?.email,
          'name':  profile?.name,
          'currency': profile?.defaultCurrency,
        },
        'wallet_entries': walletEntries.map((e) => e.toJson()).toList(),
        'group_memberships': memberships,
        'group_expenses': groupExpenses,
        'settlements': settlements,
      };

      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/setall_export.json');
      await file.writeAsString(const JsonEncoder.withIndent('  ').convert(data), flush: true);

      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'SetAll Data Export',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Data & Privacy',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        children: [
          // ── Local data ────────────────────────────────────────────────
          _SectionHeader(label: 'LOCAL DATA', theme: theme),
          const SizedBox(height: 8),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _CountTile(icon: Icons.account_balance_wallet_outlined, iconColor: _teal,
                    label: 'Wallet entries', count: _localWallet),
                const Divider(height: 1, indent: 56),
                _CountTile(icon: Icons.receipt_long_outlined, iconColor: const Color(0xFF8B5CF6),
                    label: 'Group expenses', count: _localExpenses),
                const Divider(height: 1, indent: 56),
                _CountTile(icon: Icons.group_outlined, iconColor: const Color(0xFF0EA5E9),
                    label: 'Groups', count: _localGroups),
                const Divider(height: 1, indent: 56),
                _CountTile(icon: Icons.chat_bubble_outline, iconColor: const Color(0xFFF59E0B),
                    label: 'AI chat sessions', count: _localChats),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Cloud data ────────────────────────────────────────────────
          _SectionHeader(label: 'CLOUD DATA', theme: theme),
          const SizedBox(height: 8),
          GlassCard(
            padding: EdgeInsets.zero,
            child: _cloudLoading
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator(color: _teal, strokeWidth: 2)),
                  )
                : Column(
                    children: [
                      _CountTile(icon: Icons.cloud_outlined, iconColor: _teal,
                          label: 'Wallet entries (synced)', count: _cloudWallet ?? 0),
                      const Divider(height: 1, indent: 56),
                      _CountTile(icon: Icons.cloud_outlined, iconColor: const Color(0xFF8B5CF6),
                          label: 'Group expenses (synced)', count: _cloudExpenses ?? 0),
                      const Divider(height: 1, indent: 56),
                      _CountTile(icon: Icons.cloud_outlined, iconColor: const Color(0xFF0EA5E9),
                          label: 'Groups created', count: _cloudGroups ?? 0),
                    ],
                  ),
          ),

          const SizedBox(height: 32),

          // ── Actions ───────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _exporting
                  ? const SizedBox(width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.download_outlined, size: 18),
              label: const Text('Export My Data (JSON)'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _exporting ? null : _exportJson,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Privacy Policy ↗'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _teal,
                side: const BorderSide(color: _teal),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => launchUrl(Uri.parse('https://setall.app/privacy'),
                  mode: LaunchMode.externalApplication),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.theme});
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, bottom: 2),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

class _CountTile extends StatelessWidget {
  const _CountTile({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.count,
  });
  final IconData icon;
  final Color    iconColor;
  final String   label;
  final int      count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Container(
        width: 36, height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      trailing: Text(
        count.toString(),
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }
}

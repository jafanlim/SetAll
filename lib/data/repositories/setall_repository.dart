import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../domain/services/settlement_engine.dart';
import '../../domain/entities/activity_event.dart';
import '../../domain/entities/expense.dart';
import '../local/local_database.dart';
import '../models/expense_model.dart';
import '../models/group_model.dart';
import '../models/profile_model.dart';
import '../models/split_model.dart';
import '../../core/services/currency_service.dart';

const String _deviceUserIdKey = 'device_user_id';
/// Thrown when [SetAllRepository.createDirectGroup] cannot find a user with
/// the given email address in the Supabase auth system.
class DirectGroupUserNotFoundException implements Exception {
  const DirectGroupUserNotFoundException();

  @override
  String toString() => 'DirectGroupUserNotFoundException: email not found';
}

// ---------------------------------------------------------------------------
// Data transfer objects
// ---------------------------------------------------------------------------

/// Balance summary for the current user (always in USD by default in service).
class BalanceSummary {
  const BalanceSummary({
    this.youAreOwed = '0',
    this.youOwe = '0',
    this.currency = 'USD',
  });

  final String youAreOwed;
  final String youOwe;
  final String currency;
}

  class SplitInsert {
    final String userId;
    final Decimal universalUsdOwed;
    const SplitInsert({required this.userId, required this.universalUsdOwed});
  }
  /// One entry used by [BalanceService] to compute totals.
  class BalanceEntry {
    const BalanceEntry({
      required this.amount,
      required this.currency,
      this.exchangeRateApplied,
      this.universalUsdAmount,
    });

    final Decimal amount;
    final String currency;
    final String? exchangeRateApplied;

    /// Pre-computed total in pure USD at the time of entry (schema v8+).
    final Decimal? universalUsdAmount;
  }
// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

/// Central repository: offline-first. Writes go to local SQLite first, then
/// sync to Supabase when online.
class SetAllRepository {
  SetAllRepository({
    SupabaseClient? client,
    CurrencyService? currencyService,
  })  : _client = client,
        _currencyService = currencyService;

  final SupabaseClient? _client;
  final CurrencyService? _currencyService;
  String? _deviceUserId;

  final _changeController = StreamController<void>.broadcast();
  final _pendingDeletedGroups = <_DeletedGroupRecord>[];

  /// Emits a change event so all active [watchGroups] / [watchGroupExpenses]
  /// streams re-query SQLite and push fresh data to the UI.
  void _notify() => _changeController.add(null);

  /// Called by [SyncService] after a successful Supabase pull to trigger
  /// a UI refresh without any provider invalidation.
  void notifySyncComplete() => _notify();

  bool get isConfigured => _client != null;

  bool get _isWeb => LocalDatabase.isWeb;

  String? get currentUserId {
    if (_client != null) {
      return _client.auth.currentUser?.id;
    }
    return _deviceUserId;
  }

  Future<String?> ensureUser() async {
    if (_client != null) {
      return _client.auth.currentUser?.id;
    }
    _deviceUserId ??= await _getOrCreateDeviceUserId();
    return _deviceUserId;
  }

  Future<String> _getOrCreateDeviceUserId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_deviceUserIdKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_deviceUserIdKey, id);
    }
    return id;
  }

  /// Sync is now handled by [SyncService.performFullSync].
  /// This stub exists only for compatibility during the transition period.
  Future<void> syncIfOnline() async {}

  Future<bool> get _isOnline async {
    if (kIsWeb) return _client != null;
    try {
      final result = await Connectivity().checkConnectivity();
      // ConnectivityResult.other covers macOS wired/wifi — must be included.
      return result.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      return false;
    }
  }


  // ---------------------------------------------------------------------------
  // Profile
  // ---------------------------------------------------------------------------

  Future<ProfileModel?> getCurrentUserProfile() async {
    final uid = await ensureUser();
    if (uid == null) return null;

    // Web: always use Supabase.
    if (_isWeb && _client != null) {
      final res = await _client
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();
      if (res == null) return null;
      return ProfileModel.fromJson(res);
    }

    // Mobile: prefer Supabase when online so we always get the freshest data
    // (name, nickname, avatar_url, default_currency) and cache it locally.
    if (_client != null && await _isOnline) {
      try {
        final res = await _client
            .from('profiles')
            .select()
            .eq('id', uid)
            .maybeSingle();
        if (res != null) {
          await _upsertProfileToSQLite(res);
          return ProfileModel.fromJson(res);
        }
      } catch (_) {}
    }

    // Offline fallback: SQLite cache.
    final rows = await LocalDatabase.db.query(
      'profiles',
      where: 'id = ?',
      whereArgs: [uid],
    );
    if (rows.isEmpty) return null;
    return ProfileModel.fromJson(rows.first);
  }

  /// Upsert a Supabase profiles row into local SQLite, normalising bool→int.
  Future<void> _upsertProfileToSQLite(Map<String, dynamic> p) async {
    await LocalDatabase.db.insert(
      'profiles',
      {
        'id': p['id'],
        'name': p['name'] ?? '',
        'nickname': p['nickname'],
        'avatar_url': p['avatar_url'],
        'is_ghost': (p['is_ghost'] == true) ? 1 : 0,
        'default_currency': p['default_currency'] ?? 'USD',
        'synced_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Update the current user's profile fields (name, nickname, avatarUrl,
  /// defaultCurrency). Only non-null values are written.
  Future<void> updateProfile({
    String? name,
    String? nickname,
    String? avatarUrl,
    String? defaultCurrency,
  }) async {
    final uid = await ensureUser();
    if (uid == null) return;

    final updates = <String, dynamic>{};
    if (name != null) updates['name'] = name.trim();
    if (nickname != null) {
      updates['nickname'] = nickname.trim().isEmpty ? null : nickname.trim();
    }
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;
    if (defaultCurrency != null) updates['default_currency'] = defaultCurrency;
    if (updates.isEmpty) return;

    if (_isWeb && _client != null) {
      await _client.from('profiles').update(updates).eq('id', uid);
      return;
    }

    // Mirror to Supabase first when online so the authoritative store is updated.
    // If Supabase throws (e.g. nickname uniqueness violation), propagate the
    // error so the caller can show it — do NOT silently eat it and let
    // getCurrentUserProfile overwrite the local cache with the old value.
    if (await _isOnline && _client != null) {
      await _client.from('profiles').update(updates).eq('id', uid);
    }

    // Local DB (column additions require schema v6 — see local_database.dart)
    await LocalDatabase.db.update(
      'profiles',
      updates,
      where: 'id = ?',
      whereArgs: [uid],
    );
  }

  /// Search profiles by name, nickname, or email (via Supabase RPC).
  /// Returns an empty list when offline or Supabase is not configured.
  Future<List<ProfileModel>> searchUsers(String query) async {
    if (query.trim().length < 2) return [];
    if (_client == null) return [];
    try {
      final rows = await _client.rpc('search_profiles', params: {'p_query': query.trim()}) as List;
      return rows
          .map((r) => ProfileModel.fromJson(r as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// Add a ghost member to a group when the email is not found in Supabase.
  /// Creates a pending invite and a synthetic profile row so the ghost user
  /// can participate in debt simplification immediately.
  /// Returns the ghost user's UUID, or null if offline / not configured.
  Future<String?> addGhostMember(String groupId, String email) async {
    if (_client == null) return null;
    try {
      final result = await _client.rpc('add_ghost_member', params: {
        'p_group_id': groupId,
        'p_email': email.trim().toLowerCase(),
        'p_invited_by': currentUserId,
      });
      return result as String?;
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Balance raw data (consumed by BalanceService)
  // ---------------------------------------------------------------------------

  /// Returns raw split entries for global balance computation.
  ///
  /// Each [BalanceEntry] now carries [baseAmountAtEntry] when the expense was
  /// created with schema v4+ – enabling zero-conversion balance calculations.
  Future<({List<BalanceEntry> youOwe, List<BalanceEntry> youAreOwed})>
      getBalanceRawData(String uid) async {
    if (_isWeb && _client != null) {
      return _getBalanceRawDataWeb(uid);
    }
    // Mobile: try local first; fall back to Supabase when local is empty
    // so freshly-signed-in users see correct balances before sync completes.
    final local = await _getBalanceRawDataLocal(uid);
    if (local.youOwe.isNotEmpty || local.youAreOwed.isNotEmpty) return local;
    if (_client != null && await _isOnline) {
      return _getBalanceRawDataWeb(uid);
    }
    return local;
  }

  Future<({List<BalanceEntry> youOwe, List<BalanceEntry> youAreOwed})>
      _getBalanceRawDataWeb(String uid) async {
    // Only include expenses from 'normal' groups — exclude 'direct' (friend)
    // groups so the global counter matches the sum of the dashboard group cards.
    final normalGroupRows = await _client!
        .from('groups')
        .select('id')
        .eq('type', 'normal') as List;
    final normalGroupIds = normalGroupRows
        .map((r) => (r as Map<String, dynamic>)['id'] as String)
        .toSet();

    final youOwe = <BalanceEntry>[];
    final mySplits =
        await _client.from('splits').select().eq('user_id', uid) as List;
    for (final row in mySplits) {
      final sMap = row as Map<String, dynamic>;
      final exList = await _client
          .from('expenses')
          .select()
          .eq('id', sMap['expense_id'] as String);
      if ((exList as List).isEmpty) continue;
      final ex = (exList as List).first as Map<String, dynamic>;
      if (!normalGroupIds.contains(ex['group_id'] as String?)) continue;
      if (ex['payer_id'] == uid) continue; // payer doesn't owe themselves
      youOwe.add(_makeEntry(sMap, ex));
    }

    final youAreOwed = <BalanceEntry>[];
    final myExpenses =
        await _client.from('expenses').select().eq('payer_id', uid) as List;
    for (final ex in myExpenses) {
      final exMap = ex as Map<String, dynamic>;
      if (!normalGroupIds.contains(exMap['group_id'] as String?)) continue;
      final splits = await _client
          .from('splits')
          .select()
          .eq('expense_id', exMap['id'] as String) as List;
      for (final s in splits) {
        final sMap = s as Map<String, dynamic>;
        if (sMap['user_id'] == uid) continue; // payer not owed by themselves
        youAreOwed.add(_makeEntry(sMap, exMap));
      }
    }
    return (youOwe: youOwe, youAreOwed: youAreOwed);
  }

  Future<({List<BalanceEntry> youOwe, List<BalanceEntry> youAreOwed})>
      _getBalanceRawDataLocal(String uid) async {
    // Only include expenses from 'normal' groups — exclude 'direct' (friend)
    // groups so the global counter matches the sum of the dashboard group cards.
    final normalGroupRows = await LocalDatabase.db.query(
      'groups',
      columns: ['id'],
      where: 'type = ?',
      whereArgs: ['normal'],
    );
    final normalGroupIds =
        normalGroupRows.map((r) => r['id'] as String).toSet();

    final youOwe = <BalanceEntry>[];
    final mySplits = await LocalDatabase.db.query(
      'splits',
      where: 'user_id = ?',
      whereArgs: [uid],
    );
    for (final row in mySplits) {
      final expRows = await LocalDatabase.db.query(
        'expenses',
        where: 'id = ?',
        whereArgs: [row['expense_id']],
      );
      if (expRows.isEmpty) continue;
      final ex = expRows.first;
      if (!normalGroupIds.contains(ex['group_id'] as String?)) continue;
      if (ex['payer_id'] == uid) continue;
      youOwe.add(_makeEntry(row, ex));
    }

    final youAreOwed = <BalanceEntry>[];
    final myExpenses = await LocalDatabase.db.query(
      'expenses',
      where: 'payer_id = ?',
      whereArgs: [uid],
    );
    for (final ex in myExpenses) {
      if (!normalGroupIds.contains(ex['group_id'] as String?)) continue;
      final splits = await LocalDatabase.db.query(
        'splits',
        where: 'expense_id = ?',
        whereArgs: [ex['id']],
      );
      for (final s in splits) {
        if (s['user_id'] == uid) continue;
        youAreOwed.add(_makeEntry(s, ex));
      }
    }
    return (youOwe: youOwe, youAreOwed: youAreOwed);
  }

  /// Group-scoped raw balance. Returns null when the group has no expenses.
  Future<({List<BalanceEntry> youOwe, List<BalanceEntry> youAreOwed})?>
      getGroupBalanceRawData(String uid, String groupId) async {
    if (_isWeb && _client != null) {
      return _getGroupBalanceRawDataWeb(uid, groupId);
    }
    // Mobile: try local first; if empty and online, fall back to Supabase
    // so a freshly-signed-in user sees correct balances before sync completes.
    final local = await _getGroupBalanceRawDataLocal(uid, groupId);
    if (local != null) return local;
    if (_client != null && await _isOnline) {
      return _getGroupBalanceRawDataWeb(uid, groupId);
    }
    return null;
  }

  Future<({List<BalanceEntry> youOwe, List<BalanceEntry> youAreOwed})?>
      _getGroupBalanceRawDataWeb(String uid, String groupId) async {
    final expenseRows = await _client!
        .from('expenses')
        .select()
        .eq('group_id', groupId) as List;
    if (expenseRows.isEmpty) return null;

    final expenseIds = expenseRows
        .map((r) => (r as Map<String, dynamic>)['id'] as String)
        .toList();
    final splitsRaw = await _client
        .from('splits')
        .select()
        .inFilter('expense_id', expenseIds) as List;
    final expenseById = {
      for (final e in expenseRows)
        (e as Map<String, dynamic>)['id'] as String: e
    };

    final youOwe = <BalanceEntry>[];
    final youAreOwed = <BalanceEntry>[];
    for (final s in splitsRaw) {
      final sMap = s as Map<String, dynamic>;
      final ex = expenseById[sMap['expense_id'] as String] as Map<String, dynamic>;
      final entry = _makeEntry(sMap, ex);
      if (sMap['user_id'] == uid && ex['payer_id'] != uid) youOwe.add(entry);
      if (ex['payer_id'] == uid && sMap['user_id'] != uid) youAreOwed.add(entry);
    }
    return (youOwe: youOwe, youAreOwed: youAreOwed);
  }

  Future<({List<BalanceEntry> youOwe, List<BalanceEntry> youAreOwed})?>
      _getGroupBalanceRawDataLocal(String uid, String groupId) async {
    final expenseRows = await LocalDatabase.db.query(
      'expenses',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    if (expenseRows.isEmpty) return null;

    final expenseIds = expenseRows.map((r) => r['id'] as String).toList();
    final placeholders = expenseIds.map((_) => '?').join(',');
    final splitRows = await LocalDatabase.db.query(
      'splits',
      where: 'expense_id IN ($placeholders)',
      whereArgs: expenseIds,
    );
    final expenseById = {for (final e in expenseRows) e['id'] as String: e};

    debugPrint('[GroupBalance] uid=$uid, expenses=${expenseIds.length}, splits=${splitRows.length}');
    final youOwe = <BalanceEntry>[];
    final youAreOwed = <BalanceEntry>[];
    for (final s in splitRows) {
      final ex = expenseById[s['expense_id'] as String]!;
      final entry = _makeEntry(s, ex);
      final splitUserId = s['user_id'] as String?;
      final payerId = ex['payer_id'] as String?;
      final usd = s['universal_usd_owed'];
      debugPrint('[GroupBalance] split: userId=$splitUserId payerId=$payerId usd=$usd → owe=${splitUserId == uid && payerId != uid} owed=${payerId == uid && splitUserId != uid}');
      if (splitUserId == uid && payerId != uid) youOwe.add(entry);
      if (payerId == uid && splitUserId != uid) youAreOwed.add(entry);
    }
    debugPrint('[GroupBalance] youOwe=${youOwe.length} youAreOwed=${youAreOwed.length}');
    return (youOwe: youOwe, youAreOwed: youAreOwed);
  }

  /// Construct a [BalanceEntry] from a split row and its parent expense row.
  /// Reads [universal_usd_owed] (schema v8+) or [amount_owed] (old column name)
  /// so the app works regardless of which migration state the DB is in.
  BalanceEntry _makeEntry(
    Map<String, dynamic> splitRow,
    Map<String, dynamic> expenseRow,
  ) {
    // Prefer universal_usd_owed; fall back to amount_owed (old column name).
    final rawUsd = (splitRow['universal_usd_owed'] ?? splitRow['amount_owed'])?.toString();
    final splitAmount = Decimal.tryParse(rawUsd ?? '') ?? Decimal.zero;

    return BalanceEntry(
      amount: splitAmount,
      currency: (expenseRow['currency'] as String?) ?? 'USD',
      universalUsdAmount: splitAmount,
    );
  }
  
  // ---------------------------------------------------------------------------
  // Groups
  // ---------------------------------------------------------------------------


  /// Returns all normal (non-direct) groups the user belongs to.
  /// Direct groups are shown separately in the Friends tab via [getDirectGroups].
  /// Emits the current group list immediately, then re-emits after every
  /// local write or sync completion. The UI never needs to be invalidated.
  Stream<List<GroupModel>> watchGroups() async* {
    var last = await getMyGroups();
    yield last;
    await for (final _ in _changeController.stream) {
      final next = await getMyGroups();
      if (_groupListChanged(last, next)) {
        last = next;
        yield next;
      }
    }
  }

  /// Emits expenses for [groupId] immediately, then re-emits on every change.
  Stream<List<ExpenseModel>> watchGroupExpenses(String groupId) async* {
    var last = await getExpensesForGroup(groupId);
    yield last;
    await for (final _ in _changeController.stream) {
      final next = await getExpensesForGroup(groupId);
      if (_expenseListChanged(last, next)) {
        last = next;
        yield next;
      }
    }
  }

  static bool _groupListChanged(List<GroupModel> a, List<GroupModel> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].name != b[i].name) return true;
    }
    return false;
  }

  static bool _expenseListChanged(List<ExpenseModel> a, List<ExpenseModel> b) {
    if (a.length != b.length) return true;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id || a[i].amount != b[i].amount) return true;
    }
    return false;
  }

  Future<List<GroupModel>> getMyGroups() async {
    return _getGroupsByType(type: 'normal', includePersonal: false);
  }

  /// Returns all 1-on-1 direct groups the user belongs to.
  Future<List<GroupModel>> getDirectGroups() async {
    return _getGroupsByType(type: 'direct', includePersonal: false);
  }

  Future<List<GroupModel>> _getGroupsByType({
    required String type,
    required bool includePersonal,
  }) async {
    final uid = await ensureUser();
    if (uid == null) return [];

    if (_isWeb && _client != null) {
      final memberRows = await _client
          .from('group_members')
          .select('group_id')
          .eq('user_id', uid) as List;
      final memberIds = memberRows
          .map((e) => (e as Map<String, dynamic>)['group_id'] as String)
          .toSet()
          .toList();
      final created =
          await _client.from('groups').select('id').eq('creator_id', uid) as List;
      for (final r in created) {
        memberIds.add((r as Map<String, dynamic>)['id'] as String);
      }
      if (memberIds.isEmpty) return [];
      final rows = await _client
          .from('groups')
          .select()
          .inFilter('id', memberIds)
          .eq('type', type)
          .order('updated_at', ascending: false) as List;
      return rows.map((r) => _rowToGroup(r as Map<String, dynamic>)).toList();
    }

    // Groups this user voluntarily left must never resurface.
    final leftRows = await LocalDatabase.db.query('left_groups', columns: ['group_id']);
    final leftGroupIds = leftRows.map((r) => r['group_id'] as String).toSet();

    final memberRows = await LocalDatabase.db.query(
      'group_members',
      where: 'user_id = ?',
      whereArgs: [uid],
    );
    final memberIds = memberRows
        .map((r) => r['group_id'] as String)
        .where((id) => !leftGroupIds.contains(id))
        .toSet()
        .toList();
    final createdRows = await LocalDatabase.db.query(
      'groups',
      where: 'creator_id = ?',
      whereArgs: [uid],
    );
    final createdIds = createdRows
        .map((r) => r['id'] as String)
        .where((id) => !leftGroupIds.contains(id))
        .toList();
    final allIds = <String>{...memberIds, ...createdIds}.toList();
    if (allIds.isEmpty) return [];

    final rows = await LocalDatabase.db.query(
      'groups',
      where:
          "id IN (${allIds.map((_) => '?').join(',')}) AND (type = ? OR type IS NULL AND ? = 'normal')",
      whereArgs: [...allIds, type, type],
      orderBy: 'updated_at DESC',
    );
    return rows.map<GroupModel>((row) => _rowToGroup(row)).toList();
  }

  Future<GroupModel?> createGroup(String name) async {
    final uid = await ensureUser();
    if (uid == null) return null;

    // Reject duplicate names (case-insensitive) within the user's groups.
    final existing = await LocalDatabase.db.query(
      'groups',
      where: 'LOWER(name) = LOWER(?)',
      whereArgs: [name],
    );
    if (existing.isNotEmpty) {
      throw Exception('You already have a group named "$name".');
    }

    final id = const Uuid().v4();

    if (_isWeb && _client != null) {
      await _client.from('groups').insert(
          {'id': id, 'name': name, 'creator_id': uid, 'type': 'normal'});
      await _client
          .from('group_members')
          .insert({'group_id': id, 'user_id': uid});
      return GroupModel(id: id, name: name, creatorId: uid);
    }

    final now = _now();
    await LocalDatabase.db.insert('groups', {
      'id': id,
      'name': name,
      'creator_id': uid,
      'type': 'normal',
      'created_at': now,
      'updated_at': now,
      'synced_at': null,
    });
    await LocalDatabase.db.insert('group_members', {
      'group_id': id,
      'user_id': uid,
      'joined_at': now,
      'synced_at': null,
    });

    if (await _isOnline && _client != null) {
      // Use SECURITY DEFINER RPC to bypass RLS — same pattern as add_member_by_id.
      // The RPC also inserts the creator's group_members row atomically.
      try {
        final remoteId = await _client.rpc('create_group', params: {'p_name': name}) as String;
        if (remoteId != id) {
          await LocalDatabase.db.update('groups', {'id': remoteId, 'synced_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);
          await LocalDatabase.db.update('group_members', {'group_id': remoteId, 'synced_at': DateTime.now().millisecondsSinceEpoch}, where: 'group_id = ?', whereArgs: [id]);
          return GroupModel(id: remoteId, name: name, creatorId: uid);
        }
        await LocalDatabase.db.update('groups', {'synced_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);
        await LocalDatabase.db.update('group_members', {'synced_at': DateTime.now().millisecondsSinceEpoch}, where: 'group_id = ?', whereArgs: [id]);
      } catch (e) {
        debugPrint('⚠️ createGroup RPC failed (saved locally, will sync later): $e');
      }
    }
    _notify();
    return GroupModel(id: id, name: name, creatorId: uid);
  }

  /// Returns the creator_id for [groupId], or null if not found.
  Future<String?> getGroupCreatorId(String groupId) async {
    if (_isWeb && _client != null) {
      final rows = await _client
          .from('groups')
          .select('creator_id')
          .eq('id', groupId)
          .limit(1) as List;
      if (rows.isEmpty) return null;
      return (rows.first as Map<String, dynamic>)['creator_id'] as String?;
    }
    final rows = await LocalDatabase.db.query(
      'groups',
      columns: ['creator_id'],
      where: 'id = ?',
      whereArgs: [groupId],
    );
    if (rows.isEmpty) return null;
    return rows.first['creator_id'] as String?;
  }

  /// Delete a group. Any member of the group can perform this action.
  Future<bool> deleteGroup(String groupId) async {
    final uid = await ensureUser();
    if (uid == null) return false;

    if (_isWeb && _client != null) {
      try {
        // Snapshot name + creator before deleting.
        String webGroupName = groupId;
        String? creatorId;
        try {
          final infoRows = await _client.from('groups').select('name, creator_id').eq('id', groupId).limit(1) as List;
          if (infoRows.isNotEmpty) {
            final info = infoRows.first as Map<String, dynamic>;
            webGroupName = info['name'] as String? ?? groupId;
            creatorId    = info['creator_id'] as String?;
          }
        } catch (_) {}

        if (creatorId == uid) {
          // Full delete — cascade expenses / splits / members / group.
          final expenseRows = await _client.from('expenses').select('id').eq('group_id', groupId) as List;
          final expenseIds  = expenseRows.map((r) => (r as Map<String, dynamic>)['id'] as String).toList();
          if (expenseIds.isNotEmpty) {
            await _client.from('splits').delete().inFilter('expense_id', expenseIds);
          }
          await _client.from('expenses').delete().eq('group_id', groupId);
          await _client.from('group_members').delete().eq('group_id', groupId);
          await _client.from('groups').delete().eq('id', groupId);
        } else {
          // Non-owner: leave only — remove this user from group_members.
          await _client.from('group_members').delete()
              .eq('group_id', groupId).eq('user_id', uid);
        }
        _logGroupDeletedEvents(uid, {groupId: webGroupName});
        _notify();
        return true;
      } catch (_) {
        return false;
      }
    }

    // Local check — resolve creator and name.
    final rows = await LocalDatabase.db.query(
      'groups',
      where: 'id = ?',
      whereArgs: [groupId],
    );
    if (rows.isEmpty) return false;
    final groupName = rows.first['name'] as String? ?? groupId;
    final creatorId = rows.first['creator_id'] as String?;
    final isOwner   = creatorId == uid;

    if (isOwner) {
      // ── Owner: full cascade delete ──────────────────────────────────────
      // Remote-first: delete from Supabase before removing locally so other
      // devices' reconciler will prune the group on their next pull.
      if (await _isOnline && _client != null) {
        try {
          final remoteExpenseRows = await _client
              .from('expenses').select('id').eq('group_id', groupId) as List;
          final remoteExpenseIds = remoteExpenseRows
              .map((r) => (r as Map<String, dynamic>)['id'] as String).toList();
          if (remoteExpenseIds.isNotEmpty) {
            await _client.from('splits').delete().inFilter('expense_id', remoteExpenseIds);
          }
          await _client.from('expenses').delete().eq('group_id', groupId);
          await _client.from('group_members').delete().eq('group_id', groupId);
          await _client.from('groups').delete().eq('id', groupId);
        } catch (e) {
          debugPrint('[deleteGroup] Supabase owner-delete failed: $e');
        }
      }
      // Local cascade.
      final expenseRows = await LocalDatabase.db.query(
        'expenses', columns: ['id'], where: 'group_id = ?', whereArgs: [groupId]);
      for (final row in expenseRows) {
        await LocalDatabase.db.delete('splits',
            where: 'expense_id = ?', whereArgs: [row['id']]);
      }
      await LocalDatabase.db.delete('expenses', where: 'group_id = ?', whereArgs: [groupId]);
      await LocalDatabase.db.delete('group_members', where: 'group_id = ?', whereArgs: [groupId]);
      await LocalDatabase.db.delete('groups', where: 'id = ?', whereArgs: [groupId]);
    } else {
      // ── Non-owner: leave only ────────────────────────────────────────────
      // Remove this user from group_members remotely (best-effort).
      if (await _isOnline && _client != null) {
        try {
          await _client.from('group_members').delete()
              .eq('group_id', groupId).eq('user_id', uid);
        } catch (e) {
          debugPrint('[deleteGroup] Supabase member-exit failed: $e');
        }
      }
      // Persist the left group so _pullFromSupabase never re-pulls it.
      await LocalDatabase.db.insert(
        'left_groups',
        {'group_id': groupId, 'left_at': DateTime.now().toIso8601String()},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      // Remove locally — cascade expenses/members/group so nothing lingers.
      final expenseRows = await LocalDatabase.db.query(
        'expenses', columns: ['id'], where: 'group_id = ?', whereArgs: [groupId]);
      for (final row in expenseRows) {
        await LocalDatabase.db.delete('splits',
            where: 'expense_id = ?', whereArgs: [row['id']]);
      }
      await LocalDatabase.db.delete('expenses', where: 'group_id = ?', whereArgs: [groupId]);
      await LocalDatabase.db.delete('group_members',
          where: 'group_id = ?', whereArgs: [groupId]);
      await LocalDatabase.db.delete('groups', where: 'id = ?', whereArgs: [groupId]);
    }

    _logGroupDeletedEvents(uid, {groupId: groupName});
    _notify();
    return true;
  }

  /// Batch-delete multiple groups.
  /// Delegates to [deleteGroup] so the owner-check, left_groups write, and
  /// cascade are identical whether the user deletes one group or many.
  Future<bool> deleteGroups(List<String> ids) async {
    if (ids.isEmpty) return true;
    bool allOk = true;
    for (final id in ids) {
      final ok = await deleteGroup(id);
      if (!ok) allOk = false;
    }
    return allOk;
  }

  void _logGroupDeletedEvents(String uid, Map<String, String> groupNames) {
    // Logged as in-memory events only; picked up by next _buildOmniActivity call.
    for (final entry in groupNames.entries) {
      _pendingDeletedGroups.add(_DeletedGroupRecord(
        id: entry.key,
        name: entry.value,
        deletedAt: _now(),
        deletedByUid: uid,
      ));
    }
  }

  /// Batch-delete multiple expenses by [ids]. Removes splits first, then the
  /// expense rows — both locally (SQLite transaction) and on Supabase.
  Future<bool> deleteExpenses(List<String> ids) async {
    if (ids.isEmpty) return true;
    final uid = await ensureUser();
    if (uid == null) return false;

    // ── Supabase (web or online native) ──────────────────────────────────
    if (_isWeb && _client != null) {
      try {
        await _client.from('splits').delete().inFilter('expense_id', ids);
        await _client.from('expenses').delete().inFilter('id', ids);
        _notify();
        return true;
      } catch (e) {
        debugPrint('[deleteExpenses] Supabase error: $e');
        return false;
      }
    }

    if (await _isOnline && _client != null) {
      try {
        await _client.from('splits').delete().inFilter('expense_id', ids);
        await _client.from('expenses').delete().inFilter('id', ids);
      } catch (e) {
        debugPrint('[deleteExpenses] Supabase delete failed (continuing locally): $e');
      }
    }

    // ── Local SQLite — single transaction ────────────────────────────────
    final db = LocalDatabase.db;
    final placeholder = ids.map((_) => '?').join(',');
    await db.transaction((txn) async {
      await txn.delete('splits',   where: 'expense_id IN ($placeholder)', whereArgs: ids);
      await txn.delete('expenses', where: 'id IN ($placeholder)',          whereArgs: ids);
    });

    _notify();
    return true;
  }

  /// Remove a member from a group. Only the group creator can do this,
  /// and cannot remove themselves.
  Future<({bool ok, String? error})> removeGroupMember(
      String groupId, String userId) async {
    final uid = await ensureUser();
    if (uid == null) return (ok: false, error: 'not_signed_in');

    if (_isWeb && _client != null) {
      try {
        await _client.rpc('remove_group_member',
            params: {'p_group_id': groupId, 'p_user_id': userId});
        return (ok: true, error: null);
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('not_group_creator')) {
          return (ok: false, error: 'Only the group creator can remove members.');
        }
        if (msg.contains('cannot_remove_creator')) {
          return (ok: false, error: 'The group creator cannot be removed.');
        }
        return (ok: false, error: 'Could not remove member.');
      }
    }

    // Local-first: verify caller is the creator.
    final groupRows = await LocalDatabase.db.query(
      'groups',
      where: 'id = ? AND creator_id = ?',
      whereArgs: [groupId, uid],
    );
    if (groupRows.isEmpty) {
      return (ok: false, error: 'Only the group creator can remove members.');
    }
    if (userId == uid) {
      return (ok: false, error: 'The group creator cannot be removed.');
    }

    await LocalDatabase.db.delete(
      'group_members',
      where: 'group_id = ? AND user_id = ?',
      whereArgs: [groupId, userId],
    );

    if (await _isOnline && _client != null) {
      try {
        await _client.rpc('remove_group_member',
            params: {'p_group_id': groupId, 'p_user_id': userId});
      } catch (_) {}
    }
    _notify();
    return (ok: true, error: null);
  }

  /// Rename a group. Only the creator can perform this action.
  Future<bool> renameGroup(String groupId, String newName) async {
    final uid = await ensureUser();
    if (uid == null) return false;
    final trimmed = newName.trim();
    if (trimmed.isEmpty) return false;

    if (_isWeb && _client != null) {
      try {
        await _client
            .from('groups')
            .update({'name': trimmed})
            .eq('id', groupId)
            .eq('creator_id', uid);
        return true;
      } catch (_) {
        return false;
      }
    }

    final rows = await LocalDatabase.db.query(
      'groups',
      where: 'id = ? AND creator_id = ?',
      whereArgs: [groupId, uid],
    );
    if (rows.isEmpty) return false;

    await LocalDatabase.db.update(
      'groups',
      {'name': trimmed},
      where: 'id = ?',
      whereArgs: [groupId],
    );
    if (await _isOnline && _client != null) {
      try {
        await _client
            .from('groups')
            .update({'name': trimmed})
            .eq('id', groupId)
            .eq('creator_id', uid);
      } catch (_) {}
    }
    _notify();
    return true;
  }

  /// Creates a 1-on-1 direct group with [otherEmail].
  ///
  /// On web/Supabase: calls the `create_direct_group` RPC which is idempotent
  /// (returns the existing direct group ID if one already exists).
  /// On mobile (local-first): creates the group locally and syncs when online.
  ///
  /// Returns null if [otherEmail] is not found or an error occurs.
  Future<GroupModel?> createDirectGroup(String otherEmail) async {
    final uid = await ensureUser();
    if (uid == null) return null;
    final trimmedEmail = otherEmail.trim().toLowerCase();

    if (_isWeb && _client != null) {
      try {
        final groupId = await _client.rpc(
          'create_direct_group',
          params: {'p_other_email': trimmedEmail},
        ) as String?;
        if (groupId == null) return null;
        final rows = await _client
            .from('groups')
            .select()
            .eq('id', groupId)
            .limit(1) as List;
        if (rows.isEmpty) return null;
        return _rowToGroup(rows.first as Map<String, dynamic>);
      } catch (e) {
        final msg = e.toString();
        if (msg.contains('user_not_found')) {
          throw const DirectGroupUserNotFoundException();
        }
        rethrow;
      }
    }

    // Mobile: resolve other user via Supabase, create locally, sync.
    final client = _client;
    if (client == null) return null;
    try {
      final groupId = await client.rpc(
        'create_direct_group',
        params: {'p_other_email': trimmedEmail},
      ) as String?;
      if (groupId == null) return null;

      // Fetch full group data from Supabase to sync locally.
      final rows = await client
          .from('groups')
          .select()
          .eq('id', groupId)
          .limit(1) as List;
      if (rows.isEmpty) return null;
      final group = _rowToGroup(rows.first as Map<String, dynamic>);
      final now = _now();

      // Upsert into local DB so offline access works.
      await LocalDatabase.db.insert(
        'groups',
        {
          'id': group.id,
          'name': group.name,
          'creator_id': group.creatorId,
          'type': group.type.name,
          'created_at': now,
          'updated_at': now,
          'synced_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      await LocalDatabase.db.insert(
        'group_members',
        {'group_id': group.id, 'user_id': uid, 'joined_at': now, 'synced_at': null},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      return group;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('user_not_found')) {
        throw const DirectGroupUserNotFoundException();
      }
      rethrow;
    }
  }

  /// Create (or return an existing) 1-on-1 "direct" group with [otherUserId].
  /// Uses the [create_direct_group_by_id] SECURITY DEFINER RPC so no email
  /// look-up is needed — only the profile UUID from the search results.
  Future<GroupModel?> createDirectGroupById(String otherUserId) async {
    final uid = await ensureUser();
    if (uid == null) return null;
    if (_client == null) return null;
    try {
      final groupId = await _client.rpc(
        'create_direct_group_by_id',
        params: {'p_other_id': otherUserId},
      ) as String?;
      if (groupId == null) return null;

      final rows = await _client
          .from('groups')
          .select()
          .eq('id', groupId)
          .limit(1) as List;
      if (rows.isEmpty) return null;
      final group = _rowToGroup(rows.first as Map<String, dynamic>);
      final now   = _now();

      if (!_isWeb) {
        await LocalDatabase.db.insert(
          'groups',
          {
            'id': group.id,
            'name': group.name,
            'creator_id': group.creatorId,
            'type': group.type.name,
            'created_at': now,
            'updated_at': now,
            'synced_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await LocalDatabase.db.insert(
          'group_members',
          {'group_id': group.id, 'user_id': uid, 'joined_at': now, 'synced_at': null},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await LocalDatabase.db.insert(
          'group_members',
          {'group_id': group.id, 'user_id': otherUserId, 'joined_at': now, 'synced_at': null},
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      return group;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('cannot_add_self')) {
        throw Exception('You cannot add yourself as a friend.');
      }
      rethrow;
    }
  }

  // ---------------------------------------------------------------------------
  // Members
  // ---------------------------------------------------------------------------

  Future<List<ProfileModel>> getGroupMembers(String groupId) async {
    // Web always uses Supabase directly.
    if (_isWeb && _client != null) {
      return _getGroupMembersFromSupabase(groupId);
    }

    // Mobile: freshen from Supabase when online so newly-joined members
    // appear immediately (e.g. after invite, or when switching accounts).
    if (_client != null && await _isOnline) {
      try {
        final members = await _getGroupMembersFromSupabase(groupId);
        // Cache member rows locally for offline use.
        final now = _now();
        for (final m in members) {
          await LocalDatabase.db.insert(
            'group_members',
            {'group_id': groupId, 'user_id': m.id, 'joined_at': now, 'synced_at': DateTime.now().millisecondsSinceEpoch},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        return members;
      } catch (_) {
        // Fall through to local on error.
      }
    }

    // Offline fallback: local SQLite.
    final rows = await LocalDatabase.db.query(
      'group_members',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    final userIds = rows.map((r) => r['user_id'] as String).toSet().toList();
    if (userIds.isEmpty) return [];

    final profileRows = await LocalDatabase.db.query(
      'profiles',
      where: 'id IN (${userIds.map((_) => '?').join(',')})',
      whereArgs: userIds,
    );
    if (profileRows.isEmpty) {
      return userIds
          .map((id) => ProfileModel(id: id, name: 'Member', defaultCurrency: 'USD'))
          .toList();
    }
    return profileRows.map((r) => ProfileModel.fromJson(r)).toList();
  }

  /// Shared Supabase path for fetching group members + their profiles.
  Future<List<ProfileModel>> _getGroupMembersFromSupabase(String groupId) async {
    final rows = await _client!
        .from('group_members')
        .select('user_id')
        .eq('group_id', groupId) as List;
    var userIds =
        rows.map((r) => (r as Map<String, dynamic>)['user_id'] as String).toSet().toList();
    debugPrint('[getGroupMembers] groupId=$groupId → group_members rows=${rows.length}, userIds=$userIds');

    // If RLS only returned our own row (unapplied migration), fall back to the
    // SECURITY DEFINER RPC which reads group_members as the DB owner.
    if (userIds.length <= 1) {
      try {
        final rpcRows = await _client.rpc(
          'get_group_members',
          params: {'p_group_id': groupId},
        ) as List;
        if (rpcRows.length > userIds.length) {
          userIds = rpcRows
              .map((r) => (r as Map<String, dynamic>)['user_id'] as String)
              .toSet()
              .toList();
          debugPrint('[getGroupMembers] RPC fallback: ${userIds.length} members: $userIds');
        }
      } catch (_) {}
    }

    if (userIds.isEmpty) return [];
    final profileRows =
        await _client.from('profiles').select().inFilter('id', userIds) as List;
    if (profileRows.isEmpty) {
      return userIds
          .map((id) => ProfileModel(id: id, name: 'Member', defaultCurrency: 'USD'))
          .toList();
    }
    return profileRows.map((r) {
      final m = r as Map<String, dynamic>;
      // Also cache into local SQLite.
      if (!_isWeb) {
        LocalDatabase.db.insert(
          'profiles',
          {
            'id': m['id'],
            'name': m['name'] ?? '',
            'nickname': m['nickname'],
            'avatar_url': m['avatar_url'],
            'default_currency': m['default_currency'] ?? 'USD',
            'is_ghost': (m['is_ghost'] == true) ? 1 : 0,
            'synced_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      return ProfileModel(
        id: m['id'] as String,
        name: (m['name'] as String?) ?? 'Member',
        defaultCurrency: (m['default_currency'] as String?) ?? 'USD',
      );
    }).toList();
  }

  
  
  Future<void> addMemberByEmail(String groupId, String identifier) async {
  final uid = await ensureUser();
  if (uid == null || _client == null || !await _isOnline) {
    debugPrint('❌ Cannot invite: Offline or Not Authenticated');
    throw Exception('You must be online to invite members.');
  }

  try {
    debugPrint('🚀 Calling RPC add_member_by_email with: $identifier');
    
          // The RPC now automatically detects if the identifier is an email or nickname
          await _client.rpc('add_member_by_email', params: {
            'p_group_id': groupId,
    
      'p_identifier': identifier.trim().toLowerCase(),
    });
    
    debugPrint('✅ Successfully added $identifier to group $groupId');
    
  } on PostgrestException catch (e) {
    debugPrint('❌ DATABASE ERROR [${e.code}]: ${e.message}');
    // Throw a user-friendly version of the database exception
    throw Exception(e.message); 
  } catch (e) {
    debugPrint('❌ SYSTEM ERROR: $e');
    throw Exception('An unexpected error occurred. Please try again.');
  }
}



  /// Add an existing (registered) user to a group by their profile UUID.
  /// Calls the [add_member_by_id] SECURITY DEFINER RPC, then mirrors the row
  /// into local SQLite so [getGroupMembers] reflects the change immediately
  /// without requiring a full sync round-trip.
  Future<void> addMemberById(String groupId, String userId) async {
    if (_client == null || !await _isOnline) {
      throw Exception('Internet connection required to add member.');
    }
    await _client.rpc('add_member_by_id', params: {
      'p_group_id': groupId,
      'p_user_id': userId,
    });

    // Mirror to local SQLite so the member appears immediately on mobile.
    if (!_isWeb) {
      final now = _now();
      await LocalDatabase.db.insert(
        'group_members',
        {
          'group_id': groupId,
          'user_id': userId,
          'joined_at': now,
          'synced_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
      // Also pull the new member's profile into local profiles table.
      try {
        final profileRows = await _client
            .from('profiles')
            .select()
            .eq('id', userId)
            .limit(1) as List;
        if (profileRows.isNotEmpty) {
          final p = profileRows.first as Map<String, dynamic>;
          await LocalDatabase.db.insert(
            'profiles',
            {
              'id': p['id'],
              'name': p['name'] ?? '',
              'nickname': p['nickname'],
              'avatar_url': p['avatar_url'],
              'default_currency': p['default_currency'] ?? 'USD',
              'is_ghost': (p['is_ghost'] == true) ? 1 : 0,
              'synced_at': DateTime.now().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      } catch (_) {}
    }
  }

  // ---------------------------------------------------------------------------
  // Expenses – CRUD
  // ---------------------------------------------------------------------------

  Future<List<ExpenseModel>> getRecentExpenses({int limit = 20}) async {
    final uid = await ensureUser();
    if (uid == null) return [];

    if (_isWeb && _client != null) {
      final memberRows = await _client
          .from('group_members')
          .select('group_id')
          .eq('user_id', uid) as List;
      final groupIds = memberRows
          .map((r) => (r as Map<String, dynamic>)['group_id'] as String)
          .toSet()
          .toList();
      final created =
          await _client.from('groups').select('id').eq('creator_id', uid) as List;
      for (final r in created) {
        groupIds.add((r as Map<String, dynamic>)['id'] as String);
      }
      if (groupIds.isEmpty) return [];
      final rows = await _client
          .from('expenses')
          .select()
          .inFilter('group_id', groupIds)
          .order('created_at', ascending: false)
          .limit(limit) as List;
      return rows.map((r) => _rowToExpense(r as Map<String, dynamic>)).toList();
    }

    final memberRows = await LocalDatabase.db.query(
      'group_members',
      where: 'user_id = ?',
      whereArgs: [uid],
    );
    final groupIds =
        memberRows.map((r) => r['group_id'] as String).toSet().toList();
    final created = await LocalDatabase.db.query(
      'groups',
      where: 'creator_id = ?',
      whereArgs: [uid],
    );
    for (final r in created) {
      groupIds.add(r['id'] as String);
    }
    if (groupIds.isEmpty) return [];
    final rows = await LocalDatabase.db.query(
      'expenses',
      where: 'group_id IN (${groupIds.map((_) => '?').join(',')})',
      whereArgs: groupIds,
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map<ExpenseModel>((row) => _rowToExpense(row)).toList();
  }

  Future<List<ExpenseModel>> getExpensesForGroup(String groupId) async {
    if (_isWeb && _client != null) {
      final rows = await _client
          .from('expenses')
          .select()
          .eq('group_id', groupId)
          .order('created_at', ascending: false) as List;
      return rows.map((r) => _rowToExpense(r as Map<String, dynamic>)).toList();
    }
    final rows = await LocalDatabase.db.query(
      'expenses',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'created_at DESC',
    );
    return rows.map<ExpenseModel>((row) => _rowToExpense(row)).toList();
  }

  Future<ExpenseModel?> getExpense(String expenseId) async {
    if (_isWeb && _client != null) {
      final res = await _client
          .from('expenses')
          .select()
          .eq('id', expenseId)
          .maybeSingle();
      if (res == null) return null;
      return _rowToExpense(res);
    }
    final rows = await LocalDatabase.db.query(
      'expenses',
      where: 'id = ?',
      whereArgs: [expenseId],
    );
    if (rows.isEmpty) return null;
    return _rowToExpense(rows.first);
  }

  Future<List<SplitModel>> getSplitsForExpense(String expenseId) async {
    if (_isWeb && _client != null) {
      final rows =
          await _client.from('splits').select().eq('expense_id', expenseId) as List;
      return rows.map((r) => _rowToSplit(r as Map<String, dynamic>)).toList();
    }
    final rows = await LocalDatabase.db.query(
      'splits',
      where: 'expense_id = ?',
      whereArgs: [expenseId],
    );
    return rows.map<SplitModel>((row) => _rowToSplit(row)).toList();
  }

  /// Add an expense. Offline-first on mobile; Supabase-only on web.
  ///
  /// The [universal_usd_amount] (USD anchor) is calculated internally via
  /// [CurrencyService] to ensure financial consistency.
  Future<ExpenseModel?> addExpense({
    String? groupId,
    required String payerId,
    required Decimal amount,
    required String description,
    required String currency,
    required SplitType splitType,
    required List<SplitInsert> splits,
    String category = 'General',
    bool isIncome = false,
    Decimal? originalAmount,
    String? originalCurrency,
    String? exchangeRateApplied,
  }) async {
    final uid = await ensureUser();
    if (uid == null) return null;
    final expenseId = const Uuid().v4();
    final now = _now();

    // -- Anchor logic: Always compute USD value --
    Decimal rateToUsd = Decimal.one;
    if (_currencyService != null) {
      rateToUsd = await _currencyService.getRateToUsd(currency);
    }
    final universalUsdAmount = (amount * rateToUsd).round(scale: 2);

          final expense = ExpenseModel(
            id: expenseId,
            groupId: groupId,
            payerId: payerId,
            amount: amount.toString(),
            description: description,
            currency: currency,
            splitType: splitType,
            category: category,
            isIncome: isIncome,
            createdAt: now,
            createdBy: uid,
            originalAmount: originalAmount?.toString(),
            originalCurrency: originalCurrency,
            exchangeRateApplied: exchangeRateApplied ?? rateToUsd.toString(),
            universalUsdAmount: universalUsdAmount.toString(),
          );
    
          final expenseData = expense.toJson();
          // Strip local-only / schema-mismatched fields before sending to Supabase.
          // Remap is_income: SQLite stores 0/1 int, Postgres expects boolean.
          // Also coerce empty-string groupId to null (wallet entries).
          final supabaseExpenseData = Map<String, dynamic>.from(expenseData)
            ..remove('created_by')
            ..remove('base_amount_at_entry')
            ..['is_income'] = (expenseData['is_income'] as int? ?? 0) != 0
            ..['group_id'] = (expenseData['group_id'] as String?)?.isEmpty == true
                ? null
                : expenseData['group_id'];
    
          if (_isWeb && _client != null) {
            try {
                        await _client.from('expenses').insert(supabaseExpenseData);
                        for (final s in splits) {
                          // Calculate proportional universal_usd_owed
                          final usdOwed = (s.universalUsdOwed * rateToUsd).round(scale: 2);
                          final split = SplitModel(
                            id: const Uuid().v4(),
                            expenseId: expenseId,
                            userId: s.userId,
                            universalUsdOwed: usdOwed.toString(),
                          );
                          await _client.from('splits').insert(split.toJson());
                        }
                        return expense;
                      } catch (e) {
                        if (e is PostgrestException) {
                          debugPrint(
                              'PostgrestException in addExpense: ${e.message}, code: ${e.code}, details: ${e.details}, hint: ${e.hint}');
                        } else {
                          debugPrint('Error in addExpense (Supabase): $e');
                        }
                        return null;
                      }
                    }
              
                    // Build split models with stable UUIDs so local + Supabase rows
                    // share the same ID — preventing _syncFromSupabase from inserting
                    // duplicates when it pulls Supabase rows back into SQLite.
                    final splitModels = splits.map((s) {
                      final usdOwed = (s.universalUsdOwed * rateToUsd).round(scale: 2);
                      return SplitModel(
                        id: const Uuid().v4(),
                        expenseId: expenseId,
                        userId: s.userId,
                        universalUsdOwed: usdOwed.toString(),
                      );
                    }).toList();

                    // Local SQLite
                    await LocalDatabase.db.insert('expenses', {
                      ...expenseData,
                      'synced_at': null,
                    });
                    for (final split in splitModels) {
                      await LocalDatabase.db.insert('splits', {
                        ...split.toJson(),
                        'created_at': now,
                        'synced_at': null,
                      });
                    }
              
                    // Fire-and-forget: return immediately after local save.
                    // SyncService retries on next tick if network is unavailable.
                    Future(() async {
                      if (!await _isOnline || _client == null) return;
                      try {
                        await Future.wait([
                          _client.from('expenses').insert(supabaseExpenseData),
                          ...splitModels.map((s) => _client.from('splits').insert(s.toJson())),
                        ]).timeout(const Duration(seconds: 8));
                        await LocalDatabase.db.update(
                          'expenses',
                          {'synced_at': DateTime.now().millisecondsSinceEpoch},
                          where: 'id = ?',
                          whereArgs: [expenseId],
                        );
                      } catch (e) {
                        if (e is PostgrestException) {
                          debugPrint(
                              'PostgrestException in addExpense (bg sync): ${e.message}, code: ${e.code}');
                        } else {
                          debugPrint('Error in addExpense (bg sync): $e');
                        }
                      }
                    });

    // Ensure all split participants are in group_members so they appear in
    // the members list even if they were never formally invited.
    if (groupId != null) {
      await _ensureSplitParticipantsAreMembers(groupId, splits.map((s) => s.userId).toList());
    }

    _notify();
    return expense;
  }

  /// Fetch personal (wallet) expenses – expenses with no group_id.
  Future<List<ExpenseModel>> getPersonalExpenses({int limit = 50}) async {
    final uid = await ensureUser();
    if (uid == null) return [];

    if (_isWeb && _client != null) {
      final rows = await _client
          .from('expenses')
          .select()
          .isFilter('group_id', null)
          .eq('payer_id', uid)
          .order('created_at', ascending: false)
          .limit(limit) as List;
      return rows.map((r) => _rowToExpense(r as Map<String, dynamic>)).toList();
    }

    final rows = await LocalDatabase.db.query(
      'expenses',
      where: 'group_id IS NULL AND payer_id = ?',
      whereArgs: [uid],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map<ExpenseModel>((row) => _rowToExpense(row)).toList();
  }

  // ---------------------------------------------------------------------------
  // User Categories
  // ---------------------------------------------------------------------------

  /// Returns the current user's custom categories from local SQLite (or Supabase on web).
  Future<List<Map<String, String>>> getUserCategories() async {
    final uid = await ensureUser();
    if (uid == null) return [];

    if (_isWeb && _client != null) {
      try {
        final rows = await _client
            .from('user_categories')
            .select()
            .eq('created_by', uid)
            .order('created_at', ascending: true) as List;
        return rows
            .map((r) => Map<String, String>.from(
                (r as Map<String, dynamic>).map((k, v) => MapEntry(k, v?.toString() ?? ''))))
            .toList();
      } catch (_) {
        return [];
      }
    }

    if (LocalDatabase.dbOrNull == null) return [];
    final rows = await LocalDatabase.db.query(
      'user_categories',
      where: 'created_by = ?',
      whereArgs: [uid],
      orderBy: 'created_at ASC',
    );
    return rows
        .map((r) => r.map((k, v) => MapEntry(k, v?.toString() ?? '')))
        .toList();
  }

  /// Creates a new custom category locally and syncs to Supabase.
  /// [type] is 'expense' or 'income'.
  Future<bool> createUserCategory({
    required String name,
    required String type,
  }) async {
    final uid = await ensureUser();
    if (uid == null) return false;
    final id = const Uuid().v4();
    final now = _now();

    if (_isWeb && _client != null) {
      try {
        await _client.from('user_categories').insert({
          'id': id, 'name': name, 'type': type, 'created_by': uid, 'created_at': now,
        });
        return true;
      } catch (e) {
        debugPrint('[createUserCategory] Supabase error: $e');
        return false;
      }
    }

    await LocalDatabase.db.insert('user_categories', {
      'id': id, 'name': name, 'type': type, 'created_by': uid, 'created_at': now,
    });

    if (await _isOnline && _client != null) {
      try {
        await _client.from('user_categories').insert({
          'id': id, 'name': name, 'type': type, 'created_by': uid, 'created_at': now,
        });
      } catch (e) {
        debugPrint('[createUserCategory] Supabase sync failed (non-fatal): $e');
      }
    }
    return true;
  }

  /// Calculate wallet balance: income - personal expenses - user's share of group expenses.
  /// Returns amount in the user's base currency (USD fallback).
  Future<Decimal> getWalletBalance() async {
    final uid = await ensureUser();
    if (uid == null) return Decimal.zero;

    // 1. Sum personal income entries
    final personalRows = await getPersonalExpenses(limit: 1000);
    Decimal income = Decimal.zero;
    Decimal personalSpend = Decimal.zero;
    for (final e in personalRows) {
      final amt = Decimal.tryParse(e.universalUsdAmount ?? e.amount) ?? Decimal.zero;
      if (e.isIncome) {
        income += amt;
      } else {
        personalSpend += amt;
      }
    }

    // 2. Sum the user's owed share from group splits
    Decimal groupShare = Decimal.zero;
    if (!_isWeb) {
      final splitRows = await LocalDatabase.db.rawQuery(
        'SELECT s.universal_usd_owed FROM splits s '
        'INNER JOIN expenses e ON e.id = s.expense_id '
        'WHERE s.user_id = ? AND e.group_id IS NOT NULL',
        [uid],
      );
      for (final r in splitRows) {
        groupShare += Decimal.tryParse(r['universal_usd_owed']?.toString() ?? '0') ?? Decimal.zero;
      }
    } else if (_client != null) {
      final rows = await _client
          .from('splits')
          .select('universal_usd_owed')
          .eq('user_id', uid) as List;
      for (final r in rows) {
        groupShare += Decimal.tryParse(
                (r as Map<String, dynamic>)['universal_usd_owed']?.toString() ?? '0') ??
            Decimal.zero;
      }
    }

    return income - personalSpend - groupShare;
  }

  /// Stream a unified activity feed: group + personal expenses, sorted newest-first.
  Stream<List<ExpenseModel>> watchActivityFeed({int limit = 50}) async* {
    // Yield immediately from current data, then re-yield on every _notify()
    yield await _buildActivityFeed(limit);
    await for (final _ in _changeController.stream) {
      yield await _buildActivityFeed(limit);
    }
  }

  Future<List<ExpenseModel>> _buildActivityFeed(int limit) async {
    final uid = await ensureUser();
    if (uid == null) return [];

    if (_isWeb && _client != null) {
      // Group expenses
      final memberRows = await _client
          .from('group_members')
          .select('group_id')
          .eq('user_id', uid) as List;
      final groupIds = memberRows
          .map((r) => (r as Map<String, dynamic>)['group_id'] as String)
          .toSet()
          .toList();
      final created =
          await _client.from('groups').select('id').eq('creator_id', uid) as List;
      for (final r in created) {
        groupIds.add((r as Map<String, dynamic>)['id'] as String);
      }

      final List<ExpenseModel> results = [];
      if (groupIds.isNotEmpty) {
        final groupRows = await _client
            .from('expenses')
            .select()
            .inFilter('group_id', groupIds)
            .order('created_at', ascending: false)
            .limit(limit) as List;
        results.addAll(groupRows.map((r) => _rowToExpense(r as Map<String, dynamic>)));
      }
      // Personal expenses
      final personalRows = await _client
          .from('expenses')
          .select()
          .isFilter('group_id', null)
          .eq('payer_id', uid)
          .order('created_at', ascending: false)
          .limit(limit) as List;
      results.addAll(personalRows.map((r) => _rowToExpense(r as Map<String, dynamic>)));
      results.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
      return results.take(limit).toList();
    }

    // Mobile SQLite path
    final memberRows = await LocalDatabase.db.query(
      'group_members', where: 'user_id = ?', whereArgs: [uid]);
    final groupIds = memberRows.map((r) => r['group_id'] as String).toSet().toList();
    final createdRows = await LocalDatabase.db.query(
      'groups', where: 'creator_id = ?', whereArgs: [uid]);
    for (final r in createdRows) {
      groupIds.add(r['id'] as String);
    }

    final List<ExpenseModel> results = [];
    if (groupIds.isNotEmpty) {
      final groupExpRows = await LocalDatabase.db.query(
        'expenses',
        where: 'group_id IN (${groupIds.map((_) => '?').join(',')})',
        whereArgs: groupIds,
        orderBy: 'created_at DESC',
        limit: limit,
      );
      results.addAll(groupExpRows.map(_rowToExpense));
    }
    final personalExpRows = await LocalDatabase.db.query(
      'expenses',
      where: 'group_id IS NULL AND payer_id = ?',
      whereArgs: [uid],
      orderBy: 'created_at DESC',
      limit: limit,
    );
    results.addAll(personalExpRows.map(_rowToExpense));
    results.sort((a, b) => (b.createdAt ?? '').compareTo(a.createdAt ?? ''));
    return results.take(limit).toList();
  }

  // ---------------------------------------------------------------------------
  // Omni Activity Feed — polymorphic event stream
  // ---------------------------------------------------------------------------

  /// Streams a unified, chronological list of [ActivityEvent]s aggregating
  /// expenses (group + personal), group-creation events, and settlements.
  Stream<List<ActivityEvent>> watchOmniActivity({int limit = 80}) async* {
    yield await _buildOmniActivity(limit);
    await for (final _ in _changeController.stream) {
      yield await _buildOmniActivity(limit);
    }
  }

  Future<List<ActivityEvent>> _buildOmniActivity(int limit) async {
    final uid = await ensureUser();
    if (uid == null) return [];

    final List<ActivityEvent> events = [];

    // ── 1. Groups the current user belongs to / created ─────────────────────
    List<Map<String, dynamic>> groupRows;
    if (_isWeb && _client != null) {
      final memberGidRows = await _client
          .from('group_members')
          .select('group_id')
          .eq('user_id', uid) as List;
      final gids = memberGidRows
          .map((r) => (r as Map<String, dynamic>)['group_id'] as String)
          .toSet()
          .toList();
      final createdRows =
          await _client.from('groups').select('id').eq('creator_id', uid) as List;
      for (final r in createdRows) {
        gids.add((r as Map<String, dynamic>)['id'] as String);
      }
      if (gids.isEmpty) {
        groupRows = [];
      } else {
        final raw = await _client
            .from('groups')
            .select('id, name, creator_id, created_at')
            .inFilter('id', gids) as List;
        groupRows = raw.cast<Map<String, dynamic>>();
      }
    } else {
      final memberGidRows = await LocalDatabase.db.query(
        'group_members',
        columns: ['group_id'],
        where: 'user_id = ?',
        whereArgs: [uid],
      );
      final gids = memberGidRows.map((r) => r['group_id'] as String).toSet().toList();
      final createdRows = await LocalDatabase.db.query(
        'groups',
        columns: ['id'],
        where: 'creator_id = ?',
        whereArgs: [uid],
      );
      for (final r in createdRows) {
        gids.add(r['id'] as String);
      }
      if (gids.isNotEmpty) {
        final raw = await LocalDatabase.db.query(
          'groups',
          columns: ['id', 'name', 'creator_id', 'created_at'],
          where: 'id IN (${gids.map((_) => '?').join(',')})',
          whereArgs: gids,
        );
        groupRows = raw;
      } else {
        groupRows = [];
      }
    }

    // Build group name map for expense enrichment
    final groupNameMap = <String, String>{
      for (final g in groupRows)
        (g['id'] as String): (g['name'] as String? ?? ''),
    };

    // ── 2. Group-created events ──────────────────────────────────────────────
    for (final g in groupRows) {
      final ts = (g['created_at'] as String?) ?? '';
      events.add(GroupCreatedEvent(
        timestamp: ts,
        groupId: g['id'] as String,
        groupName: g['name'] as String? ?? '',
        createdByYou: (g['creator_id'] as String?) == uid,
      ));
    }

    // ── 3. Expenses (group + personal) ───────────────────────────────────────
    final gids = groupRows.map((g) => g['id'] as String).toList();

    if (_isWeb && _client != null) {
      if (gids.isNotEmpty) {
        final raw = await _client
            .from('expenses')
            .select()
            .inFilter('group_id', gids)
            .order('created_at', ascending: false)
            .limit(limit) as List;
        for (final r in raw) {
          final m = r as Map<String, dynamic>;
          final e = _rowToExpense(m);
          events.add(ExpenseEvent(
            timestamp: e.createdAt ?? '',
            expense: e,
            groupName: groupNameMap[e.groupId] ?? '',
          ));
        }
      }
      // Personal
      final personal = await _client
          .from('expenses')
          .select()
          .isFilter('group_id', null)
          .eq('payer_id', uid)
          .order('created_at', ascending: false)
          .limit(limit) as List;
      for (final r in personal) {
        final e = _rowToExpense(r as Map<String, dynamic>);
        events.add(ExpenseEvent(
          timestamp: e.createdAt ?? '',
          expense: e,
          groupName: '',
        ));
      }
    } else {
      if (gids.isNotEmpty) {
        final raw = await LocalDatabase.db.query(
          'expenses',
          where: 'group_id IN (${gids.map((_) => '?').join(',')})',
          whereArgs: gids,
          orderBy: 'created_at DESC',
          limit: limit,
        );
        for (final r in raw) {
          final e = _rowToExpense(r);
          events.add(ExpenseEvent(
            timestamp: e.createdAt ?? '',
            expense: e,
            groupName: groupNameMap[e.groupId] ?? '',
          ));
        }
      }
      // Personal
      final personal = await LocalDatabase.db.query(
        'expenses',
        where: 'group_id IS NULL AND payer_id = ?',
        whereArgs: [uid],
        orderBy: 'created_at DESC',
        limit: limit,
      );
      for (final r in personal) {
        final e = _rowToExpense(r);
        events.add(ExpenseEvent(
          timestamp: e.createdAt ?? '',
          expense: e,
          groupName: '',
        ));
      }
    }

    // ── 4. In-memory group-deleted events (logged on deleteGroup/deleteGroups) ─
    for (final rec in _pendingDeletedGroups) {
      if (rec.deletedByUid == uid) {
        events.add(GroupDeletedEvent(
          timestamp: rec.deletedAt,
          groupId:   rec.id,
          groupName: rec.name,
        ));
      }
    }

    // ── 5. Sort newest-first, cap at limit ───────────────────────────────────
    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events.take(limit).toList();
  }

  /// Silently adds any split participant who is missing from group_members.
  Future<void> _ensureSplitParticipantsAreMembers(
    String groupId,
    List<String> userIds,
  ) async {
    final now = _now();
    for (final userId in userIds) {
      // Local SQLite
      if (!_isWeb) {
        try {
          await LocalDatabase.db.insert(
            'group_members',
            {
              'group_id': groupId,
              'user_id': userId,
              'joined_at': now,
              'synced_at': null,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        } catch (_) {}
      }
      // Supabase — use RLS-safe upsert
      if (_client != null && await _isOnline) {
        try {
          await _client.from('group_members').upsert(
            {'group_id': groupId, 'user_id': userId, 'joined_at': now},
            onConflict: 'group_id,user_id',
            ignoreDuplicates: true,
          );
        } catch (_) {}
      }
    }
  }

  /// Update expense: replaces splits. Offline-first, then sync. Web: Supabase only.
  Future<ExpenseModel?> updateExpense({
    required String expenseId,
    required String groupId,
    required String payerId,
    required Decimal amount,
    required String description,
    required String currency,
    required SplitType splitType,
    required List<SplitInsert> splits,
    String category = 'General',
    bool isIncome = false,
  }) async {
    final uid = await ensureUser();
    if (uid == null) return null;
    final now = _now();

    // Coerce empty string to null so wallet entries stay group_id IS NULL.
    final effectiveGroupId = groupId.isEmpty ? null : groupId;

    // -- Anchor logic: Always re-compute USD value on update --
    Decimal rateToUsd = Decimal.one;
    if (_currencyService != null) {
      rateToUsd = await _currencyService.getRateToUsd(currency);
    }
    final universalUsdAmount = (amount * rateToUsd).round(scale: 2);

          final expense = ExpenseModel(
            id: expenseId,
            groupId: effectiveGroupId,
            payerId: payerId,
            amount: amount.toString(),
            description: description,
            currency: currency,
            splitType: splitType,
            category: category,
            isIncome: isIncome,
            universalUsdAmount: universalUsdAmount.toString(),
            exchangeRateApplied: rateToUsd.toString(),
            createdBy: uid,
          );
    
          // Strip created_at so we never overwrite the original timestamp.
          final expenseData = expense.toJson()..remove('created_at');
    
          if (_isWeb && _client != null) {
            try {
              await _client
                  .from('expenses')
                  .update(expenseData)
                  .eq('id', expenseId);
              await _client.from('splits').delete().eq('expense_id', expenseId);
              for (final s in splits) {
                final usdOwed = (s.universalUsdOwed * rateToUsd).round(scale: 2);
                final split = SplitModel(
                  id: const Uuid().v4(),
                  expenseId: expenseId,
                  userId: s.userId,
                  universalUsdOwed: usdOwed.toString(),
                );
                await _client.from('splits').insert(split.toJson());
              }
              final res = await _client
                  .from('expenses')
                  .select()
                  .eq('id', expenseId)
                  .single();
              return ExpenseModel.fromJson(res);
            } catch (e) {
              if (e is PostgrestException) {
                debugPrint(
                    'PostgrestException in updateExpense: ${e.message}, code: ${e.code}, details: ${e.details}, hint: ${e.hint}');
              } else {
                debugPrint('Error in updateExpense (Supabase): $e');
              }
              return null;
            }
          }
    
          // Build split models with stable UUIDs shared by local + Supabase,
          // preventing _syncFromSupabase from duplicating rows on conflict.
          final updatedSplitModels = splits.map((s) {
            final usdOwed = (s.universalUsdOwed * rateToUsd).round(scale: 2);
            return SplitModel(
              id: const Uuid().v4(),
              expenseId: expenseId,
              userId: s.userId,
              universalUsdOwed: usdOwed.toString(),
            );
          }).toList();

          await LocalDatabase.db.update(
            'expenses',
            {...expenseData, 'synced_at': null}, // created_at already removed from expenseData
            where: 'id = ?',
            whereArgs: [expenseId],
          );
    
          await LocalDatabase.db.delete('splits', where: 'expense_id = ?', whereArgs: [expenseId]);
          for (final split in updatedSplitModels) {
            await LocalDatabase.db.insert('splits', {
              ...split.toJson(),
              'created_at': now,
              'synced_at': null,
            });
          }
    
          if (await _isOnline && _client != null) {
            try {
              await _client
                  .from('expenses')
                  .update(expenseData) // created_at already stripped
                  .eq('id', expenseId);
              await _client.from('splits').delete().eq('expense_id', expenseId);
              for (final split in updatedSplitModels) {
                await _client.from('splits').insert(split.toJson());
              }
              await LocalDatabase.db.update(
                'expenses',
                {'synced_at': DateTime.now().millisecondsSinceEpoch},
                where: 'id = ?',
                whereArgs: [expenseId],
              );
            } catch (e) {
              if (e is PostgrestException) {
                debugPrint(
                    'PostgrestException in updateExpense (mobile sync): ${e.message}, code: ${e.code}, details: ${e.details}, hint: ${e.hint}');
              } else {
                debugPrint('Error in updateExpense (mobile sync): $e');
              }
            }
          }
        final updatedRow = await LocalDatabase.db.query(
      'expenses',
      where: 'id = ?',
      whereArgs: [expenseId],
    );
    if (updatedRow.isEmpty) return null;
    final result = ExpenseModel.fromJson(updatedRow.first);
    _notify();
    return result;
  }

  Future<bool> deleteExpense(String expenseId) async {
    if (_isWeb && _client != null) {
      try {
        await _client.from('splits').delete().eq('expense_id', expenseId);
        await _client.from('expenses').delete().eq('id', expenseId);
        return true;
      } catch (_) {
        return false;
      }
    }

    // Remote-first: delete from Supabase before removing locally.
    // This ensures the deletion is authoritative — the reconciler in
    // _pullFromSupabase will not re-insert rows that were deleted on another device.
    if (await _isOnline && _client != null) {
      try {
        await _client.from('splits').delete().eq('expense_id', expenseId);
        await _client.from('expenses').delete().eq('id', expenseId);
      } catch (e) {
        debugPrint('[deleteExpense] Supabase delete failed: $e');
        // Proceed with local delete anyway so the UI stays responsive.
      }
    }

    await LocalDatabase.db.delete(
      'splits',
      where: 'expense_id = ?',
      whereArgs: [expenseId],
    );
    await LocalDatabase.db.delete(
      'expenses',
      where: 'id = ?',
      whereArgs: [expenseId],
    );
    _notify();
    return true;
  }

  /// Records a settlement by inserting a negating expense (category: 'Settlement')
  /// so the SettlementEngine sees the debt as zero on next calculation.
  ///
  /// [from] is the debtor (payer of the settlement expense).
  /// [to] is the creditor (the single split recipient).
  /// [amount] is the USD-normalised value from [SettlementTransaction].
  /// [currency] is the display currency label.
  Future<bool> recordSettlement({
    required String groupId,
    required String fromUserId,
    required String toUserId,
    required String amount,
    required String currency,
  }) async {
    final uid = await ensureUser();
    if (uid == null) return false;

    final expenseId = const Uuid().v4();
    final splitId   = const Uuid().v4();
    final now       = _now();

    final expenseRow = {
      'id':                   expenseId,
      'group_id':             groupId,
      'payer_id':             fromUserId,
      'amount':               amount,
      'description':          'Settlement',
      'currency':             currency,
      'split_type':           'even',
      'category':             'Settlement',
      'created_at':           now,
      'universal_usd_amount': amount,
    };

    final splitRow = {
      'id':                 splitId,
      'expense_id':         expenseId,
      'user_id':            toUserId,
      'universal_usd_owed': amount,
      'created_at':         now,
    };

    if (_isWeb && _client != null) {
      try {
        await _client.from('expenses').insert(expenseRow);
        await _client.from('splits').insert(splitRow);
        _notify();
        return true;
      } catch (e) {
        debugPrint('[recordSettlement] Supabase error: $e');
        return false;
      }
    }

    // Local-first path: write to SQLite immediately, sync later.
    try {
      await LocalDatabase.db.insert('expenses', {...expenseRow, 'synced_at': null});
      await LocalDatabase.db.insert('splits',   {...splitRow,   'synced_at': null});
    } catch (e) {
      debugPrint('[recordSettlement] SQLite error: $e');
      return false;
    }

    // Best-effort push to Supabase.
    if (await _isOnline && _client != null) {
      try {
        await _client.from('expenses').insert(expenseRow);
        await _client.from('splits').insert(splitRow);
        await LocalDatabase.db.update('expenses', {'synced_at': DateTime.now().millisecondsSinceEpoch},
            where: 'id = ?', whereArgs: [expenseId]);
        await LocalDatabase.db.update('splits', {'synced_at': DateTime.now().millisecondsSinceEpoch},
            where: 'id = ?', whereArgs: [splitId]);
      } catch (_) {}
    }

    _notify();
    return true;
  }

  /// Wipe all expenses and splits — local SQLite + Supabase.
  /// Supabase delete is scoped to groups the current user belongs to.
  Future<void> clearAllExpenses() async {
    // 1. Local SQLite
    if (!_isWeb) {
      await LocalDatabase.db.delete('splits');
      await LocalDatabase.db.delete('expenses');
    }

    // 2. Supabase
    if (_client != null) {
      try {
        final uid = await ensureUser();
        if (uid != null) {
          // Fetch group IDs the user belongs to, then delete scoped rows.
          final memberRows = await _client
              .from('group_members')
              .select('group_id')
              .eq('user_id', uid) as List;
          final groupIds = memberRows
              .map((r) => (r as Map<String, dynamic>)['group_id'] as String)
              .toList();
          if (groupIds.isNotEmpty) {
            // Delete splits for those expenses first (FK constraint).
            final expenseRows = await _client
                .from('expenses')
                .select('id')
                .inFilter('group_id', groupIds) as List;
            final expenseIds = expenseRows
                .map((r) => (r as Map<String, dynamic>)['id'] as String)
                .toList();
            if (expenseIds.isNotEmpty) {
              await _client
                  .from('splits')
                  .delete()
                  .inFilter('expense_id', expenseIds);
            }
            await _client
                .from('expenses')
                .delete()
                .inFilter('group_id', groupIds);
          }
        }
      } catch (e) {
        debugPrint('clearAllExpenses Supabase error: $e');
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Balance summaries (legacy – use BalanceService for correct conversion)
  // ---------------------------------------------------------------------------

      /// Legacy: only used for quick display. Use BalanceService for multi-currency.
      /// Prefers [universalUsdAmount] for schema v8+ expenses; sums raw amounts for
      /// same-currency groups (no conversion attempted here).
      Future<BalanceSummary> getBalanceSummary() async {
        final uid = await ensureUser();
        if (uid == null) return const BalanceSummary();
        final profile = await getCurrentUserProfile();
        final baseCurrency = profile?.defaultCurrency ?? 'USD';
  
        if (_isWeb && _client != null) {
          final raw = await getBalanceRawData(uid);
          var youOwe = Decimal.zero;
          var youAreOwed = Decimal.zero;
          for (final e in raw.youOwe) {
            youOwe += e.universalUsdAmount ?? e.amount;
          }
          for (final e in raw.youAreOwed) {
            youAreOwed += e.universalUsdAmount ?? e.amount;
          }
          return BalanceSummary(
            youOwe: youOwe.toStringAsFixed(2),
            youAreOwed: youAreOwed.toStringAsFixed(2),
            currency: baseCurrency,
          );
        }
  
        final raw = await getBalanceRawData(uid);
        var youOwe = Decimal.zero;
        var youAreOwed = Decimal.zero;
        for (final e in raw.youOwe) {
          youOwe += e.universalUsdAmount ?? e.amount;
        }
        for (final e in raw.youAreOwed) {
          youAreOwed += e.universalUsdAmount ?? e.amount;
        }
        return BalanceSummary(
          youOwe: youOwe.toStringAsFixed(2),
          youAreOwed: youAreOwed.toStringAsFixed(2),
          currency: baseCurrency,
        );
      }
  
      Future<BalanceSummary> getGroupBalanceSummary(String groupId) async {
        final uid = await ensureUser();
        if (uid == null) return const BalanceSummary();
        final profile = await getCurrentUserProfile();
        final baseCurrency = profile?.defaultCurrency ?? 'USD';
  
        final raw = await getGroupBalanceRawData(uid, groupId);
        if (raw == null) return BalanceSummary(currency: baseCurrency);
  
        var youOwe = Decimal.zero;
        var youAreOwed = Decimal.zero;
        for (final e in raw.youOwe) {
          youOwe += e.universalUsdAmount ?? e.amount;
        }
        for (final e in raw.youAreOwed) {
          youAreOwed += e.universalUsdAmount ?? e.amount;
        }
        return BalanceSummary(
          youOwe: youOwe.toStringAsFixed(2),
          youAreOwed: youAreOwed.toStringAsFixed(2),
          currency: baseCurrency,
        );
      }
    // ---------------------------------------------------------------------------
  // Simplified debts
  // ---------------------------------------------------------------------------

      /// Returns simplified debts for a group.
      ///
      /// [baseCurrency] should be the user's base currency (e.g. from
      /// [BalanceService.getBaseCurrency]). Amounts are normalised to base currency
      /// via [universal_usd_amount] (schema v8+). The returned [SettlementTransaction.currency]
      /// is [baseCurrency] so the UI can show a consistent denomination.
  
  Future<List<SettlementTransaction>> getSimplifiedDebts(
    String groupId, {
    String baseCurrency = 'USD',
  }) async {
    if (_isWeb && _client != null) {
      final expenseRows = await _client
          .from('expenses')
          .select()
          .eq('group_id', groupId) as List;
      if (expenseRows.isEmpty) return [];
      final expenseIds =
          expenseRows.map((r) => (r as Map<String, dynamic>)['id'] as String).toList();
      final splitRows = await _client
          .from('splits')
          .select()
          .inFilter('expense_id', expenseIds) as List;
      // Convert raw split data to SplitModel objects
      final splitModels = splitRows.map((row) {
        final splitMap = row as Map<String, dynamic>;
        return SplitModel.fromJson(splitMap);
      }).toList();
      
      return SettlementEngine.simplify(
        groupId: groupId,
        currency: baseCurrency,
        expenses: expenseRows.cast<Map<String, dynamic>>(),
        splits: splitModels,
      );
    }
    final expenseRows = await LocalDatabase.db.query(
      'expenses',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    if (expenseRows.isEmpty) return [];
    final expenseIds = expenseRows.map((r) => r['id'] as String).toList();
    final placeholders = expenseIds.map((_) => '?').join(',');
    final splitRows = await LocalDatabase.db.query(
      'splits',
      where: 'expense_id IN ($placeholders)',
      whereArgs: expenseIds,
    );
    // Convert raw split data to SplitModel objects
    final splitModels = splitRows.map((row) {
      final splitMap = row as Map<String, dynamic>;
      return SplitModel.fromJson(splitMap);
    }).toList();
    
    return SettlementEngine.simplify(
      groupId: groupId,
      currency: baseCurrency,
      expenses: expenseRows,
      splits: splitModels,
    );
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  String _now() => DateTime.now().toUtc().toIso8601String();

  GroupModel _rowToGroup(Map<String, dynamic> row) => GroupModel.fromJson(row);

  ExpenseModel _rowToExpense(Map<String, dynamic> row) =>
      ExpenseModel.fromJson(row);

  SplitModel _rowToSplit(Map<String, dynamic> row) => SplitModel.fromJson(row);
}

// ---------------------------------------------------------------------------
// Internal record for pending group-deleted activity events
// ---------------------------------------------------------------------------
class _DeletedGroupRecord {
  const _DeletedGroupRecord({
    required this.id,
    required this.name,
    required this.deletedAt,
    required this.deletedByUid,
  });
  final String id;
  final String name;
  final String deletedAt;
  final String deletedByUid;
}
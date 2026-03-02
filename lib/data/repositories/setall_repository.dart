import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../../core/utils/debt_simplification_engine.dart';
import '../../domain/entities/expense.dart';
import '../local/local_database.dart';
import '../models/expense_model.dart';
import '../models/group_model.dart';
import '../models/profile_model.dart';
import '../models/split_model.dart';
import '../../core/services/currency_service.dart';

const String _deviceUserIdKey = 'device_user_id';
const String _personalGroupName = 'Personal';

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

  Future<void> syncIfOnline() async {
    if (_isWeb) return;
    final uid = await ensureUser();
    if (uid != null && await _isOnline && _client != null) {
      await _syncFromSupabase(uid);
    }
  }

  Future<bool> get _isOnline async {
    if (kIsWeb) return _client != null;
    try {
      final result = await Connectivity().checkConnectivity();
      return result.contains(ConnectivityResult.wifi) ||
          result.contains(ConnectivityResult.mobile) ||
          result.contains(ConnectivityResult.ethernet) ||
          result.contains(ConnectivityResult.vpn);
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
    final youOwe = <BalanceEntry>[];
    final mySplits =
        await _client!.from('splits').select().eq('user_id', uid) as List;
    for (final row in mySplits) {
      final sMap = row as Map<String, dynamic>;
      final exList = await _client
          .from('expenses')
          .select()
          .eq('id', sMap['expense_id'] as String);
      if ((exList as List).isEmpty) continue;
      final ex = exList.first;
      if (ex['payer_id'] == uid) continue; // payer doesn't owe themselves
      youOwe.add(_makeEntry(sMap, ex));
    }

    final youAreOwed = <BalanceEntry>[];
    final myExpenses =
        await _client.from('expenses').select().eq('payer_id', uid) as List;
    for (final ex in myExpenses) {
      final exMap = ex as Map<String, dynamic>;
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

  Future<GroupModel> _getOrCreatePersonalGroup(String uid) async {
    if (_isWeb && _client != null) {
      final rows = await _client
          .from('groups')
          .select()
          .eq('creator_id', uid)
          .eq('name', _personalGroupName) as List;
      if (rows.isNotEmpty) return _rowToGroup(rows.first as Map<String, dynamic>);
      final id = const Uuid().v4();
      await _client
          .from('groups')
          .insert({'id': id, 'name': _personalGroupName, 'creator_id': uid});
      await _client
          .from('group_members')
          .insert({'group_id': id, 'user_id': uid});
      return GroupModel(id: id, name: _personalGroupName, creatorId: uid);
    }
    // Sync from Supabase first so we find any existing personal group
    // before creating a new one (prevents duplicates across devices).
    if (_client != null && await _isOnline) {
      try { await _syncFromSupabase(uid); } catch (_) {}
    }
    final rows = await LocalDatabase.db.query(
      'groups',
      where: 'creator_id = ? AND name = ?',
      whereArgs: [uid, _personalGroupName],
    );
    if (rows.isNotEmpty) return _rowToGroup(rows.first);
    final id = const Uuid().v4();
    final now = _now();
    await LocalDatabase.db.insert('groups', {
      'id': id,
      'name': _personalGroupName,
      'creator_id': uid,
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
    return GroupModel(id: id, name: _personalGroupName, creatorId: uid);
  }

  /// Returns all normal (non-direct) groups the user belongs to.
  /// Direct groups are shown separately in the Friends tab via [getDirectGroups].
  Future<List<GroupModel>> getMyGroups() async {
    final all = await _getGroupsByType(type: 'normal', includePersonal: true);
    // Deduplicate: keep only the first personal group encountered.
    bool seenPersonal = false;
    final deduped = <GroupModel>[];
    for (final g in all) {
      if (g.name == _personalGroupName) {
        if (seenPersonal) continue;
        seenPersonal = true;
      }
      deduped.add(g);
    }
    return deduped;
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
    if (includePersonal) await _getOrCreatePersonalGroup(uid);

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

    if (await _isOnline && _client != null) {
      try {
        await syncPendingToSupabase();
        await _syncFromSupabase(uid);
      } catch (_) {}
    }

    final memberRows = await LocalDatabase.db.query(
      'group_members',
      where: 'user_id = ?',
      whereArgs: [uid],
    );
    final memberIds =
        memberRows.map((r) => r['group_id'] as String).toSet().toList();
    final createdRows = await LocalDatabase.db.query(
      'groups',
      where: 'creator_id = ?',
      whereArgs: [uid],
    );
    final createdIds = createdRows.map((r) => r['id'] as String).toList();
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
          {'id': id, 'name': name, 'creator_id': uid});
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
      // Step 1: push group row — must succeed before group_members FK insert.
      bool groupSynced = false;
      try {
        await _client
            .from('groups')
            .insert({'id': id, 'name': name, 'creator_id': uid})
            .select()
            .single();
        groupSynced = true;
        await LocalDatabase.db.update(
          'groups',
          {'synced_at': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: [id],
        );
        debugPrint('[CreateGroup] Step1 group synced OK');
      } catch (e) {
        debugPrint('[CreateGroup] Step1 group sync FAILED: $e');
      }

      // Step 2: push creator's group_members row only if the group row is in
      // Supabase (FK constraint). The add_member_by_id RPC checks creator_id
      // OR group_members membership — this row is what makes it pass.
      if (groupSynced) {
        try {
          await _client
              .from('group_members')
              .insert({'group_id': id, 'user_id': uid});
          await LocalDatabase.db.update(
            'group_members',
            {'synced_at': DateTime.now().millisecondsSinceEpoch},
            where: 'group_id = ? AND user_id = ?',
            whereArgs: [id, uid],
          );
          debugPrint('[CreateGroup] Step2 group_members synced OK');
        } catch (e) {
          debugPrint('[CreateGroup] Step2 group_members sync FAILED: $e');
        }
      } else {
        debugPrint('[CreateGroup] Step2 skipped — group not in Supabase yet, addMemberById will fail');
      }
    }
    return GroupModel(id: id, name: name, creatorId: uid);
  }

  /// Delete a group. Only the creator can perform this action.
  Future<bool> deleteGroup(String groupId) async {
    final uid = await ensureUser();
    if (uid == null) return false;

    if (_isWeb && _client != null) {
      try {
        await _client.from('groups').delete().eq('id', groupId).eq('creator_id', uid);
        return true;
      } catch (_) {
        return false;
      }
    }

    // Local check
    final rows = await LocalDatabase.db.query(
      'groups',
      where: 'id = ? AND creator_id = ?',
      whereArgs: [groupId, uid],
    );
    if (rows.isEmpty) return false;

    await LocalDatabase.db.delete('group_members', where: 'group_id = ?', whereArgs: [groupId]);
    await LocalDatabase.db.delete('groups', where: 'id = ?', whereArgs: [groupId]);

    if (await _isOnline && _client != null) {
      try {
        await _client.from('groups').delete().eq('id', groupId).eq('creator_id', uid);
      } catch (_) {}
    }
    return true;
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

    if (await _isOnline && _client != null) await _syncFromSupabase(uid);
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
    required String groupId,
    required String payerId,
    required Decimal amount,
    required String description,
    required String currency,
    required SplitType splitType,
    required List<SplitInsert> splits,
    String category = 'General',
    Decimal? originalAmount,
    String? originalCurrency,
    String? exchangeRateApplied,
  }) async {
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
            createdAt: now,
            originalAmount: originalAmount?.toString(),
            originalCurrency: originalCurrency,
            exchangeRateApplied: exchangeRateApplied ?? rateToUsd.toString(),
            universalUsdAmount: universalUsdAmount.toString(),
          );
    
          final expenseData = expense.toJson();
    
          if (_isWeb && _client != null) {
            try {
                        await _client.from('expenses').insert(expenseData);
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
              
                    if (await _isOnline && _client != null) {
                      try {
                        await _client.from('expenses').insert(expenseData);
                        for (final split in splitModels) {
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
                    'PostgrestException in addExpense (mobile sync): ${e.message}, code: ${e.code}, details: ${e.details}, hint: ${e.hint}');
              } else {
                debugPrint('Error in addExpense (mobile sync): $e');
              }
            }
          }

    // Ensure all split participants are in group_members so they appear in
    // the members list even if they were never formally invited.
    await _ensureSplitParticipantsAreMembers(groupId, splits.map((s) => s.userId).toList());

    return expense;
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
  }) async {
    final now = _now();

    // -- Anchor logic: Always re-compute USD value on update --
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
            universalUsdAmount: universalUsdAmount.toString(),
            exchangeRateApplied: rateToUsd.toString(),
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
    return ExpenseModel.fromJson(updatedRow.first);
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
    if (await _isOnline && _client != null) {
      try {
        await _client.from('splits').delete().eq('expense_id', expenseId);
        await _client.from('expenses').delete().eq('id', expenseId);
      } catch (_) {}
    }
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
  
        if (await _isOnline && _client != null) await _syncFromSupabase(uid);
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
      /// via [universal_usd_amount] (schema v8+). The returned [SimplifiedDebt.currency]
      /// is [baseCurrency] so the UI can show a consistent denomination.
  
  Future<List<SimplifiedDebt>> getSimplifiedDebts(
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
      return DebtSimplificationEngine.simplify(
        groupId: groupId,
        currency: baseCurrency,
        expenses: expenseRows.cast<Map<String, dynamic>>(),
        splits: splitRows.cast<Map<String, dynamic>>(),
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
    return DebtSimplificationEngine.simplify(
      groupId: groupId,
      currency: baseCurrency,
      expenses: expenseRows,
      splits: splitRows,
    );
  }

  // ---------------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------------

  Future<void> _syncFromSupabase(String uid) async {
    if (_client == null || _isWeb) return;
    try {
      final memberRows = await _client
          .from('group_members')
          .select('group_id')
          .eq('user_id', uid);
      final memberIds = (memberRows as List)
          .map((e) => (e as Map<String, dynamic>)['group_id'] as String)
          .toSet()
          .toList();
      final created =
          await _client.from('groups').select('id').eq('creator_id', uid);
      for (final r in created as List) {
        memberIds.add((r as Map<String, dynamic>)['id'] as String);
      }
      if (memberIds.isEmpty) return;

      final groups =
          await _client.from('groups').select().inFilter('id', memberIds.toList());
      for (final g in groups as List) {
        final map = g as Map<String, dynamic>;
        await LocalDatabase.db.insert(
          'groups',
          {
            'id': map['id'],
            'name': map['name'],
            'creator_id': map['creator_id'],
            'created_at': map['created_at']?.toString(),
            'updated_at': map['updated_at']?.toString(),
            'synced_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final gMembers = await _client
          .from('group_members')
          .select()
          .inFilter('group_id', memberIds.toList());
      final allMemberUserIds = <String>{uid};
      for (final m in gMembers as List) {
        final map = m as Map<String, dynamic>;
        allMemberUserIds.add(map['user_id'] as String);
        await LocalDatabase.db.insert(
          'group_members',
          {
            'group_id': map['group_id'],
            'user_id': map['user_id'],
            'joined_at': map['joined_at']?.toString(),
            'synced_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      // Sync all member profiles (including current user) so local SQLite
      // always has fresh name / nickname / avatar_url / default_currency.
      try {
        final profileRows = await _client
            .from('profiles')
            .select()
            .inFilter('id', allMemberUserIds.toList()) as List;
        for (final p in profileRows) {
          await _upsertProfileToSQLite(p as Map<String, dynamic>);
        }
      } catch (_) {}

      final expenses =
          await _client.from('expenses').select().inFilter('group_id', memberIds.toList());
      for (final e in expenses as List) {
        final map = e as Map<String, dynamic>;
        final expense = ExpenseModel.fromJson(map);
        await LocalDatabase.db.insert(
          'expenses',
          {
            ...expense.toJson(),
            'updated_at': map['updated_at']?.toString(),
            'synced_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }

      final expenseIds = (expenses as List)
          .map((e) => (e as Map<String, dynamic>)['id'] as String)
          .toList();
      if (expenseIds.isNotEmpty) {
        final splits = await _client
            .from('splits')
            .select()
            .inFilter('expense_id', expenseIds);
        for (final s in splits as List) {
          final map = s as Map<String, dynamic>;
          final split = SplitModel.fromJson(map);
          // INSERT OR REPLACE leverages the UNIQUE(expense_id, user_id) index
          // (schema v9) to upsert without pre-deleting. If Supabase is missing
          // a split that exists locally (e.g. its INSERT failed), the local row
          // is left untouched because we only process what Supabase returns.
          await LocalDatabase.db.insert(
            'splits',
            {
              ...split.toJson(),
              'created_at': map['created_at']?.toString(),
              'synced_at': DateTime.now().millisecondsSinceEpoch,
            },
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      }
    } catch (_) {}
  }

  Future<void> syncPendingToSupabase() async {
    if (_client == null || !await _isOnline || _isWeb) return;
    final uid = await ensureUser();
    if (uid == null) return;

    final pendingGroups =
        await LocalDatabase.db.query('groups', where: 'synced_at IS NULL');
    for (final row in pendingGroups) {
      try {
        await _client.from('groups').insert({
          'id': row['id'],
          'name': row['name'],
          'creator_id': row['creator_id'],
        });
        await LocalDatabase.db.update(
          'groups',
          {'synced_at': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
        await _client.from('group_members').insert({
          'group_id': row['id'],
          'user_id': row['creator_id'],
        });
        await LocalDatabase.db.update(
          'group_members',
          {'synced_at': DateTime.now().millisecondsSinceEpoch},
          where: 'group_id = ?',
          whereArgs: [row['id']],
        );
      } catch (_) {}
    }

        final pendingExpenses =
            await LocalDatabase.db.query('expenses', where: 'synced_at IS NULL');
        for (final row in pendingExpenses) {
          try {
            final expense = ExpenseModel.fromJson(row);
            await _client.from('expenses').insert(expense.toJson());
            await LocalDatabase.db.update(
              'expenses',
              {'synced_at': DateTime.now().millisecondsSinceEpoch},
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          } catch (e) {
            if (e is PostgrestException) {
              if (e.code == '23505') {
                // DUPLICATE KEY: already in Supabase — mark synced locally.
                debugPrint('⚠️ Expense already exists in cloud. Marking as synced locally.');
              } else {
                // RLS violation (42501) or other permanent error — this row can
                // never be pushed by this user (e.g. stale test data with a
                // different payer_id). Mark synced to stop retrying.
                debugPrint('⚠️ Expense skipped (${e.code}): ${e.message}');
              }
              await LocalDatabase.db.update(
                'expenses',
                {'synced_at': DateTime.now().millisecondsSinceEpoch},
                where: 'id = ?',
                whereArgs: [row['id']],
              );
            }
          }
        }
    
        final pendingSplits =
            await LocalDatabase.db.query('splits', where: 'synced_at IS NULL');
        for (final row in pendingSplits) {
          try {
            final split = SplitModel.fromJson(row);
            await _client.from('splits').insert(split.toJson());
            await LocalDatabase.db.update(
              'splits',
              {'synced_at': DateTime.now().millisecondsSinceEpoch},
              where: 'id = ?',
              whereArgs: [row['id']],
            );
          } catch (e) {
            if (e is PostgrestException) {
              if (e.code != '23505') {
                debugPrint('⚠️ Split skipped (${e.code}): ${e.message}');
              }
              await LocalDatabase.db.update(
                'splits',
                {'synced_at': DateTime.now().millisecondsSinceEpoch},
                where: 'id = ?',
                whereArgs: [row['id']],
              );
            }
          }
        }
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
    
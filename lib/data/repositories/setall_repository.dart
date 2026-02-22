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

/// Balance summary for the current user (always in base currency).
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

/// One entry used by [BalanceService] to compute totals in the user's base
/// currency.
///
/// Resolution priority in BalanceService._toBase():
///   1. [baseAmountAtEntry] – frozen value (schema v4+, most reliable).
///   2. If [currency] == baseCurrency – return [amount] as-is (v1-v3 new data).
///   3. [exchangeRateApplied] – stored rate (v3 legacy data).
///   4. Live rate lookup (v1-v2 legacy data, last resort).
class BalanceEntry {
  const BalanceEntry({
    required this.amount,
    required this.currency,
    this.exchangeRateApplied,
    this.baseAmountAtEntry,
  });

  final Decimal amount;
  final String currency;
  final String? exchangeRateApplied;

  /// Pre-computed split share in the user's base currency at entry time.
  /// When non-null, [BalanceService] returns this directly without any
  /// conversion – eliminating the $104 offline-fallback bug permanently.
  final Decimal? baseAmountAtEntry;
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

    // Local DB (column additions require schema v6 — see local_database.dart)
    await LocalDatabase.db.update(
      'profiles',
      updates,
      where: 'id = ?',
      whereArgs: [uid],
    );
    // Mirror to Supabase when online
    if (await _isOnline && _client != null) {
      try {
        await _client.from('profiles').update(updates).eq('id', uid);
      } catch (_) {}
    }
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
    return _getBalanceRawDataLocal(uid);
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
    return _getGroupBalanceRawDataLocal(uid, groupId);
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

    final youOwe = <BalanceEntry>[];
    final youAreOwed = <BalanceEntry>[];
    for (final s in splitRows) {
      final ex = expenseById[s['expense_id'] as String]!;
      final entry = _makeEntry(s, ex);
      final splitUserId = s['user_id'] as String?;
      final payerId = ex['payer_id'] as String?;
      if (splitUserId == uid && payerId != uid) youOwe.add(entry);
      if (payerId == uid && splitUserId != uid) youAreOwed.add(entry);
    }
    return (youOwe: youOwe, youAreOwed: youAreOwed);
  }

  /// Construct a [BalanceEntry] from a split row and its parent expense row.
  ///
  /// When the expense has [universal_usd_amount] (schema v4+), we compute the
  /// split's proportional base amount to populate [BalanceEntry.baseAmountAtEntry].
  /// This allows [BalanceService._toBase] to skip any live rate lookup.
    BalanceEntry _makeEntry(
    Map<String, dynamic> splitRow,
    Map<String, dynamic> expenseRow,
  ) {
    // Splits are now natively USD! No more complex math.
    final splitAmount =
        Decimal.parse((splitRow['universal_usd_owed']?.toString()) ?? '0');

    return BalanceEntry(
      amount: splitAmount,
      currency: 'USD',
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
    return _getGroupsByType(type: 'normal', includePersonal: true);
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
    return rows.map(_rowToGroup).toList();
  }

  Future<GroupModel?> createGroup(String name) async {
    final uid = await ensureUser();
    if (uid == null) return null;
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
      try {
        await _client
            .from('groups')
            .insert({'id': id, 'name': name, 'creator_id': uid, 'type': 'normal'})
            .select()
            .single();
        await _client
            .from('group_members')
            .insert({'group_id': id, 'user_id': uid});
        await LocalDatabase.db.update(
          'groups',
          {'synced_at': DateTime.now().millisecondsSinceEpoch},
          where: 'id = ?',
          whereArgs: [id],
        );
        await LocalDatabase.db.update(
          'group_members',
          {'synced_at': DateTime.now().millisecondsSinceEpoch},
          where: 'group_id = ?',
          whereArgs: [id],
        );
      } catch (_) {}
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
    if (_isWeb && _client != null) {
      final rows = await _client
          .from('group_members')
          .select('user_id')
          .eq('group_id', groupId) as List;
      final userIds =
          rows.map((r) => (r as Map<String, dynamic>)['user_id'] as String).toSet().toList();
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
        return ProfileModel(
          id: m['id'] as String,
          name: m['name'] as String,
          defaultCurrency: (m['default_currency'] as String?) ?? 'USD',
        );
      }).toList();
    }
    final rows = await LocalDatabase.db.query(
      'group_members',
      where: 'group_id = ?',
      whereArgs: [groupId],
    );
    final userIds =
        rows.map((r) => r['user_id'] as String).toSet().toList();
    if (userIds.isEmpty) return [];

    // Find which user IDs are missing from local profiles table.
    final profileRows = await LocalDatabase.db.query(
      'profiles',
      where: 'id IN (${userIds.map((_) => '?').join(',')})',
      whereArgs: userIds,
    );
    final cachedIds = profileRows.map((r) => r['id'] as String).toSet();
    final missingIds = userIds.where((id) => !cachedIds.contains(id)).toList();

    // Pull missing profiles from Supabase and cache them.
    if (missingIds.isNotEmpty && _client != null && await _isOnline) {
      try {
        final fetched = await _client
            .from('profiles')
            .select()
            .inFilter('id', missingIds) as List;
        for (final p in fetched) {
          await _upsertProfileToSQLite(p as Map<String, dynamic>);
        }
        // Re-query so we include the newly cached rows.
        final refreshed = await LocalDatabase.db.query(
          'profiles',
          where: 'id IN (${userIds.map((_) => '?').join(',')})',
          whereArgs: userIds,
        );
        return refreshed.map((r) => ProfileModel.fromJson(r)).toList();
      } catch (_) {}
    }

    if (profileRows.isEmpty) {
      return userIds
          .map((id) => ProfileModel(id: id, name: 'Member', defaultCurrency: 'USD'))
          .toList();
    }
    return profileRows.map((r) => ProfileModel.fromJson(r)).toList();
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
    await _client!.rpc('add_member_by_email', params: {
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
    return rows.map(_rowToExpense).toList();
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
    return rows.map(_rowToExpense).toList();
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
    return rows.map(_rowToSplit).toList();
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
      baseAmountAtEntry: universalUsdAmount.toString(),
    );

    final expenseData = expense.toJson();

    if (_isWeb && _client != null) {
      try {
        await _client.from('expenses').insert(expenseData);
        for (final s in splits) {
          // Calculate proportional universal_usd_owed
          final usdOwed = (s.amountOwed * rateToUsd).round(scale: 2);
          final split = SplitModel(
            id: const Uuid().v4(),
            expenseId: expenseId,
            userId: s.userId,
            amountOwed: usdOwed.toString(),
          );
          await _client.from('splits').insert(split.toJson());
        }
        return expense;
      } catch (e) {
        if (e is PostgrestException) {
          debugPrint('PostgrestException in addExpense: ${e.message}, code: ${e.code}, details: ${e.details}, hint: ${e.hint}');
        } else {
          debugPrint('Error in addExpense (Supabase): $e');
        }
        return null;
      }
    }

    // Local SQLite
    await LocalDatabase.db.insert('expenses', {
      ...expenseData,
      'synced_at': null,
    });
    for (final s in splits) {
      final usdOwed = (s.amountOwed * rateToUsd).round(scale: 2);
      final split = SplitModel(
        id: const Uuid().v4(),
        expenseId: expenseId,
        userId: s.userId,
        amountOwed: usdOwed.toString(),
      );
      await LocalDatabase.db.insert('splits', {
        ...split.toJson(),
        'created_at': now,
        'synced_at': null,
      });
    }

    if (await _isOnline && _client != null) {
      try {
        await _client.from('expenses').insert(expenseData);
        for (final s in splits) {
          final usdOwed = (s.amountOwed * rateToUsd).round(scale: 2);
          final split = SplitModel(
            id: const Uuid().v4(),
            expenseId: expenseId,
            userId: s.userId,
            amountOwed: usdOwed.toString(),
          );
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
          debugPrint('PostgrestException in addExpense (mobile sync): ${e.message}, code: ${e.code}, details: ${e.details}, hint: ${e.hint}');
        } else {
          debugPrint('Error in addExpense (mobile sync): $e');
        }
      }
    }

    return expense;
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
      // Note: We might want to fetch the original createdAt and currency normalization fields here
      // but following the requested logic of using toJson() as the source.
      baseAmountAtEntry: universalUsdAmount.toString(),
      exchangeRateApplied: rateToUsd.toString(),
    );

    final expenseData = expense.toJson();

    if (_isWeb && _client != null) {
      try {
        await _client
            .from('expenses')
            .update(expenseData)
            .eq('id', expenseId);
        await _client.from('splits').delete().eq('expense_id', expenseId);
        for (final s in splits) {
          final usdOwed = (s.amountOwed * rateToUsd).round(scale: 2);
          final split = SplitModel(
            id: const Uuid().v4(),
            expenseId: expenseId,
            userId: s.userId,
            amountOwed: usdOwed.toString(),
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
          debugPrint('PostgrestException in updateExpense: ${e.message}, code: ${e.code}, details: ${e.details}, hint: ${e.hint}');
        } else {
          debugPrint('Error in updateExpense (Supabase): $e');
        }
        return null;
      }
    }

    await LocalDatabase.db.update(
      'expenses',
      {...expenseData, 'synced_at': null},
      where: 'id = ?',
      whereArgs: [expenseId],
    );

    final existingSplits = await LocalDatabase.db.query(
      'splits',
      where: 'expense_id = ?',
      whereArgs: [expenseId],
    );
    for (final row in existingSplits) {
      await LocalDatabase.db.delete(
        'splits',
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
    for (final s in splits) {
      final usdOwed = (s.amountOwed * rateToUsd).round(scale: 2);
      final split = SplitModel(
        id: const Uuid().v4(),
        expenseId: expenseId,
        userId: s.userId,
        amountOwed: usdOwed.toString(),
      );
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
            .update(expenseData)
            .eq('id', expenseId);
        await _client.from('splits').delete().eq('expense_id', expenseId);
        for (final s in splits) {
          final usdOwed = (s.amountOwed * rateToUsd).round(scale: 2);
          final split = SplitModel(
            id: const Uuid().v4(),
            expenseId: expenseId,
            userId: s.userId,
            amountOwed: usdOwed.toString(),
          );
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
          debugPrint('PostgrestException in updateExpense (mobile sync): ${e.message}, code: ${e.code}, details: ${e.details}, hint: ${e.hint}');
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

  // ---------------------------------------------------------------------------
  // Balance summaries (legacy – use BalanceService for correct conversion)
  // ---------------------------------------------------------------------------

  /// Legacy: only used for quick display. Use BalanceService for multi-currency.
  /// Prefers [baseAmountAtEntry] for schema v4+ expenses; sums raw amounts for
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
        youOwe += e.baseAmountAtEntry ?? e.amount;
      }
      for (final e in raw.youAreOwed) {
        youAreOwed += e.baseAmountAtEntry ?? e.amount;
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
      youOwe += e.baseAmountAtEntry ?? e.amount;
    }
    for (final e in raw.youAreOwed) {
      youAreOwed += e.baseAmountAtEntry ?? e.amount;
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
      youOwe += e.baseAmountAtEntry ?? e.amount;
    }
    for (final e in raw.youAreOwed) {
      youAreOwed += e.baseAmountAtEntry ?? e.amount;
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
  /// via [universal_usd_amount] (schema v4+). The returned [SimplifiedDebt.currency]
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
          debugPrint('PostgrestException in syncPendingToSupabase (expenses): ${e.message}, code: ${e.code}, details: ${e.details}, hint: ${e.hint}');
        } else {
          debugPrint('Error in syncPendingToSupabase (expenses): $e');
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
          debugPrint('PostgrestException in syncPendingToSupabase (splits): ${e.message}, code: ${e.code}, details: ${e.details}, hint: ${e.hint}');
        } else {
          debugPrint('Error in syncPendingToSupabase (splits): $e');
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  String _now() => DateTime.now().toUtc().toIso8601String();

  GroupModel _rowToGroup(Map<String, dynamic> row) => GroupModel.fromJson(row);

  ExpenseModel _rowToExpense(Map<String, dynamic> row) => ExpenseModel.fromJson(row);

  SplitModel _rowToSplit(Map<String, dynamic> row) => SplitModel.fromJson(row);
}

class SplitInsert {
  const SplitInsert({required this.userId, required this.amountOwed});
  final String userId;
  final Decimal amountOwed;
}

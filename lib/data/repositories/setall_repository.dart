import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
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

const String _deviceUserIdKey = 'device_user_id';
const String _personalGroupName = 'Personal';

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

/// Raw balance entry for multi-currency conversion (amount + expense currency + optional rate already applied).
class BalanceEntry {
  const BalanceEntry({
    required this.amount,
    required this.currency,
    this.exchangeRateApplied,
  });

  final Decimal amount;
  final String currency;
  final String? exchangeRateApplied;
}

/// Central repository: offline-first. Writes go to local SQLite first, then sync to Supabase when online.
/// When Supabase is not configured, all data stays on device. Uses device user id from SharedPreferences.
class SetAllRepository {
  SetAllRepository({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  String? _deviceUserId;

  bool get isConfigured => _client != null;

  /// True when running on web (Supabase-only; no local SQLite).
  bool get _isWeb => LocalDatabase.isWeb;

  /// Current user id: Supabase auth user when signed in, or device-local UUID when Supabase not configured. Null when Supabase is configured but user has not signed in.
  String? get currentUserId {
    if (_client != null) {
      final id = _client!.auth.currentUser?.id;
      if (id != null) return id;
      return null;
    }
    return _deviceUserId;
  }

  /// Current user id (Supabase session or device id when offline/no Supabase). Null when Supabase is configured but user has not signed in.
  Future<String?> ensureUser() async {
    if (_client != null) {
      final user = _client!.auth.currentUser;
      if (user != null) return user.id;
      return null;
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

  /// Sync local DB from Supabase when online (call before balance/expense reads). No-op on web.
  Future<void> syncIfOnline() async {
    if (_isWeb) return;
    final uid = await ensureUser();
    if (uid != null && await _isOnline && _client != null) await _syncFromSupabase(uid);
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

  Future<LocalDatabase> get _local async => LocalDatabase.instance;

  /// Current user profile (for base currency). Returns null if no profile row.
  Future<ProfileModel?> getCurrentUserProfile() async {
    final uid = await ensureUser();
    if (uid == null) return null;
    if (_isWeb && _client != null) {
      final res = await _client!.from('profiles').select().eq('id', uid).maybeSingle();
      if (res == null) return null;
      final r = res as Map<String, dynamic>;
      return ProfileModel(
        id: r['id'] as String,
        name: r['name'] as String,
        defaultCurrency: (r['default_currency'] as String?) ?? 'USD',
      );
    }
    final rows = await LocalDatabase.db.query('profiles', where: 'id = ?', whereArgs: [uid]);
    if (rows.isEmpty) return null;
    final r = rows.first;
    return ProfileModel(
      id: r['id'] as String,
      name: r['name'] as String,
      defaultCurrency: (r['default_currency'] as String?) ?? 'USD',
    );
  }

  /// Raw balance data for conversion to base: each entry has amount, currency, and optional exchange_rate_applied.
  Future<({List<BalanceEntry> youOwe, List<BalanceEntry> youAreOwed})> getBalanceRawData(String uid) async {
    if (_isWeb && _client != null) {
      final youOwe = <BalanceEntry>[];
      final mySplits = await _client!.from('splits').select().eq('user_id', uid) as List;
      for (final row in mySplits) {
        final map = row as Map<String, dynamic>;
        final exList = await _client!.from('expenses').select().eq('id', map['expense_id']);
        if (exList.isEmpty) continue;
        final ex = (exList as List).first as Map<String, dynamic>;
        youOwe.add(BalanceEntry(
          amount: Decimal.parse((map['amount_owed']?.toString()) ?? '0'),
          currency: (ex['currency'] as String?) ?? 'USD',
          exchangeRateApplied: ex['exchange_rate_applied']?.toString(),
        ));
      }
      final youAreOwed = <BalanceEntry>[];
      final myExpenses = await _client!.from('expenses').select().eq('payer_id', uid) as List;
      for (final ex in myExpenses) {
        final exMap = ex as Map<String, dynamic>;
        final payerId = exMap['payer_id'] as String?;
        final splits = await _client!.from('splits').select().eq('expense_id', exMap['id']) as List;
        final currency = (exMap['currency'] as String?) ?? 'USD';
        final rate = exMap['exchange_rate_applied']?.toString();
        for (final s in splits) {
          final sMap = s as Map<String, dynamic>;
          if (sMap['user_id'] == payerId) continue; // exclude self: you are not owed by yourself
          youAreOwed.add(BalanceEntry(
            amount: Decimal.parse((sMap['amount_owed']?.toString()) ?? '0'),
            currency: currency,
            exchangeRateApplied: rate,
          ));
        }
      }
      return (youOwe: youOwe, youAreOwed: youAreOwed);
    }
    final youOwe = <BalanceEntry>[];
    final mySplits = await LocalDatabase.db.query('splits', where: 'user_id = ?', whereArgs: [uid]);
    for (final row in mySplits) {
      final expenseRows = await LocalDatabase.db.query('expenses', where: 'id = ?', whereArgs: [row['expense_id']]);
      if (expenseRows.isEmpty) continue;
      final ex = expenseRows.first;
      youOwe.add(BalanceEntry(
        amount: Decimal.parse((row['amount_owed'] as String?) ?? '0'),
        currency: (ex['currency'] as String?) ?? 'USD',
        exchangeRateApplied: ex['exchange_rate_applied'] as String?,
      ));
    }

    final youAreOwed = <BalanceEntry>[];
    final myExpenses = await LocalDatabase.db.query('expenses', where: 'payer_id = ?', whereArgs: [uid]);
    for (final ex in myExpenses) {
      final payerId = ex['payer_id'] as String?;
      final splits = await LocalDatabase.db.query('splits', where: 'expense_id = ?', whereArgs: [ex['id']]);
      final currency = (ex['currency'] as String?) ?? 'USD';
      final rate = ex['exchange_rate_applied'] as String?;
      for (final s in splits) {
        if (s['user_id'] == payerId) continue; // exclude self
        youAreOwed.add(BalanceEntry(
          amount: Decimal.parse((s['amount_owed'] as String?) ?? '0'),
          currency: currency,
          exchangeRateApplied: rate,
        ));
      }
    }
    return (youOwe: youOwe, youAreOwed: youAreOwed);
  }

  /// Group-scoped raw balance. Null if no expenses in group.
  Future<({List<BalanceEntry> youOwe, List<BalanceEntry> youAreOwed})?> getGroupBalanceRawData(String uid, String groupId) async {
    if (_isWeb && _client != null) {
      final expenseRows = await _client!.from('expenses').select().eq('group_id', groupId) as List;
      if (expenseRows.isEmpty) return null;
      final expenseIds = expenseRows.map((r) => (r as Map<String, dynamic>)['id'] as String).toList();
      final splitsRaw = await _client!.from('splits').select().inFilter('expense_id', expenseIds) as List;
      final expenseById = {for (final e in expenseRows) (e as Map<String, dynamic>)['id'] as String: e};
      final youOwe = <BalanceEntry>[];
      final youAreOwed = <BalanceEntry>[];
      for (final s in splitsRaw) {
        final sMap = s as Map<String, dynamic>;
        final ex = expenseById[sMap['expense_id'] as String] as Map<String, dynamic>;
        final currency = (ex['currency'] as String?) ?? 'USD';
        final rate = ex['exchange_rate_applied']?.toString();
        final amount = Decimal.parse((sMap['amount_owed']?.toString()) ?? '0');
        final entry = BalanceEntry(amount: amount, currency: currency, exchangeRateApplied: rate);
        if (sMap['user_id'] == uid) youOwe.add(entry);
        if (ex['payer_id'] == uid && sMap['user_id'] != ex['payer_id']) youAreOwed.add(entry); // exclude self
      }
      return (youOwe: youOwe, youAreOwed: youAreOwed);
    }
    final expenseRows = await LocalDatabase.db.query('expenses', where: 'group_id = ?', whereArgs: [groupId]);
    if (expenseRows.isEmpty) return null;
    final expenseIds = expenseRows.map((r) => r['id'] as String).toList();
    final placeholders = expenseIds.map((_) => '?').join(',');
    final splitRows = await LocalDatabase.db.query('splits', where: 'expense_id IN ($placeholders)', whereArgs: expenseIds);
    final expenseById = {for (final e in expenseRows) e['id'] as String: e};

    final youOwe = <BalanceEntry>[];
    final youAreOwed = <BalanceEntry>[];
    for (final s in splitRows) {
      final ex = expenseById[s['expense_id'] as String]!;
      final currency = (ex['currency'] as String?) ?? 'USD';
      final rate = ex['exchange_rate_applied'] as String?;
      final amount = Decimal.parse((s['amount_owed'] as String?) ?? '0');
      final entry = BalanceEntry(amount: amount, currency: currency, exchangeRateApplied: rate);
      if (s['user_id'] == uid) {
        youOwe.add(entry);
      }
      if (ex['payer_id'] == uid) {
        youAreOwed.add(entry);
      }
    }
    return (youOwe: youOwe, youAreOwed: youAreOwed);
  }

  /// Ensure Personal group exists for current user (local + optional Supabase).
  Future<GroupModel> _getOrCreatePersonalGroup(String uid) async {
    if (_isWeb && _client != null) {
      final rows = await _client!.from('groups').select().eq('creator_id', uid).eq('name', _personalGroupName) as List;
      if (rows.isNotEmpty) return _rowToGroup((rows.first as Map<String, dynamic>));
      final id = const Uuid().v4();
      await _client!.from('groups').insert({'id': id, 'name': _personalGroupName, 'creator_id': uid});
      await _client!.from('group_members').insert({'group_id': id, 'user_id': uid});
      return GroupModel(id: id, name: _personalGroupName, creatorId: uid);
    }
    final db = await _local;
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

  String _now() => DateTime.now().toUtc().toIso8601String();

  GroupModel _rowToGroup(Map<String, dynamic> row) => GroupModel(
        id: row['id'] as String,
        name: row['name'] as String,
        creatorId: row['creator_id'] as String,
      );

  /// Fetch groups (from local; sync from Supabase when online). On web: Supabase only.
  Future<List<GroupModel>> getMyGroups() async {
    final uid = await ensureUser();
    if (uid == null) return [];

    await _getOrCreatePersonalGroup(uid!);

    if (_isWeb && _client != null) {
      final memberRows = await _client!.from('group_members').select('group_id').eq('user_id', uid) as List;
      final memberIds = (memberRows.map((e) => (e as Map<String, dynamic>)['group_id'] as String).toSet().toList());
      final created = await _client!.from('groups').select('id').eq('creator_id', uid) as List;
      for (final r in created) {
        memberIds.add((r as Map<String, dynamic>)['id'] as String);
      }
      if (memberIds.isEmpty) return [];
      final rows = await _client!.from('groups').select().inFilter('id', memberIds).order('updated_at', ascending: false) as List;
      return rows.map((r) => _rowToGroup(r as Map<String, dynamic>)).toList();
    }

    if (await _isOnline && _client != null) {
      await syncPendingToSupabase();
      await _syncFromSupabase(uid!);
    }

    final db = await _local;
    final memberRows = await LocalDatabase.db.query('group_members', where: 'user_id = ?', whereArgs: [uid]);
    final memberIds = memberRows.map((r) => r['group_id'] as String).toSet().toList();
    final createdRows = await LocalDatabase.db.query('groups', where: 'creator_id = ?', whereArgs: [uid]);
    final createdIds = createdRows.map((r) => r['id'] as String).toList();
    final allIds = <String>{...memberIds, ...createdIds}.toList();
    if (allIds.isEmpty) return [];

    final rows = await LocalDatabase.db.query('groups', where: 'id IN (${allIds.map((_) => '?').join(',')})', whereArgs: allIds, orderBy: 'updated_at DESC');
    return rows.map(_rowToGroup).toList();
  }

  Future<void> _syncFromSupabase(String uid) async {
    if (_client == null || _isWeb) return;
    try {
      final memberRows = await _client!.from('group_members').select('group_id').eq('user_id', uid);
      final memberIds = (memberRows as List).map((e) => (e as Map<String, dynamic>)['group_id'] as String).toSet().toList();
      final created = await _client!.from('groups').select('id').eq('creator_id', uid);
      for (final r in created as List) {
        memberIds.add((r as Map<String, dynamic>)['id'] as String);
      }
      if (memberIds.isEmpty) return;
      final groups = await _client!.from('groups').select().inFilter('id', memberIds.toList());
      final db = await _local;
      for (final g in groups as List) {
        final map = g as Map<String, dynamic>;
        await LocalDatabase.db.insert('groups', {
          'id': map['id'],
          'name': map['name'],
          'creator_id': map['creator_id'],
          'created_at': map['created_at']?.toString(),
          'updated_at': map['updated_at']?.toString(),
          'synced_at': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      final gMembers = await _client!.from('group_members').select().inFilter('group_id', memberIds.toList());
      for (final m in gMembers as List) {
        final map = m as Map<String, dynamic>;
        await LocalDatabase.db.insert('group_members', {
          'group_id': map['group_id'],
          'user_id': map['user_id'],
          'joined_at': map['joined_at']?.toString(),
          'synced_at': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      final expenses = await _client!.from('expenses').select().inFilter('group_id', memberIds.toList());
      for (final e in expenses as List) {
        final map = e as Map<String, dynamic>;
        await LocalDatabase.db.insert('expenses', {
          'id': map['id'],
          'group_id': map['group_id'],
          'payer_id': map['payer_id'],
          'amount': map['amount']?.toString(),
          'description': map['description'],
          'currency': map['currency'],
          'split_type': map['split_type'],
          'category': map['category'],
          'original_amount': map['original_amount']?.toString(),
          'original_currency': map['original_currency'],
          'exchange_rate_applied': map['exchange_rate_applied']?.toString(),
          'created_at': map['created_at']?.toString(),
          'updated_at': map['updated_at']?.toString(),
          'synced_at': DateTime.now().millisecondsSinceEpoch,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      final expenseIds = (expenses as List).map((e) => (e as Map<String, dynamic>)['id'] as String).toList();
      if (expenseIds.isNotEmpty) {
        final splits = await _client!.from('splits').select().inFilter('expense_id', expenseIds);
        for (final s in splits as List) {
          final map = s as Map<String, dynamic>;
          await LocalDatabase.db.insert('splits', {
            'id': map['id'],
            'expense_id': map['expense_id'],
            'user_id': map['user_id'],
            'amount_owed': map['amount_owed']?.toString(),
            'created_at': map['created_at']?.toString(),
            'synced_at': DateTime.now().millisecondsSinceEpoch,
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      }
    } catch (_) {}
  }

  /// Push pending local changes to Supabase. No-op on web.
  Future<void> syncPendingToSupabase() async {
    if (_client == null || !await _isOnline || _isWeb) return;
    final db = await _local;
    final uid = await ensureUser();
    if (uid == null) return;

    final pendingGroups = await LocalDatabase.db.query('groups', where: 'synced_at IS NULL');
    for (final row in pendingGroups) {
      try {
        await _client!.from('groups').insert({
          'id': row['id'],
          'name': row['name'],
          'creator_id': row['creator_id'],
        });
        await LocalDatabase.db.update('groups', {'synced_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [row['id']]);
        await _client!.from('group_members').insert({'group_id': row['id'], 'user_id': row['creator_id']});
        await LocalDatabase.db.update('group_members', {'synced_at': DateTime.now().millisecondsSinceEpoch}, where: 'group_id = ?', whereArgs: [row['id']]);
      } catch (_) {}
    }

    final pendingExpenses = await LocalDatabase.db.query('expenses', where: 'synced_at IS NULL');
    for (final row in pendingExpenses) {
      try {
        final expenseData = {
          'id': row['id'],
          'group_id': row['group_id'],
          'payer_id': row['payer_id'],
          'amount': row['amount'],
          'description': row['description'] ?? '',
          'currency': row['currency'] ?? 'USD',
          'split_type': row['split_type'] ?? 'even',
        };
        if (row['category'] != null) expenseData['category'] = row['category'];
        if (row['original_amount'] != null) expenseData['original_amount'] = row['original_amount'];
        if (row['original_currency'] != null) expenseData['original_currency'] = row['original_currency'];
        if (row['exchange_rate_applied'] != null) expenseData['exchange_rate_applied'] = row['exchange_rate_applied'];
        await _client!.from('expenses').insert(expenseData);
        await LocalDatabase.db.update('expenses', {'synced_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [row['id']]);
      } catch (_) {}
    }

    final pendingSplits = await LocalDatabase.db.query('splits', where: 'synced_at IS NULL');
    for (final row in pendingSplits) {
      try {
        await _client!.from('splits').insert({
          'id': row['id'],
          'expense_id': row['expense_id'],
          'user_id': row['user_id'],
          'amount_owed': row['amount_owed'],
        });
        await LocalDatabase.db.update('splits', {'synced_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [row['id']]);
      } catch (_) {}
    }
  }

  Future<List<ProfileModel>> getGroupMembers(String groupId) async {
    if (_isWeb && _client != null) {
      final rows = await _client!.from('group_members').select('user_id').eq('group_id', groupId) as List;
      final userIds = rows.map((r) => (r as Map<String, dynamic>)['user_id'] as String).toSet().toList();
      if (userIds.isEmpty) return [];
      final profileRows = await _client!.from('profiles').select().inFilter('id', userIds) as List;
      if (profileRows.isEmpty) {
        return userIds.map((id) => ProfileModel(id: id, name: 'Member', defaultCurrency: 'USD')).toList();
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
    final db = await _local;
    final rows = await LocalDatabase.db.query('group_members', where: 'group_id = ?', whereArgs: [groupId]);
    final userIds = rows.map((r) => r['user_id'] as String).toSet().toList();
    if (userIds.isEmpty) return [];

    final profileRows = await LocalDatabase.db.query('profiles', where: 'id IN (${userIds.map((_) => '?').join(',')})', whereArgs: userIds);
    if (profileRows.isEmpty) {
      return userIds.map((id) => ProfileModel(id: id, name: 'Member', defaultCurrency: 'USD')).toList();
    }
    return profileRows.map((r) => ProfileModel(
      id: r['id'] as String,
      name: r['name'] as String,
      defaultCurrency: (r['default_currency'] as String?) ?? 'USD',
    )).toList();
  }

  /// Deprecated: use [BalanceService.getBalanceSummary] for correct multi-currency conversion.
  Future<BalanceSummary> getBalanceSummary() async {
    final uid = await ensureUser();
    if (uid == null) return const BalanceSummary();
    if (_isWeb) {
      final raw = await getBalanceRawData(uid);
      var youOwe = Decimal.zero;
      for (final e in raw.youOwe) { youOwe += e.amount; }
      var youAreOwed = Decimal.zero;
      for (final e in raw.youAreOwed) { youAreOwed += e.amount; }
      final profile = await getCurrentUserProfile();
      return BalanceSummary(
        youOwe: youOwe.toStringAsFixed(2),
        youAreOwed: youAreOwed.toStringAsFixed(2),
        currency: profile?.defaultCurrency ?? 'USD',
      );
    }
    if (await _isOnline && _client != null) await _syncFromSupabase(uid);
    var youOwe = Decimal.zero;
    final mySplits = await LocalDatabase.db.query('splits', where: 'user_id = ?', whereArgs: [uid]);
    for (final row in mySplits) {
      youOwe += Decimal.parse((row['amount_owed'] as String?) ?? '0');
    }
    var youAreOwed = Decimal.zero;
    final myExpenses = await LocalDatabase.db.query('expenses', where: 'payer_id = ?', whereArgs: [uid]);
    for (final ex in myExpenses) {
      final splits = await LocalDatabase.db.query('splits', where: 'expense_id = ?', whereArgs: [ex['id']]);
      for (final s in splits) {
        youAreOwed += Decimal.parse((s['amount_owed'] as String?) ?? '0');
      }
    }
    final profile = await getCurrentUserProfile();
    return BalanceSummary(
      youOwe: youOwe.toStringAsFixed(2),
      youAreOwed: youAreOwed.toStringAsFixed(2),
      currency: profile?.defaultCurrency ?? 'USD',
    );
  }

  Future<List<ExpenseModel>> getRecentExpenses({int limit = 20}) async {
    final uid = await ensureUser();
    if (uid == null) return [];

    if (_isWeb && _client != null) {
      final memberRows = await _client!.from('group_members').select('group_id').eq('user_id', uid) as List;
      final groupIds = (memberRows.map((r) => (r as Map<String, dynamic>)['group_id'] as String).toSet().toList());
      final created = await _client!.from('groups').select('id').eq('creator_id', uid) as List;
      for (final r in created) {
        groupIds.add((r as Map<String, dynamic>)['id'] as String);
      }
      if (groupIds.isEmpty) return [];
      final rows = await _client!.from('expenses').select().inFilter('group_id', groupIds).order('created_at', ascending: false).limit(limit) as List;
      return rows.map((r) => _rowToExpense(r as Map<String, dynamic>)).toList();
    }

    if (await _isOnline && _client != null) await _syncFromSupabase(uid);
    final db = await _local;
    final memberRows = await LocalDatabase.db.query('group_members', where: 'user_id = ?', whereArgs: [uid]);
    final groupIds = memberRows.map((r) => r['group_id'] as String).toSet().toList();
    final created = await LocalDatabase.db.query('groups', where: 'creator_id = ?', whereArgs: [uid]);
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
      final rows = await _client!.from('expenses').select().eq('group_id', groupId).order('created_at', ascending: false) as List;
      return rows.map((r) => _rowToExpense(r as Map<String, dynamic>)).toList();
    }
    final rows = await LocalDatabase.db.query('expenses', where: 'group_id = ?', whereArgs: [groupId], orderBy: 'created_at DESC');
    return rows.map(_rowToExpense).toList();
  }

  /// Group-scoped balance for current user (you owe / you are owed in this group only).
  Future<BalanceSummary> getGroupBalanceSummary(String groupId) async {
    final uid = await ensureUser();
    if (uid == null) return const BalanceSummary();

    if (_isWeb && _client != null) {
      final raw = await getGroupBalanceRawData(uid, groupId);
      if (raw == null) return const BalanceSummary(currency: 'USD');
      var youOwe = Decimal.zero;
      for (final e in raw.youOwe) { youOwe += e.amount; }
      var youAreOwed = Decimal.zero;
      for (final e in raw.youAreOwed) { youAreOwed += e.amount; }
      final profile = await getCurrentUserProfile();
      return BalanceSummary(
        youOwe: youOwe.toStringAsFixed(2),
        youAreOwed: youAreOwed.toStringAsFixed(2),
        currency: profile?.defaultCurrency ?? 'USD',
      );
    }

    final expenseRows = await LocalDatabase.db.query('expenses', where: 'group_id = ?', whereArgs: [groupId]);
    final expenseIds = expenseRows.map((r) => r['id'] as String).toList();
    if (expenseIds.isEmpty) return const BalanceSummary(currency: 'USD');

    var youOwe = Decimal.zero;
    var youAreOwed = Decimal.zero;
    String currency = 'USD';

    final placeholders = expenseIds.map((_) => '?').join(',');
    final splitRows = await LocalDatabase.db.query('splits', where: 'expense_id IN ($placeholders)', whereArgs: expenseIds);

    for (final s in splitRows) {
      if (s['user_id'] == uid) {
        youOwe += Decimal.parse((s['amount_owed'] as String?) ?? '0');
      }
    }
    for (final ex in expenseRows) {
      if (ex['payer_id'] == uid) {
        currency = (ex['currency'] as String?) ?? 'USD';
        for (final s in splitRows) {
          if (s['expense_id'] == ex['id'] && s['user_id'] != ex['payer_id']) {
            youAreOwed += Decimal.parse((s['amount_owed'] as String?) ?? '0');
          }
        }
      }
    }
    if (expenseRows.isNotEmpty && currency == 'USD') {
      currency = (expenseRows.first['currency'] as String?) ?? 'USD';
    }

    return BalanceSummary(
      youOwe: youOwe.toStringAsFixed(2),
      youAreOwed: youAreOwed.toStringAsFixed(2),
      currency: currency,
    );
  }

  /// Simplified debts for group only (minimal transactions). Uses Decimal only.
  Future<List<SimplifiedDebt>> getSimplifiedDebts(String groupId) async {
    if (_isWeb && _client != null) {
      final expenseRows = await _client!.from('expenses').select().eq('group_id', groupId) as List;
      if (expenseRows.isEmpty) return [];
      final expenseIds = expenseRows.map((r) => (r as Map<String, dynamic>)['id'] as String).toList();
      final splitRows = await _client!.from('splits').select().inFilter('expense_id', expenseIds) as List;
      final currency = ((expenseRows.first as Map<String, dynamic>)['currency'] as String?) ?? 'USD';
      return DebtSimplificationEngine.simplify(
        groupId: groupId,
        currency: currency,
        expenses: expenseRows.cast<Map<String, dynamic>>(),
        splits: splitRows.cast<Map<String, dynamic>>(),
      );
    }
    final expenseRows = await LocalDatabase.db.query('expenses', where: 'group_id = ?', whereArgs: [groupId]);
    if (expenseRows.isEmpty) return [];

    final expenseIds = expenseRows.map((r) => r['id'] as String).toList();
    final placeholders = expenseIds.map((_) => '?').join(',');
    final splitRows = await LocalDatabase.db.query('splits', where: 'expense_id IN ($placeholders)', whereArgs: expenseIds);

    final currency = (expenseRows.first['currency'] as String?) ?? 'USD';
    return DebtSimplificationEngine.simplify(
      groupId: groupId,
      currency: currency,
      expenses: expenseRows,
      splits: splitRows,
    );
  }

  ExpenseModel _rowToExpense(Map<String, dynamic> row) => ExpenseModel(
        id: row['id'] as String,
        groupId: row['group_id'] as String,
        payerId: row['payer_id'] as String,
        amount: row['amount'] as String,
        description: (row['description'] as String?) ?? '',
        currency: (row['currency'] as String?) ?? 'USD',
        splitType: _splitTypeFromString(row['split_type'] as String?),
        category: (row['category'] as String?) ?? 'General',
        createdAt: row['created_at'] as String?,
      );

  SplitType _splitTypeFromString(String? v) {
    switch (v) {
      case 'manual':
        return SplitType.manual;
      case 'parts':
        return SplitType.parts;
      default:
        return SplitType.even;
    }
  }

  /// Create group: save to local first (always works), then try Supabase. On web: Supabase only.
  Future<GroupModel?> createGroup(String name) async {
    final uid = await ensureUser();
    if (uid == null) return null;

    final id = const Uuid().v4();

    if (_isWeb && _client != null) {
      await _client!.from('groups').insert({'id': id, 'name': name, 'creator_id': uid});
      await _client!.from('group_members').insert({'group_id': id, 'user_id': uid});
      return GroupModel(id: id, name: name, creatorId: uid);
    }

    final now = _now();
    final db = await _local;
    await LocalDatabase.db.insert('groups', {
      'id': id,
      'name': name,
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

    if (await _isOnline && _client != null) {
      try {
        await _client!.from('groups').insert({'id': id, 'name': name, 'creator_id': uid}).select().single();
        await _client!.from('group_members').insert({'group_id': id, 'user_id': uid});
        await LocalDatabase.db.update('groups', {'synced_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [id]);
        await LocalDatabase.db.update('group_members', {'synced_at': DateTime.now().millisecondsSinceEpoch}, where: 'group_id = ?', whereArgs: [id]);
      } catch (_) {}
    }

    return GroupModel(id: id, name: name, creatorId: uid);
  }

  /// Get a single expense by id.
  Future<ExpenseModel?> getExpense(String expenseId) async {
    if (_isWeb && _client != null) {
      final res = await _client!.from('expenses').select().eq('id', expenseId).maybeSingle();
      if (res == null) return null;
      return _rowToExpense(res as Map<String, dynamic>);
    }
    final rows = await LocalDatabase.db.query('expenses', where: 'id = ?', whereArgs: [expenseId]);
    if (rows.isEmpty) return null;
    return _rowToExpense(rows.first);
  }

  /// Get splits for an expense (for edit / display).
  Future<List<SplitModel>> getSplitsForExpense(String expenseId) async {
    if (_isWeb && _client != null) {
      final rows = await _client!.from('splits').select().eq('expense_id', expenseId) as List;
      return rows.map((r) => _rowToSplit(r as Map<String, dynamic>)).toList();
    }
    final rows = await LocalDatabase.db.query('splits', where: 'expense_id = ?', whereArgs: [expenseId]);
    return rows.map(_rowToSplit).toList();
  }

  SplitModel _rowToSplit(Map<String, dynamic> row) => SplitModel(
        id: row['id'] as String,
        expenseId: row['expense_id'] as String,
        userId: row['user_id'] as String,
        amountOwed: row['amount_owed'] as String,
      );

  /// Add expense: save to local first, then try Supabase. On web: Supabase only.
  /// [amount] and [splits] must be in base currency when [exchangeRateApplied] is provided.
  /// When [originalAmount]/[originalCurrency]/[exchangeRateApplied] are set, [currency] is the base currency for storage.
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

    if (_isWeb && _client != null) {
      try {
        final expenseData = {
          'id': expenseId,
          'group_id': groupId,
          'payer_id': payerId,
          'amount': amount.toString(),
          'description': description,
          'currency': currency,
          'split_type': splitType.name,
        };
        if (category.isNotEmpty) expenseData['category'] = category;
        if (originalAmount != null) expenseData['original_amount'] = originalAmount.toString();
        if (originalCurrency != null) expenseData['original_currency'] = originalCurrency;
        if (exchangeRateApplied != null) expenseData['exchange_rate_applied'] = exchangeRateApplied;
        await _client!.from('expenses').insert(expenseData);
        for (final s in splits) {
          await _client!.from('splits').insert({
            'expense_id': expenseId,
            'user_id': s.userId,
            'amount_owed': s.amountOwed.toString(),
          });
        }
        return ExpenseModel(
          id: expenseId,
          groupId: groupId,
          payerId: payerId,
          amount: amount.toString(),
          description: description,
          currency: currency,
          splitType: splitType,
          category: category,
          createdAt: now,
        );
      } catch (_) {
        return null;
      }
    }

    await LocalDatabase.db.insert('expenses', {
      'id': expenseId,
      'group_id': groupId,
      'payer_id': payerId,
      'amount': amount.toString(),
      'description': description,
      'currency': currency,
      'split_type': splitType.name,
      'category': category,
      'original_amount': originalAmount?.toString(),
      'original_currency': originalCurrency,
      'exchange_rate_applied': exchangeRateApplied,
      'created_at': now,
      'updated_at': now,
      'synced_at': null,
    });

    for (final s in splits) {
      await LocalDatabase.db.insert('splits', {
        'id': const Uuid().v4(),
        'expense_id': expenseId,
        'user_id': s.userId,
        'amount_owed': s.amountOwed.toString(),
        'created_at': now,
        'synced_at': null,
      });
    }

    if (await _isOnline && _client != null) {
      try {
        final expenseData = {
          'id': expenseId,
          'group_id': groupId,
          'payer_id': payerId,
          'amount': amount.toString(),
          'description': description,
          'currency': currency,
          'split_type': splitType.name,
        };
        if (category.isNotEmpty) expenseData['category'] = category;
        if (originalAmount != null) expenseData['original_amount'] = originalAmount.toString();
        if (originalCurrency != null) expenseData['original_currency'] = originalCurrency;
        if (exchangeRateApplied != null) expenseData['exchange_rate_applied'] = exchangeRateApplied;
        await _client!.from('expenses').insert(expenseData).select().single();
        for (final s in splits) {
          await _client!.from('splits').insert({
            'expense_id': expenseId,
            'user_id': s.userId,
            'amount_owed': s.amountOwed.toString(),
          });
        }
        await LocalDatabase.db.update('expenses', {'synced_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [expenseId]);
      } catch (_) {}
    }

    return ExpenseModel(
      id: expenseId,
      groupId: groupId,
      payerId: payerId,
      amount: amount.toString(),
      description: description,
      currency: currency,
      splitType: splitType,
      category: category,
      createdAt: now,
    );
  }

  /// Update expense: replace splits. Offline-first, then sync. On web: Supabase only.
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

    if (_isWeb && _client != null) {
      try {
        await _client!.from('expenses').update({
          'payer_id': payerId,
          'amount': amount.toString(),
          'description': description,
          'currency': currency,
          'split_type': splitType.name,
          'category': category,
        }).eq('id', expenseId);
        await _client!.from('splits').delete().eq('expense_id', expenseId);
        for (final s in splits) {
          await _client!.from('splits').insert({
            'expense_id': expenseId,
            'user_id': s.userId,
            'amount_owed': s.amountOwed.toString(),
          });
        }
        final res = await _client!.from('expenses').select().eq('id', expenseId).single() as Map<String, dynamic>;
        return ExpenseModel(
          id: expenseId,
          groupId: groupId,
          payerId: payerId,
          amount: amount.toString(),
          description: description,
          currency: currency,
          splitType: splitType,
          category: category,
          createdAt: res['created_at']?.toString(),
        );
      } catch (_) {
        return null;
      }
    }

    await LocalDatabase.db.update(
      'expenses',
      {
        'payer_id': payerId,
        'amount': amount.toString(),
        'description': description,
        'currency': currency,
        'split_type': splitType.name,
        'category': category,
        'updated_at': now,
        'synced_at': null,
      },
      where: 'id = ?',
      whereArgs: [expenseId],
    );

    final existingSplits = await LocalDatabase.db.query('splits', where: 'expense_id = ?', whereArgs: [expenseId]);
    for (final row in existingSplits) {
      await LocalDatabase.db.delete('splits', where: 'id = ?', whereArgs: [row['id']]);
    }

    for (final s in splits) {
      await LocalDatabase.db.insert('splits', {
        'id': const Uuid().v4(),
        'expense_id': expenseId,
        'user_id': s.userId,
        'amount_owed': s.amountOwed.toString(),
        'created_at': now,
        'synced_at': null,
      });
    }

    if (await _isOnline && _client != null) {
      try {
        await _client!.from('expenses').update({
          'payer_id': payerId,
          'amount': amount.toString(),
          'description': description,
          'currency': currency,
          'split_type': splitType.name,
        }).eq('id', expenseId);
        await _client!.from('splits').delete().eq('expense_id', expenseId);
        for (final s in splits) {
          await _client!.from('splits').insert({
            'expense_id': expenseId,
            'user_id': s.userId,
            'amount_owed': s.amountOwed.toString(),
          });
        }
        await LocalDatabase.db.update('expenses', {'synced_at': DateTime.now().millisecondsSinceEpoch}, where: 'id = ?', whereArgs: [expenseId]);
      } catch (_) {}
    }

    final updatedRow = await LocalDatabase.db.query('expenses', where: 'id = ?', whereArgs: [expenseId]);
    final createdAt = updatedRow.isNotEmpty ? updatedRow.first['created_at'] as String? : null;
    return ExpenseModel(
      id: expenseId,
      groupId: groupId,
      payerId: payerId,
      amount: amount.toString(),
      description: description,
      currency: currency,
      splitType: splitType,
      category: category,
      createdAt: createdAt,
    );
  }

  /// Delete expense and its splits. Offline-first, then sync. On web: Supabase only.
  Future<bool> deleteExpense(String expenseId) async {
    if (_isWeb && _client != null) {
      try {
        await _client!.from('splits').delete().eq('expense_id', expenseId);
        await _client!.from('expenses').delete().eq('id', expenseId);
        return true;
      } catch (_) {
        return false;
      }
    }
    await LocalDatabase.db.delete('splits', where: 'expense_id = ?', whereArgs: [expenseId]);
    await LocalDatabase.db.delete('expenses', where: 'id = ?', whereArgs: [expenseId]);

    if (await _isOnline && _client != null) {
      try {
        await _client!.from('splits').delete().eq('expense_id', expenseId);
        await _client!.from('expenses').delete().eq('id', expenseId);
      } catch (_) {}
    }
    return true;
  }

  /// Add member by email (Supabase RPC). Optionally notify by email via Edge Function.
  Future<void> addMemberByEmail(String groupId, String email, {bool sendEmail = true, String? groupName}) async {
    if (_client != null && await _isOnline) {
      await _client!.rpc('add_member_by_email', params: {'p_group_id': groupId, 'p_email': email.trim().toLowerCase()});
      if (sendEmail) {
        try {
          await _client!.functions.invoke('notify-group-invite', body: {
            'email': email.trim(),
            'groupId': groupId,
            'groupName': groupName ?? 'a group',
          });
        } catch (_) {}
      }
    }
  }
}

class SplitInsert {
  const SplitInsert({required this.userId, required this.amountOwed});
  final String userId;
  final Decimal amountOwed;
}

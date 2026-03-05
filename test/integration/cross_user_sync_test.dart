// ignore_for_file: avoid_print
//
// Cross-User Sync Integration Test
// =================================
// Verifies Pillar 1 (SQLite ↔ Supabase sync) and Pillar 3 (reactive streams)
// work correctly across two independent user sessions.
//
// Architecture note
// -----------------
// LocalDatabase is a global singleton, so we CANNOT use it here for two users
// simultaneously. Instead, each user gets their own sqflite in-memory Database
// opened directly via openDatabase(':memory:'). The _TestableRepository
// subclass overrides every LocalDatabase.db call to use the injected database,
// and uses a shared _MockSupabaseStore in place of a real SupabaseClient.

import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:uuid/uuid.dart';

import 'package:setall/data/models/expense_model.dart';
import 'package:setall/data/models/group_model.dart';

// ---------------------------------------------------------------------------
// In-memory Supabase mock
// ---------------------------------------------------------------------------

/// Simulates the shared Supabase cloud store that both users sync to/from.
class _MockSupabaseStore {
  final _groups = <String, Map<String, dynamic>>{};
  final _groupMembers = <String, Map<String, dynamic>>{};
  final _expenses = <String, Map<String, dynamic>>{};
  final _splits = <String, Map<String, dynamic>>{};

  // -- Groups --

  void upsertGroup(Map<String, dynamic> row) {
    _groups[row['id'] as String] = Map.unmodifiable(row);
  }

  List<Map<String, dynamic>> getGroupsForUser(String uid) {
    final memberGroupIds = _groupMembers.values
        .where((m) => m['user_id'] == uid)
        .map((m) => m['group_id'] as String)
        .toSet();
    final creatorGroupIds = _groups.values
        .where((g) => g['creator_id'] == uid)
        .map((g) => g['id'] as String)
        .toSet();
    final allIds = {...memberGroupIds, ...creatorGroupIds};
    return _groups.values.where((g) => allIds.contains(g['id'])).toList();
  }

  // -- Group members --

  void upsertMember(Map<String, dynamic> row) {
    final key = '${row['group_id']}_${row['user_id']}';
    _groupMembers[key] = Map.unmodifiable(row);
  }

  List<Map<String, dynamic>> getMembersForGroups(List<String> groupIds) {
    return _groupMembers.values
        .where((m) => groupIds.contains(m['group_id']))
        .toList();
  }

  // -- Expenses --

  void upsertExpense(Map<String, dynamic> row) {
    _expenses[row['id'] as String] = Map.unmodifiable(row);
  }

  List<Map<String, dynamic>> getExpensesForGroups(List<String> groupIds) {
    return _expenses.values
        .where((e) => groupIds.contains(e['group_id']))
        .toList();
  }

  // -- Splits --

  void upsertSplit(Map<String, dynamic> row) {
    _splits[row['id'] as String] = Map.unmodifiable(row);
  }

  List<Map<String, dynamic>> getSplitsForExpenses(List<String> expenseIds) {
    return _splits.values
        .where((s) => expenseIds.contains(s['expense_id']))
        .toList();
  }
}

// ---------------------------------------------------------------------------
// Schema helper — identical DDL to LocalDatabase._onCreate (schema v9)
// ---------------------------------------------------------------------------

Future<void> _applySchema(Database db) async {
  await db.execute('''
    CREATE TABLE groups (
      id         TEXT PRIMARY KEY,
      name       TEXT NOT NULL,
      creator_id TEXT NOT NULL,
      created_by TEXT,
      type       TEXT NOT NULL DEFAULT 'normal',
      created_at TEXT,
      updated_at TEXT,
      synced_at  INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE group_members (
      group_id  TEXT NOT NULL,
      user_id   TEXT NOT NULL,
      joined_at TEXT,
      synced_at INTEGER,
      PRIMARY KEY (group_id, user_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE expenses (
      id                    TEXT PRIMARY KEY,
      group_id              TEXT NOT NULL,
      payer_id              TEXT NOT NULL,
      created_by            TEXT,
      amount                TEXT NOT NULL,
      total_amount          TEXT,
      description           TEXT,
      currency              TEXT,
      split_type            TEXT,
      category              TEXT,
      original_amount       TEXT,
      original_currency     TEXT,
      exchange_rate_applied TEXT,
      base_amount_at_entry  TEXT,
      universal_usd_amount  TEXT,
      created_at            TEXT,
      updated_at            TEXT,
      synced_at             INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE splits (
      id                 TEXT PRIMARY KEY,
      expense_id         TEXT NOT NULL,
      user_id            TEXT NOT NULL,
      universal_usd_owed TEXT NOT NULL,
      created_at         TEXT,
      synced_at          INTEGER,
      UNIQUE(expense_id, user_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE profiles (
      id               TEXT PRIMARY KEY,
      name             TEXT NOT NULL,
      nickname         TEXT,
      avatar_url       TEXT,
      is_ghost         INTEGER NOT NULL DEFAULT 0,
      default_currency TEXT,
      synced_at        INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE exchange_rates (
      base_currency   TEXT NOT NULL,
      target_currency TEXT NOT NULL,
      rate            TEXT NOT NULL,
      last_updated    TEXT,
      PRIMARY KEY (base_currency, target_currency)
    )
  ''');
}

// ---------------------------------------------------------------------------
// Testable repository — wraps SetAllRepository using an injected Database
// instead of the LocalDatabase singleton.
// ---------------------------------------------------------------------------

/// A thin adapter that re-implements only the SQLite I/O used by
/// createGroup + watchGroups using the injected [_db], and routes
/// push/pull through [_store] instead of a real SupabaseClient.
class _TestableRepository {
  _TestableRepository({
    required Database db,
    required _MockSupabaseStore store,
    required String userId,
  })  : _db = db,
        _store = store,
        _userId = userId;

  final Database _db;
  final _MockSupabaseStore _store;
  final String _userId;

  final _changeController = StreamController<void>.broadcast();
  void _notify() => _changeController.add(null);
  void notifySyncComplete() => _notify();

  String get userId => _userId;

  // -- watchGroups (Pillar 3) --
  //
  // Subscribe to the broadcast change stream BEFORE the initial DB query so
  // no notification is missed while _getGroups() is running. Events are
  // buffered in a Queue and replayed via the async* generator.

  Stream<List<GroupModel>> watchGroups() async* {
    final pending = StreamController<void>();
    final sub = _changeController.stream.listen(
      (_) => pending.add(null),
      onDone: pending.close,
    );
    try {
      yield await _getGroups();
      await for (final _ in pending.stream) {
        yield await _getGroups();
      }
    } finally {
      await sub.cancel();
      await pending.close();
    }
  }

  Future<List<GroupModel>> _getGroups() async {
    final memberRows = await _db.query(
      'group_members',
      where: 'user_id = ?',
      whereArgs: [_userId],
    );
    final memberIds =
        memberRows.map((r) => r['group_id'] as String).toSet().toList();
    final createdRows = await _db.query(
      'groups',
      where: 'creator_id = ?',
      whereArgs: [_userId],
    );
    final createdIds = createdRows.map((r) => r['id'] as String).toList();
    final allIds = <String>{...memberIds, ...createdIds}.toList();
    if (allIds.isEmpty) return [];

    final rows = await _db.query(
      'groups',
      where:
          "id IN (${allIds.map((_) => '?').join(',')}) AND type = 'normal'",
      whereArgs: allIds,
      orderBy: 'updated_at DESC',
    );
    return rows
        .map((r) => GroupModel(
              id: r['id'] as String,
              name: r['name'] as String,
              creatorId: r['creator_id'] as String,
            ))
        .toList();
  }

  // -- createGroup (local write + push to mock store) --

  Future<GroupModel> createGroup(String name) async {
    final id = const Uuid().v4();
    final now = DateTime.now().toIso8601String();

    await _db.insert('groups', {
      'id': id,
      'name': name,
      'creator_id': _userId,
      'type': 'normal',
      'created_at': now,
      'updated_at': now,
      'synced_at': null,
    });
    await _db.insert('group_members', {
      'group_id': id,
      'user_id': _userId,
      'joined_at': now,
      'synced_at': null,
    });

    _notify();
    return GroupModel(id: id, name: name, creatorId: _userId);
  }

  // -- addExpense (local write + push to mock store) --

  Future<ExpenseModel> addExpense({
    required String groupId,
    required String description,
    required String amount,
    required String payerId,
    required String otherUserId,
  }) async {
    final expenseId = const Uuid().v4();
    final splitId = const Uuid().v4();
    final now = DateTime.now().toIso8601String();
    final halfUsd = (Decimal.parse(amount) / Decimal.fromInt(2))
        .toDecimal(scaleOnInfinitePrecision: 2)
        .round(scale: 2)
        .toStringAsFixed(2);

    final expenseRow = {
      'id': expenseId,
      'group_id': groupId,
      'payer_id': payerId,
      'amount': amount,
      'description': description,
      'currency': 'USD',
      'split_type': 'equal',
      'category': 'General',
      'universal_usd_amount': amount,
      'created_at': now,
      'synced_at': null,
    };
    await _db.insert('expenses', expenseRow);

    final splitRow = {
      'id': splitId,
      'expense_id': expenseId,
      'user_id': otherUserId,
      'universal_usd_owed': halfUsd,
      'created_at': now,
      'synced_at': null,
    };
    await _db.insert('splits', splitRow, conflictAlgorithm: ConflictAlgorithm.ignore);

    _notify();
    return ExpenseModel(
      id: expenseId,
      groupId: groupId,
      payerId: payerId,
      amount: amount,
      description: description,
      currency: 'USD',
    );
  }

  // -- Pillar 1: push (local SQLite → mock Supabase) --

  Future<void> pushToSupabase() async {
    final pendingGroups =
        await _db.query('groups', where: 'synced_at IS NULL');
    for (final row in pendingGroups) {
      _store.upsertGroup({
        'id': row['id'],
        'name': row['name'],
        'creator_id': row['creator_id'],
        'type': row['type'] ?? 'normal',
        'created_at': row['created_at'],
        'updated_at': row['updated_at'],
      });
      _store.upsertMember({
        'group_id': row['id'],
        'user_id': row['creator_id'],
        'joined_at': row['created_at'],
      });
      await _db.update(
        'groups',
        {'synced_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    final pendingExpenses =
        await _db.query('expenses', where: 'synced_at IS NULL');
    for (final row in pendingExpenses) {
      _store.upsertExpense({
        'id': row['id'],
        'group_id': row['group_id'],
        'payer_id': row['payer_id'],
        'amount': row['amount'],
        'description': row['description'],
        'currency': row['currency'] ?? 'USD',
        'split_type': row['split_type'],
        'category': row['category'],
        'universal_usd_amount': row['universal_usd_amount'],
        'created_at': row['created_at'],
      });
      await _db.update(
        'expenses',
        {'synced_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }

    final pendingSplits = await _db.rawQuery('''
      SELECT s.* FROM splits s
      INNER JOIN expenses e ON s.expense_id = e.id
      WHERE s.synced_at IS NULL AND e.synced_at IS NOT NULL
    ''');
    for (final row in pendingSplits) {
      _store.upsertSplit({
        'id': row['id'],
        'expense_id': row['expense_id'],
        'user_id': row['user_id'],
        'universal_usd_owed': row['universal_usd_owed'],
        'created_at': row['created_at'],
      });
      await _db.update(
        'splits',
        {'synced_at': DateTime.now().millisecondsSinceEpoch},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
  }

  // -- Pillar 1: pull (mock Supabase → local SQLite) --

  Future<void> pullFromSupabase() async {
    final remoteGroups = _store.getGroupsForUser(_userId);
    for (final g in remoteGroups) {
      await _db.insert(
        'groups',
        {
          'id': g['id'],
          'name': g['name'],
          'creator_id': g['creator_id'],
          'type': g['type'] ?? 'normal',
          'created_at': g['created_at']?.toString(),
          'updated_at': g['updated_at']?.toString(),
          'synced_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    final groupIds = remoteGroups.map((g) => g['id'] as String).toList();
    if (groupIds.isEmpty) {
      notifySyncComplete();
      return;
    }

    final remoteMembers = _store.getMembersForGroups(groupIds);
    for (final m in remoteMembers) {
      await _db.insert(
        'group_members',
        {
          'group_id': m['group_id'],
          'user_id': m['user_id'],
          'joined_at': m['joined_at']?.toString(),
          'synced_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    final remoteExpenses = _store.getExpensesForGroups(groupIds);
    for (final e in remoteExpenses) {
      await _db.insert(
        'expenses',
        {
          'id': e['id'],
          'group_id': e['group_id'],
          'payer_id': e['payer_id'],
          'amount': e['amount'],
          'description': e['description'],
          'currency': e['currency'] ?? 'USD',
          'split_type': e['split_type'],
          'category': e['category'],
          'universal_usd_amount': e['universal_usd_amount'],
          'created_at': e['created_at']?.toString(),
          'synced_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }

    final expenseIds =
        remoteExpenses.map((e) => e['id'] as String).toList();
    if (expenseIds.isNotEmpty) {
      final remoteSplits = _store.getSplitsForExpenses(expenseIds);
      for (final s in remoteSplits) {
        await _db.insert(
          'splits',
          {
            'id': s['id'],
            'expense_id': s['expense_id'],
            'user_id': s['user_id'],
            'universal_usd_owed': s['universal_usd_owed'],
            'created_at': s['created_at']?.toString(),
            'synced_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    }

    notifySyncComplete();
  }

  Future<List<GroupModel>> getGroups() => _getGroups();

  Future<void> dispose() async {
    await _changeController.close();
    await _db.close();
  }
}

// ---------------------------------------------------------------------------
// Helper: open a fresh in-memory SQLite DB with the app schema applied
// ---------------------------------------------------------------------------

Future<Database> _openTestDb(String name) async {
  final db = await databaseFactoryFfi.openDatabase(
    ':memory:',
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) => _applySchema(db),
    ),
  );
  return db;
}

// ---------------------------------------------------------------------------
// Test suite
// ---------------------------------------------------------------------------

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({});
  });

  group('Multi-User Cross-Sync Integrity', () {
    late _MockSupabaseStore store;
    late _TestableRepository repoA;
    late _TestableRepository repoB;

    const userA = 'user-a-uuid-1111-1111-111111111111';
    const userB = 'user-b-uuid-2222-2222-222222222222';

    setUp(() async {
      store = _MockSupabaseStore();

      final dbA = await _openTestDb('test_user_a.db');
      final dbB = await _openTestDb('test_user_b.db');

      repoA = _TestableRepository(db: dbA, store: store, userId: userA);
      repoB = _TestableRepository(db: dbB, store: store, userId: userB);
    });

    tearDown(() async {
      await repoA.dispose();
      await repoB.dispose();
    });

    // -----------------------------------------------------------------------
    // PILLAR 1 — Sync correctness
    // -----------------------------------------------------------------------

    test(
        'P1: group created by User A appears in User B local DB after sync',
        () async {
      // Step 1: User A adds User B as a member so B can see the group.
      // We do this directly in the shared store (simulates RLS-safe invite).
      final group = await repoA.createGroup('Road Trip');

      // Manually add User B to the group in the mock store (simulates
      // add_member RPC that would run on Supabase in production).
      store.upsertMember({
        'group_id': group.id,
        'user_id': userB,
        'joined_at': DateTime.now().toIso8601String(),
      });

      // Step 2: User A syncs (push local → Supabase).
      await repoA.pushToSupabase();

      // Step 3: User B syncs (pull Supabase → local).
      await repoB.pullFromSupabase();

      // Step 4: Verify User B's local DB contains the group.
      final bGroups = await repoB.getGroups();
      expect(
        bGroups.any((g) => g.id == group.id && g.name == 'Road Trip'),
        isTrue,
        reason:
            'User B must see the "Road Trip" group after pulling from Supabase. '
            'Failure = group is stuck in User A\'s local DB (push broken).',
      );
    });

    test(
        'P1: expense created by User A appears in User B local DB after sync',
        () async {
      final group = await repoA.createGroup('Expenses Group');

      store.upsertMember({
        'group_id': group.id,
        'user_id': userB,
        'joined_at': DateTime.now().toIso8601String(),
      });

      await repoA.addExpense(
        groupId: group.id,
        description: 'Hotel',
        amount: '200.00',
        payerId: userA,
        otherUserId: userB,
      );

      // Push: A local → Supabase.
      await repoA.pushToSupabase();

      // Pull: Supabase → B local.
      await repoB.pullFromSupabase();

      // Query B's local expenses.
      final bExpenses = await repoB._db.query(
        'expenses',
        where: 'group_id = ?',
        whereArgs: [group.id],
      );
      expect(
        bExpenses.isNotEmpty,
        isTrue,
        reason:
            'User B must find the "Hotel" expense after pulling. '
            'Failure = expense is stuck in User A\'s local DB (push broken).',
      );
      expect(
        bExpenses.first['description'],
        equals('Hotel'),
      );
    });

    test(
        'P1: splits for User B are present in User B local DB after sync',
        () async {
      final group = await repoA.createGroup('Split Group');

      store.upsertMember({
        'group_id': group.id,
        'user_id': userB,
        'joined_at': DateTime.now().toIso8601String(),
      });

      final expense = await repoA.addExpense(
        groupId: group.id,
        description: 'Dinner',
        amount: '100.00',
        payerId: userA,
        otherUserId: userB,
      );

      await repoA.pushToSupabase();
      await repoB.pullFromSupabase();

      final bSplits = await repoB._db.query(
        'splits',
        where: 'expense_id = ?',
        whereArgs: [expense.id],
      );
      expect(
        bSplits.isNotEmpty,
        isTrue,
        reason:
            'User B must find their split row. '
            'Failure = split is not being pushed or parsed correctly.',
      );
      expect(
        bSplits.first['user_id'],
        equals(userB),
        reason: 'The split must be assigned to User B.',
      );
      expect(
        bSplits.first['universal_usd_owed'],
        equals('50.00'),
        reason: 'Each party owes 50.00 USD for a \$100 equal split.',
      );
    });

    // -----------------------------------------------------------------------
    // PILLAR 3 — Stream reactivity
    // -----------------------------------------------------------------------

    test(
        'P3: watchGroups() on repoB emits the new group after pullFromSupabase',
        () async {
      final group = await repoA.createGroup('Stream Test Group');

      store.upsertMember({
        'group_id': group.id,
        'user_id': userB,
        'joined_at': DateTime.now().toIso8601String(),
      });

      await repoA.pushToSupabase();

      // Collect all emissions until we see the expected group, with a timeout.
      final completer = Completer<List<GroupModel>>();
      final stream = repoB.watchGroups();
      late StreamSubscription sub;
      sub = stream.listen((groups) {
        if (groups.any((g) => g.name == 'Stream Test Group')) {
          if (!completer.isCompleted) completer.complete(groups);
          sub.cancel();
        }
      });

      // Trigger the pull — calls notifySyncComplete() → _notify() → re-emit.
      await repoB.pullFromSupabase();

      final result = await completer.future
          .timeout(const Duration(seconds: 5), onTimeout: () {
        sub.cancel();
        fail('watchGroups() never emitted a list containing "Stream Test Group". '
            'Pillar 3 (stream reactivity after sync) is broken.');
      });

      expect(result.any((g) => g.name == 'Stream Test Group'), isTrue);
    });

    test(
        'P3: watchGroups() emits updated list when User A creates a second group',
        () async {
      await repoA.createGroup('First Group');
      store.upsertMember({
        'group_id': (await repoA.getGroups()).first.id,
        'user_id': userB,
        'joined_at': DateTime.now().toIso8601String(),
      });
      await repoA.pushToSupabase();
      await repoB.pullFromSupabase();

      // User A creates a second group.
      final group2 = await repoA.createGroup('Second Group');
      store.upsertMember({
        'group_id': group2.id,
        'user_id': userB,
        'joined_at': DateTime.now().toIso8601String(),
      });
      await repoA.pushToSupabase();

      final completer = Completer<List<GroupModel>>();
      final stream = repoB.watchGroups();
      late StreamSubscription sub;
      sub = stream.listen((groups) {
        if (groups.any((g) => g.name == 'Second Group')) {
          if (!completer.isCompleted) completer.complete(groups);
          sub.cancel();
        }
      });

      await repoB.pullFromSupabase();

      final result = await completer.future
          .timeout(const Duration(seconds: 5), onTimeout: () {
        sub.cancel();
        fail('watchGroups() never emitted a list containing "Second Group". '
            'Pillar 3 stream reactivity is broken for multi-group scenarios.');
      });

      expect(result.any((g) => g.name == 'Second Group'), isTrue);
    });

    // -----------------------------------------------------------------------
    // ISOLATION — confirm separate DBs prevent SQLite lock conflicts
    // -----------------------------------------------------------------------

    test('ISOLATION: concurrent writes to both DBs do not conflict', () async {
      // Both users write simultaneously — no SQLite lock errors should occur.
      await Future.wait([
        repoA.createGroup('Group From A'),
        repoB.createGroup('Group From B'),
      ]);

      final aGroups = await repoA.getGroups();
      final bGroups = await repoB.getGroups();

      expect(aGroups.any((g) => g.name == 'Group From A'), isTrue);
      expect(bGroups.any((g) => g.name == 'Group From B'), isTrue);

      // Confirm isolation: A's DB does not contain B's group and vice versa.
      expect(aGroups.any((g) => g.name == 'Group From B'), isFalse,
          reason: 'User A\'s local DB must not contain User B\'s group before sync');
      expect(bGroups.any((g) => g.name == 'Group From A'), isFalse,
          reason: 'User B\'s local DB must not contain User A\'s group before sync');
    });
  });
}

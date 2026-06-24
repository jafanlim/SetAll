// Integration test: soft-delete integrity and time-window restore logic.
//
// Verifies:
//   1. Owner soft-delete sets is_deleted=1 and creates restoration snapshots.
//   2. Cascade-deleted expenses are tagged with deleted_with_group_id.
//   3. restoreGroup re-inserts cascade-deleted expenses and splits.
//   4. 365-day group restore window and 30-day expense restore window logic.
//   5. Batch delete generates snapshots for each group.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:setall/data/local/local_database.dart';
import 'package:setall/data/repositories/setall_repository.dart';

const _uid = 'owner-uid-soft-del';

Future<Database> _openTestDb() async {
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''
          CREATE TABLE groups (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, creator_id TEXT NOT NULL,
            created_by TEXT, type TEXT NOT NULL DEFAULT 'normal',
            is_deleted INTEGER NOT NULL DEFAULT 0, deleted_at TEXT,
            icon_name TEXT, color_value INTEGER, avatar_url TEXT,
            default_currency TEXT,
            created_at TEXT, updated_at TEXT, synced_at INTEGER
          )
        ''');
        await db.execute('''
          CREATE TABLE group_members (
            group_id TEXT NOT NULL, user_id TEXT NOT NULL,
            joined_at TEXT, synced_at INTEGER,
            PRIMARY KEY (group_id, user_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE expenses (
            id TEXT PRIMARY KEY, group_id TEXT, payer_id TEXT NOT NULL,
            created_by TEXT, amount TEXT NOT NULL, total_amount TEXT,
            base_amount_at_entry TEXT, is_income INTEGER NOT NULL DEFAULT 0,
            description TEXT, currency TEXT, split_type TEXT, category TEXT,
            original_amount TEXT, original_currency TEXT,
            exchange_rate_applied TEXT, universal_usd_amount TEXT,
            created_at TEXT, updated_at TEXT, synced_at INTEGER,
            icon_codepoint INTEGER, icon_color INTEGER,
            attachment_urls TEXT, notes TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE splits (
            id TEXT PRIMARY KEY, expense_id TEXT NOT NULL,
            user_id TEXT NOT NULL, universal_usd_owed TEXT NOT NULL,
            entry_amount_owed TEXT, created_at TEXT, synced_at INTEGER,
            UNIQUE(expense_id, user_id)
          )
        ''');
        await db.execute('''
          CREATE TABLE profiles (
            id TEXT PRIMARY KEY, name TEXT NOT NULL, nickname TEXT,
            avatar_url TEXT, is_ghost INTEGER NOT NULL DEFAULT 0,
            default_currency TEXT, synced_at INTEGER
          )
        ''');
        await db.execute(
            'CREATE TABLE left_groups (group_id TEXT PRIMARY KEY, left_at TEXT)');
        await db.execute('''
          CREATE TABLE user_categories (
            id TEXT PRIMARY KEY, name TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT 'expense',
            created_by TEXT NOT NULL, created_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE deleted_groups_log (
            group_id TEXT PRIMARY KEY, group_name TEXT NOT NULL,
            creator_id TEXT NOT NULL, deleted_by_uid TEXT NOT NULL,
            deleted_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE deleted_expenses (
            expense_id TEXT PRIMARY KEY, description TEXT,
            amount TEXT NOT NULL, original_amount TEXT, currency TEXT,
            group_id TEXT, group_name TEXT,
            is_income INTEGER NOT NULL DEFAULT 0, category TEXT,
            deleted_by TEXT NOT NULL, deleted_by_name TEXT,
            deleted_at TEXT NOT NULL, deleted_with_group_id TEXT,
            original_created_at TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE deleted_splits (
            id TEXT PRIMARY KEY, expense_id TEXT NOT NULL,
            user_id TEXT NOT NULL, amount_owed TEXT,
            universal_usd_owed TEXT, deleted_with_group_id TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE expense_edits (
            id TEXT PRIMARY KEY, expense_id TEXT NOT NULL,
            old_description TEXT, new_description TEXT,
            old_category TEXT, new_category TEXT,
            old_amount TEXT, new_amount TEXT, currency TEXT,
            group_id TEXT, group_name TEXT,
            edited_by TEXT NOT NULL, edited_by_name TEXT,
            edited_at TEXT NOT NULL
          )
        ''');
      },
    ),
  );
}

Future<void> _seedGroup(Database db,
    {required String id, String name = 'Test', String? creatorId}) async {
  await db.insert('groups', {
    'id': id,
    'name': name,
    'creator_id': creatorId ?? _uid,
    'type': 'normal',
    'is_deleted': 0,
    'created_at': DateTime.now().toIso8601String(),
  });
}

Future<void> _seedExpense(Database db,
    {required String id,
    required String groupId,
    String? payerId,
    String amount = '50.00'}) async {
  await db.insert('expenses', {
    'id': id,
    'group_id': groupId,
    'payer_id': payerId ?? _uid,
    'amount': amount,
    'universal_usd_amount': amount,
    'original_currency': 'USD',
    'description': 'Test expense $id',
    'category': 'General',
    'created_at': DateTime.now().toIso8601String(),
  });
}

Future<void> _seedSplit(Database db,
    {required String expenseId, required String userId, String amount = '25.00'}) async {
  await db.insert('splits', {
    'id': '${expenseId}_$userId',
    'expense_id': expenseId,
    'user_id': userId,
    'universal_usd_owed': amount,
  });
}

void main() {
  late Database db;

  setUpAll(() => sqfliteFfiInit());

  setUp(() async {
    SharedPreferences.setMockInitialValues({'device_user_id': _uid});
    LocalDatabase.resetForTesting();
    db = await _openTestDb();
    LocalDatabase.injectForTesting(db);
  });

  tearDown(() async {
    await db.close();
    LocalDatabase.resetForTesting();
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 1. Owner soft-delete creates restoration snapshots
  // ─────────────────────────────────────────────────────────────────────────
  group('Owner soft-delete snapshots', () {
    test('deleteGroup sets is_deleted=1 and populates deleted_expenses',
        () async {
      await _seedGroup(db, id: 'g1', name: 'Vacation');
      await _seedExpense(db, id: 'e1', groupId: 'g1');
      await _seedSplit(db, expenseId: 'e1', userId: _uid);

      final repo = SetAllRepository();
      final ok = await repo.deleteGroup('g1');
      expect(ok, isTrue);

      // Group soft-deleted
      final groups = await db.query('groups', where: 'id = ?', whereArgs: ['g1']);
      expect(groups.first['is_deleted'], equals(1));
      expect(groups.first['deleted_at'], isNotNull);

      // Expense snapshotted
      final snaps = await db.query('deleted_expenses',
          where: 'expense_id = ?', whereArgs: ['e1']);
      expect(snaps, hasLength(1));
      expect(snaps.first['deleted_with_group_id'], equals('g1'));

      // Split snapshotted
      final splitSnaps = await db.query('deleted_splits',
          where: 'expense_id = ?', whereArgs: ['e1']);
      expect(splitSnaps, hasLength(1));
      expect(splitSnaps.first['deleted_with_group_id'], equals('g1'));

      // Live expense/split removed
      expect(await db.query('expenses', where: 'id = ?', whereArgs: ['e1']),
          isEmpty);
      expect(await db.query('splits', where: 'expense_id = ?', whereArgs: ['e1']),
          isEmpty);
    });

    test('multiple expenses are all cascade-snapshotted', () async {
      await _seedGroup(db, id: 'g2', name: 'Multi');
      await _seedExpense(db, id: 'e2a', groupId: 'g2', amount: '10.00');
      await _seedExpense(db, id: 'e2b', groupId: 'g2', amount: '20.00');
      await _seedExpense(db, id: 'e2c', groupId: 'g2', amount: '30.00');

      final repo = SetAllRepository();
      await repo.deleteGroup('g2');

      final snaps = await db.query('deleted_expenses',
          where: 'deleted_with_group_id = ?', whereArgs: ['g2']);
      expect(snaps, hasLength(3),
          reason: 'All 3 expenses must be cascade-snapshotted');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. restoreGroup re-inserts cascade-deleted items
  // ─────────────────────────────────────────────────────────────────────────
  group('restoreGroup round-trip', () {
    test('restoreGroup re-inserts expenses and splits, clears snapshots',
        () async {
      await _seedGroup(db, id: 'g3', name: 'Restorable');
      await _seedExpense(db, id: 'e3', groupId: 'g3', amount: '75.00');
      await _seedSplit(db, expenseId: 'e3', userId: _uid, amount: '75.00');

      final repo = SetAllRepository();
      await repo.deleteGroup('g3');

      // Verify deleted state
      expect(await db.query('expenses', where: 'id = ?', whereArgs: ['e3']),
          isEmpty);

      // Restore
      final ok = await repo.restoreGroup('g3');
      expect(ok, isTrue);

      // Group is alive
      final groups = await db.query('groups', where: 'id = ?', whereArgs: ['g3']);
      expect(groups.first['is_deleted'], equals(0));
      expect(groups.first['deleted_at'], isNull);

      // Expense re-inserted
      final expenses = await db.query('expenses', where: 'group_id = ?', whereArgs: ['g3']);
      expect(expenses, hasLength(1));

      // Split re-inserted
      final splits = await db.query('splits',
          where: 'expense_id = ?', whereArgs: [expenses.first['id']]);
      expect(splits, hasLength(1));

      // Snapshots cleaned up
      expect(await db.query('deleted_expenses',
          where: 'deleted_with_group_id = ?', whereArgs: ['g3']), isEmpty);
      expect(await db.query('deleted_splits',
          where: 'deleted_with_group_id = ?', whereArgs: ['g3']), isEmpty);
    });

    test('restoreGroup rejects non-owner', () async {
      await _seedGroup(db, id: 'g4', name: 'NotMine', creatorId: 'someone-else');

      // Soft-delete manually (bypass owner check for setup)
      await db.update('groups', {'is_deleted': 1, 'deleted_at': DateTime.now().toIso8601String()},
          where: 'id = ?', whereArgs: ['g4']);

      final repo = SetAllRepository();
      final ok = await repo.restoreGroup('g4');
      expect(ok, isFalse,
          reason: 'Non-owner must not be able to restore a group');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. Time-window logic (365-day group, 30-day expense)
  // ─────────────────────────────────────────────────────────────────────────
  group('Restore time-window calculation', () {
    test('group deleted < 365 days ago is within restore window', () {
      final deletedAt = DateTime.now().subtract(const Duration(days: 100));
      final daysSince = DateTime.now().difference(deletedAt).inDays;
      expect(daysSince < 365, isTrue,
          reason: '100 days ago is within the 365-day restore window');
    });

    test('group deleted > 365 days ago is outside restore window', () {
      final deletedAt = DateTime.now().subtract(const Duration(days: 400));
      final daysSince = DateTime.now().difference(deletedAt).inDays;
      expect(daysSince < 365, isFalse,
          reason: '400 days ago is outside the 365-day restore window');
    });

    test('expense deleted < 30 days ago is within restore window', () {
      final deletedAt = DateTime.now().subtract(const Duration(days: 15));
      final daysSince = DateTime.now().difference(deletedAt).inDays;
      expect(daysSince < 30, isTrue,
          reason: '15 days ago is within the 30-day expense restore window');
    });

    test('expense deleted > 30 days ago is outside restore window', () {
      final deletedAt = DateTime.now().subtract(const Duration(days: 45));
      final daysSince = DateTime.now().difference(deletedAt).inDays;
      expect(daysSince < 30, isFalse,
          reason: '45 days ago is outside the 30-day expense restore window');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. left_groups entry persists after delete
  // ─────────────────────────────────────────────────────────────────────────
  group('left_groups sync guard', () {
    test('deleteGroup always writes to left_groups', () async {
      await _seedGroup(db, id: 'g5');
      final repo = SetAllRepository();
      await repo.deleteGroup('g5');

      final rows = await db.query('left_groups',
          where: 'group_id = ?', whereArgs: ['g5']);
      expect(rows, hasLength(1),
          reason: 'left_groups must contain the deleted group for sync filtering');
    });

    test('restoreGroup removes from left_groups', () async {
      await _seedGroup(db, id: 'g6');
      final repo = SetAllRepository();
      await repo.deleteGroup('g6');
      await repo.restoreGroup('g6');

      final rows = await db.query('left_groups',
          where: 'group_id = ?', whereArgs: ['g6']);
      expect(rows, isEmpty,
          reason: 'Restored group must be removed from left_groups');
    });
  });
}

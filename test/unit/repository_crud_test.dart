// ignore_for_file: lines_longer_than_80_chars
//
// Repository CRUD & Delete/Restore test suite
// ─────────────────────────────────────────────
// Uses sqflite_common_ffi (in-memory SQLite) + LocalDatabase.injectForTesting
// so every test runs without a device, emulator, or network connection.
//
// Run with:
//   flutter test test/unit/repository_crud_test.dart

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setall/core/utils/split_engine.dart';
import 'package:setall/data/local/local_database.dart';
import 'package:setall/data/models/split_model.dart';
import 'package:setall/data/repositories/setall_repository.dart';
import 'package:setall/domain/services/settlement_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Constants
// ─────────────────────────────────────────────────────────────────────────────

const _uid      = 'test-owner-uid';
const _otherUid = 'test-other-uid';

// ─────────────────────────────────────────────────────────────────────────────
// Test-DB bootstrap
// ─────────────────────────────────────────────────────────────────────────────

/// Opens a fresh in-memory SQLite database with the full v24 schema.
/// Each test gets its own instance — tearDown closes it.
Future<Database> _openFreshDb() => databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: 1, onCreate: _createSchema),
    );

Future<void> _createSchema(Database db, int _) async {
  await db.execute('''
    CREATE TABLE groups (
      id          TEXT PRIMARY KEY,
      name        TEXT NOT NULL,
      creator_id  TEXT NOT NULL,
      created_by  TEXT,
      type        TEXT NOT NULL DEFAULT 'normal',
      is_deleted  INTEGER NOT NULL DEFAULT 0,
      deleted_at  TEXT,
      icon_name   TEXT,
      color_value INTEGER,
      avatar_url  TEXT,
      created_at  TEXT,
      updated_at  TEXT,
      synced_at   INTEGER
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
      group_id              TEXT,
      payer_id              TEXT NOT NULL,
      created_by            TEXT,
      amount                TEXT NOT NULL,
      total_amount          TEXT,
      base_amount_at_entry  TEXT,
      is_income             INTEGER NOT NULL DEFAULT 0,
      description           TEXT,
      currency              TEXT,
      split_type            TEXT,
      category              TEXT,
      original_amount       TEXT,
      original_currency     TEXT,
      exchange_rate_applied TEXT,
      universal_usd_amount  TEXT,
      created_at            TEXT,
      updated_at            TEXT,
      synced_at             INTEGER,
      icon_codepoint        INTEGER,
      icon_color            INTEGER,
      attachment_urls       TEXT,
      notes                 TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE splits (
      id                 TEXT PRIMARY KEY,
      expense_id         TEXT NOT NULL,
      user_id            TEXT NOT NULL,
      universal_usd_owed TEXT NOT NULL,
      entry_amount_owed  TEXT,
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
    CREATE TABLE left_groups (
      group_id TEXT PRIMARY KEY,
      left_at  TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE deleted_expenses (
      expense_id            TEXT PRIMARY KEY,
      description           TEXT,
      amount                TEXT NOT NULL,
      original_amount       TEXT,
      currency              TEXT,
      group_id              TEXT,
      group_name            TEXT,
      is_income             INTEGER NOT NULL DEFAULT 0,
      category              TEXT,
      deleted_by            TEXT NOT NULL,
      deleted_by_name       TEXT,
      deleted_at            TEXT NOT NULL,
      deleted_with_group_id TEXT,
      original_created_at   TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE deleted_splits (
      id                    TEXT PRIMARY KEY,
      expense_id            TEXT NOT NULL,
      user_id               TEXT NOT NULL,
      amount_owed           TEXT,
      universal_usd_owed    TEXT,
      deleted_with_group_id TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE deleted_groups_log (
      group_id       TEXT PRIMARY KEY,
      group_name     TEXT NOT NULL,
      creator_id     TEXT NOT NULL,
      deleted_by_uid TEXT NOT NULL,
      deleted_at     TEXT NOT NULL
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
  await db.execute('''
    CREATE TABLE user_categories (
      id         TEXT PRIMARY KEY,
      name       TEXT NOT NULL,
      type       TEXT NOT NULL DEFAULT 'expense',
      created_by TEXT NOT NULL,
      created_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE expense_edits (
      id              TEXT PRIMARY KEY,
      expense_id      TEXT NOT NULL,
      old_description TEXT,
      new_description TEXT,
      old_category    TEXT,
      new_category    TEXT,
      old_amount      TEXT,
      new_amount      TEXT,
      currency        TEXT,
      group_id        TEXT,
      group_name      TEXT,
      edited_by       TEXT NOT NULL,
      edited_by_name  TEXT,
      edited_at       TEXT NOT NULL
    )
  ''');
}

// ─────────────────────────────────────────────────────────────────────────────
// Seed helpers
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _seedGroup(
  Database db, {
  required String id,
  required String name,
  required String creatorId,
  int isDeleted = 0,
}) async {
  await db.insert('groups', {
    'id': id, 'name': name, 'creator_id': creatorId,
    'type': 'normal', 'is_deleted': isDeleted,
    'created_at': DateTime.now().toIso8601String(),
  });
}

Future<void> _seedExpense(
  Database db, {
  required String id,
  required String groupId,
  required String payerId,
  required String amount,
  String currency = 'USD',
  String description = 'Test expense',
}) async {
  await db.insert('expenses', {
    'id': id, 'group_id': groupId, 'payer_id': payerId,
    'amount': amount, 'currency': currency,
    'original_currency': currency, 'description': description,
    'created_at': DateTime.now().toIso8601String(),
  });
}

Future<void> _seedSplit(
  Database db, {
  required String id,
  required String expenseId,
  required String userId,
  required String usdOwed,
}) async {
  await db.insert('splits', {
    'id': id, 'expense_id': expenseId,
    'user_id': userId, 'universal_usd_owed': usdOwed,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Assertion helpers
// ─────────────────────────────────────────────────────────────────────────────

Future<bool> _expenseExists(Database db, String id) async =>
    (await db.query('expenses', where: 'id = ?', whereArgs: [id])).isNotEmpty;

Future<bool> _deletedExpenseExists(Database db, String id) async =>
    (await db.query('deleted_expenses',
            where: 'expense_id = ?', whereArgs: [id]))
        .isNotEmpty;

Future<bool> _splitExists(Database db, String expenseId) async =>
    (await db.query('splits',
            where: 'expense_id = ?', whereArgs: [expenseId]))
        .isNotEmpty;

Future<bool> _groupSoftDeleted(Database db, String groupId) async =>
    (await db.query('groups',
            where: 'id = ? AND is_deleted = 1', whereArgs: [groupId]))
        .isNotEmpty;

Future<bool> _inLeftGroups(Database db, String groupId) async =>
    (await db.query('left_groups',
            where: 'group_id = ?', whereArgs: [groupId]))
        .isNotEmpty;

// ─────────────────────────────────────────────────────────────────────────────
// Settlement engine helper (mirrors engine_regression_guard_test)
// ─────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> _expense({
  required String id,
  required String groupId,
  required String payerId,
  required String amount,
  required String currency,
  String? usdAnchor,
}) => {
      'id': id, 'group_id': groupId, 'payer_id': payerId,
      'amount': amount, 'currency': currency,
      'base_amount_at_entry': usdAnchor,
    };

SplitModel _split({
  required String expenseId,
  required String userId,
  required String usdOwed,
}) =>
    SplitModel(
      id: '${expenseId}_$userId',
      expenseId: expenseId,
      userId: userId,
      universalUsdOwed: usdOwed,
    );

// ─────────────────────────────────────────────────────────────────────────────
// SUITE
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  late Database db;
  late SetAllRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'device_user_id': _uid});
    db = await _openFreshDb();
    LocalDatabase.injectForTesting(db);
    repo = SetAllRepository(); // offline — no Supabase client
  });

  tearDown(() async {
    LocalDatabase.resetForTesting();
    await db.close();
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 1. deleteExpense
  // ───────────────────────────────────────────────────────────────────────────
  group('deleteExpense', () {
    const gid = 'g-del-exp';
    const eid = 'e-del-1';

    setUp(() async {
      await _seedGroup(db, id: gid, name: 'Dinner', creatorId: _uid);
      await _seedExpense(db,
          id: eid, groupId: gid, payerId: _uid,
          amount: '60.00', description: 'Pizza night');
      await _seedSplit(db, id: 'spl-1', expenseId: eid,
          userId: 'user-b', usdOwed: '30.00');
    });

    test('removes expense from live expenses table', () async {
      await repo.deleteExpense(eid);
      expect(await _expenseExists(db, eid), isFalse);
    });

    test('creates a snapshot in deleted_expenses', () async {
      await repo.deleteExpense(eid);
      expect(await _deletedExpenseExists(db, eid), isTrue);
    });

    test('snapshot records correct deleted_by uid', () async {
      await repo.deleteExpense(eid);
      final row = (await db.query('deleted_expenses',
              where: 'expense_id = ?', whereArgs: [eid]))
          .first;
      expect(row['deleted_by'], equals(_uid));
    });

    test('snapshot preserves original amount and currency', () async {
      await repo.deleteExpense(eid);
      final row = (await db.query('deleted_expenses',
              where: 'expense_id = ?', whereArgs: [eid]))
          .first;
      // amount column stores the USD anchor (or raw amount when no anchor set)
      expect(row['amount'], isNotNull);
      expect(row['currency'], equals('USD'));
    });

    test('also removes associated splits', () async {
      await repo.deleteExpense(eid);
      expect(await _splitExists(db, eid), isFalse,
          reason: 'Splits must be removed together with the expense');
    });

    test('returns true on success', () async {
      expect(await repo.deleteExpense(eid), isTrue);
    });

    test('returns true even for a nonexistent id (silent no-op)', () async {
      // deleteExpense does not check row-count; it always returns true
      // if ensureUser() succeeds. This test documents current behaviour.
      expect(await repo.deleteExpense('no-such-expense'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2. restoreExpense
  // ───────────────────────────────────────────────────────────────────────────
  group('restoreExpense', () {
    const gid = 'g-rst-exp';
    const eid = 'e-rst-1';

    setUp(() async {
      await _seedGroup(db, id: gid, name: 'Holiday', creatorId: _uid);
      await _seedExpense(db,
          id: eid, groupId: gid, payerId: _uid,
          amount: '80.00', description: 'Hotel stay');
      await repo.deleteExpense(eid); // produces snapshot
    });

    test('re-inserts expense into live expenses table', () async {
      await repo.restoreExpense(eid);
      expect(await _expenseExists(db, eid), isTrue);
    });

    test('removes the deleted_expenses snapshot after restore', () async {
      await repo.restoreExpense(eid);
      expect(await _deletedExpenseExists(db, eid), isFalse);
    });

    test('returns true on success', () async {
      expect(await repo.restoreExpense(eid), isTrue);
    });

    test('returns false when no snapshot exists', () async {
      expect(await repo.restoreExpense('ghost-expense'), isFalse);
    });

    test('returns false when caller is not the original deleter', () async {
      // Simulate a different user trying to restore
      SharedPreferences.setMockInitialValues({'device_user_id': _otherUid});
      final otherRepo = SetAllRepository();
      expect(await otherRepo.restoreExpense(eid), isFalse,
          reason: 'Only the user who deleted the expense may restore it');
    });

    test('second restore attempt returns false (snapshot already removed)',
        () async {
      await repo.restoreExpense(eid);
      expect(await repo.restoreExpense(eid), isFalse,
          reason: 'Snapshot is consumed on first restore');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3. deleteExpenses — batch (REGRESSION: no snapshot created)
  // ───────────────────────────────────────────────────────────────────────────
  group('deleteExpenses (batch)', () {
    const gid = 'g-batch';
    final eids = ['e-b1', 'e-b2', 'e-b3'];

    setUp(() async {
      await _seedGroup(db, id: gid, name: 'Batch Group', creatorId: _uid);
      for (final id in eids) {
        await _seedExpense(db,
            id: id, groupId: gid, payerId: _uid, amount: '10.00');
        await _seedSplit(db,
            id: 'spl-$id', expenseId: id, userId: 'user-b', usdOwed: '5.00');
      }
    });

    test('removes all listed expenses from live table', () async {
      await repo.deleteExpenses(eids);
      for (final id in eids) {
        expect(await _expenseExists(db, id), isFalse,
            reason: 'Expense $id must be removed by deleteExpenses');
      }
    });

    test('removes all associated splits', () async {
      await repo.deleteExpenses(eids);
      for (final id in eids) {
        expect(await _splitExists(db, id), isFalse);
      }
    });

    test('KNOWN LIMITATION: does NOT create deleted_expenses snapshots', () async {
      // deleteExpenses skips the per-expense snapshot loop that deleteExpense
      // uses. This means batch-deleted expenses cannot be restored via
      // restoreExpense. This test documents the gap so it is caught if
      // the behaviour changes (either fixed or intentionally kept).
      await repo.deleteExpenses(eids);
      for (final id in eids) {
        expect(await _deletedExpenseExists(db, id), isFalse,
            reason: 'KNOWN GAP: deleteExpenses does not snapshot to '
                'deleted_expenses — individual deleteExpense must be used '
                'when restore capability is required');
      }
    });

    test('returns true on success', () async {
      expect(await repo.deleteExpenses(eids), isTrue);
    });

    test('empty list returns true immediately', () async {
      expect(await repo.deleteExpenses([]), isTrue);
    });

    test('partial list — only listed ids are removed', () async {
      await repo.deleteExpenses([eids[0], eids[1]]);
      expect(await _expenseExists(db, eids[0]), isFalse);
      expect(await _expenseExists(db, eids[1]), isFalse);
      expect(await _expenseExists(db, eids[2]), isTrue,
          reason: 'Unlisted expense must survive the batch delete');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4. deleteGroup — owner (soft-delete + cascade)
  // ───────────────────────────────────────────────────────────────────────────
  group('deleteGroup — owner (soft-delete)', () {
    const gid = 'g-owner-del';
    const eid1 = 'e-od-1';
    const eid2 = 'e-od-2';

    setUp(() async {
      await _seedGroup(db, id: gid, name: 'Trip', creatorId: _uid);
      await _seedExpense(db,
          id: eid1, groupId: gid, payerId: _uid, amount: '100.00');
      await _seedExpense(db,
          id: eid2, groupId: gid, payerId: _uid, amount: '50.00');
      await _seedSplit(db,
          id: 'spl-od-1', expenseId: eid1, userId: 'user-b', usdOwed: '50.00');
    });

    test('marks group as soft-deleted (is_deleted = 1)', () async {
      await repo.deleteGroup(gid);
      expect(await _groupSoftDeleted(db, gid), isTrue);
    });

    test('adds the group to left_groups so sync filters it out', () async {
      await repo.deleteGroup(gid);
      expect(await _inLeftGroups(db, gid), isTrue);
    });

    test('cascade-removes both expenses from live table', () async {
      await repo.deleteGroup(gid);
      expect(await _expenseExists(db, eid1), isFalse);
      expect(await _expenseExists(db, eid2), isFalse);
    });

    test('cascade-snapshots both expenses into deleted_expenses', () async {
      await repo.deleteGroup(gid);
      expect(await _deletedExpenseExists(db, eid1), isTrue);
      expect(await _deletedExpenseExists(db, eid2), isTrue);
    });

    test('cascade-deleted expenses are tagged with deleted_with_group_id',
        () async {
      await repo.deleteGroup(gid);
      final rows = await db.query('deleted_expenses',
          where: 'deleted_with_group_id = ?', whereArgs: [gid]);
      expect(rows.length, equals(2),
          reason: 'Both expenses must carry the cascade tag');
    });

    test('cascade-snapshots splits into deleted_splits', () async {
      await repo.deleteGroup(gid);
      final rows = await db.query('deleted_splits',
          where: 'deleted_with_group_id = ?', whereArgs: [gid]);
      expect(rows.isNotEmpty, isTrue,
          reason: 'Splits must be preserved in deleted_splits for later restore');
    });

    test('cascade-removes splits from live splits table', () async {
      await repo.deleteGroup(gid);
      expect(await _splitExists(db, eid1), isFalse);
    });

    test('returns true on success', () async {
      expect(await repo.deleteGroup(gid), isTrue);
    });

    test('returns false for a nonexistent group', () async {
      expect(await repo.deleteGroup('no-group'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 5. deleteGroup — non-owner (soft-delete + leave)
  // ───────────────────────────────────────────────────────────────────────────
  group('deleteGroup — non-owner (soft-delete / leave)', () {
    const gid = 'g-nonowner';
    const eid = 'e-no-1';
    const realOwner = 'real-owner-uid';

    setUp(() async {
      await _seedGroup(db, id: gid, name: 'Shared', creatorId: realOwner);
      await db.insert('group_members', {
        'group_id': gid, 'user_id': _otherUid,
      });
      await _seedExpense(db,
          id: eid, groupId: gid, payerId: realOwner, amount: '200.00');
      // Switch to the non-owner user
      SharedPreferences.setMockInitialValues({'device_user_id': _otherUid});
    });

    test('soft-deletes the group row for sync safety', () async {
      final nonOwnerRepo = SetAllRepository();
      await nonOwnerRepo.deleteGroup(gid);
      // Non-owner leave soft-deletes first so concurrent sync ticks see
      // is_deleted=1 and do not strip the left_groups entry.
      final rows = await db.query('groups',
          where: 'id = ? AND is_deleted = 1', whereArgs: [gid]);
      expect(rows, isNotEmpty,
          reason: 'Non-owner leave must soft-delete the group row for sync safety');
    });

    test('removes expenses from live table', () async {
      final nonOwnerRepo = SetAllRepository();
      await nonOwnerRepo.deleteGroup(gid);
      expect(await _expenseExists(db, eid), isFalse);
    });

    test('adds entry to left_groups so sync never re-pulls the group',
        () async {
      final nonOwnerRepo = SetAllRepository();
      await nonOwnerRepo.deleteGroup(gid);
      expect(await _inLeftGroups(db, gid), isTrue);
    });

    test('leaves a soft-deleted record as sync guard', () async {
      final nonOwnerRepo = SetAllRepository();
      await nonOwnerRepo.deleteGroup(gid);
      // The soft-deleted row acts as a guard so concurrent sync does not
      // re-pull the group before left_groups is checked.
      final rows = await db.query('groups',
          where: 'id = ? AND is_deleted = 1', whereArgs: [gid]);
      expect(rows, hasLength(1),
          reason: 'Non-owner leave must keep a soft-deleted row as sync guard');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 6. restoreGroup
  // ───────────────────────────────────────────────────────────────────────────
  group('restoreGroup', () {
    const gid = 'g-restore';
    const eid = 'e-r-1';

    setUp(() async {
      await _seedGroup(db, id: gid, name: 'Restoration', creatorId: _uid);
      await _seedExpense(db,
          id: eid, groupId: gid, payerId: _uid, amount: '45.00');
      await _seedSplit(db,
          id: 'spl-r-1', expenseId: eid, userId: 'user-c', usdOwed: '22.50');
      await repo.deleteGroup(gid); // creates soft-delete + cascade
    });

    test('clears is_deleted flag — group is visible again', () async {
      await repo.restoreGroup(gid);
      final row = (await db.query('groups',
              where: 'id = ?', whereArgs: [gid]))
          .first;
      expect(row['is_deleted'], equals(0));
    });

    test('restores cascade-deleted expenses back to live expenses table',
        () async {
      await repo.restoreGroup(gid);
      expect(await _expenseExists(db, eid), isTrue,
          reason: 'Cascade-deleted expenses must come back on group restore');
    });

    test('removes restored expenses from deleted_expenses', () async {
      await repo.restoreGroup(gid);
      expect(await _deletedExpenseExists(db, eid), isFalse);
    });

    test('restores cascade-deleted splits back to live splits table', () async {
      await repo.restoreGroup(gid);
      expect(await _splitExists(db, eid), isTrue,
          reason: 'Splits must be restored alongside expenses for correct '
              'balance calculations after group restore');
    });

    test('removes the group from left_groups', () async {
      await repo.restoreGroup(gid);
      expect(await _inLeftGroups(db, gid), isFalse,
          reason: 'left_groups entry must be cleaned up so sync works again');
    });

    test('returns true on success', () async {
      expect(await repo.restoreGroup(gid), isTrue);
    });

    test('returns false when called by non-owner', () async {
      SharedPreferences.setMockInitialValues({'device_user_id': _otherUid});
      final otherRepo = SetAllRepository();
      expect(await otherRepo.restoreGroup(gid), isFalse,
          reason: 'Non-owner must not be allowed to restore the group');
    });

    test('returns false for a nonexistent group id', () async {
      expect(await repo.restoreGroup('ghost-group'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 7. deleteGroups — batch
  // ───────────────────────────────────────────────────────────────────────────
  group('deleteGroups (batch)', () {
    test('soft-deletes all owner groups and returns true', () async {
      for (final id in ['bg-1', 'bg-2', 'bg-3']) {
        await _seedGroup(db, id: id, name: 'Batch $id', creatorId: _uid);
      }
      final ok = await repo.deleteGroups(['bg-1', 'bg-2', 'bg-3']);
      expect(ok, isTrue);
      for (final id in ['bg-1', 'bg-2', 'bg-3']) {
        expect(await _groupSoftDeleted(db, id), isTrue,
            reason: 'Group $id must be soft-deleted');
      }
    });

    test('empty list returns true (no-op)', () async {
      expect(await repo.deleteGroups([]), isTrue);
    });

    test('partial failure: owned groups are deleted, missing ids are tolerated',
        () async {
      await _seedGroup(db, id: 'bg-real', name: 'Real', creatorId: _uid);
      // 'bg-ghost' does not exist — deleteGroup returns false for it
      final ok = await repo.deleteGroups(['bg-real', 'bg-ghost']);
      // bg-real must be gone; overall result is false because bg-ghost failed
      expect(await _groupSoftDeleted(db, 'bg-real'), isTrue);
      expect(ok, isFalse,
          reason: 'deleteGroups returns false when any individual delete fails');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 8. SplitEngine — correctness
  // ───────────────────────────────────────────────────────────────────────────
  group('SplitEngine', () {
    test('2-way even split of \$20.00: each participant owes exactly \$10.00',
        () {
      final splits = SplitEngine.splitEven(
        total: Decimal.parse('20.00'),
        participantIds: ['alice', 'bob'],
        payerId: 'alice',
      );
      expect(splits.length, equals(2));
      for (final s in splits) {
        expect(s.amountOwed, equals(Decimal.parse('10.00')));
      }
    });

    test('5-way even split of \$100.00 gives each participant \$20.00', () {
      final splits = SplitEngine.splitEven(
        total: Decimal.parse('100.00'),
        participantIds: ['a', 'b', 'c', 'd', 'e'],
        payerId: 'a',
      );
      final sum = splits.fold(Decimal.zero, (s, e) => s + e.amountOwed);
      expect(sum, equals(Decimal.parse('100.00')));
    });

    test('single-participant split: full amount goes to solo payer', () {
      final splits = SplitEngine.splitEven(
        total: Decimal.parse('50.00'),
        participantIds: ['solo'],
        payerId: 'solo',
      );
      expect(splits.length, equals(1));
      expect(splits.first.amountOwed, equals(Decimal.parse('50.00')));
    });

    // Property-based: for any amount and any participant count, the sum of
    // all shares must always equal the original total — no penny lost or gained.
    test('sum invariant: total is exactly preserved for indivisible amounts',
        () {
      const cases = [
        ('7.00', 3), ('1.00', 3), ('0.10', 3),
        ('100.01', 7), ('33.33', 4), ('99.99', 6),
      ];
      for (final (raw, n) in cases) {
        final total = Decimal.parse(raw);
        final ids = List.generate(n, (i) => 'u$i');
        final splits = SplitEngine.splitEven(
          total: total,
          participantIds: ids,
          payerId: ids.first,
        );
        final sum = splits.fold(Decimal.zero, (s, e) => s + e.amountOwed);
        expect(sum, equals(total),
            reason: '$raw ÷ $n must sum back to exactly $raw (got $sum)');
      }
    });

    test('payer absorbs the remainder penny (not any other participant)', () {
      // 10.00 ÷ 3 = 3.33 + 3.33 + 3.34; payer gets 3.34
      final splits = SplitEngine.splitEven(
        total: Decimal.parse('10.00'),
        participantIds: ['payer', 'b', 'c'],
        payerId: 'payer',
      );
      final payerShare =
          splits.firstWhere((s) => s.userId == 'payer').amountOwed;
      final otherShares =
          splits.where((s) => s.userId != 'payer').map((s) => s.amountOwed);
      expect(payerShare, equals(Decimal.parse('3.34')),
          reason: 'Payer must absorb the remainder penny');
      for (final s in otherShares) {
        expect(s, equals(Decimal.parse('3.33')));
      }
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 9. SettlementEngine — Greedy Flow scenarios
  // ───────────────────────────────────────────────────────────────────────────
  group('SettlementEngine', () {
    test('A→B \$30, B→C \$30 chain simplifies to single A→C \$30 payment',
        () {
      // Expense 1: B paid — A owes B \$30
      // Expense 2: C paid — B owes C \$30
      // Net balances: A = −30, B = 0, C = +30 → Greedy Flow: A pays C directly
      const gid = 'grp-chain';
      final expenses = [
        _expense(id: 'e1', groupId: gid, payerId: 'B',
            amount: '30.00', currency: 'USD', usdAnchor: '30.00'),
        _expense(id: 'e2', groupId: gid, payerId: 'C',
            amount: '30.00', currency: 'USD', usdAnchor: '30.00'),
      ];
      final splits = [
        _split(expenseId: 'e1', userId: 'A', usdOwed: '30.00'),
        _split(expenseId: 'e2', userId: 'B', usdOwed: '30.00'),
      ];

      final debts = SettlementEngine.simplify(
        groupId: gid, currency: 'USD',
        expenses: expenses, splits: splits,
      );

      expect(debts.length, equals(1),
          reason: 'Greedy Flow must collapse a 2-hop chain into 1 payment');
      expect(debts.first.fromUserId, equals('A'));
      expect(debts.first.toUserId, equals('C'));
      expect(debts.first.amount, equals(Decimal.parse('30.00')));
    });

    test('fully settled group (no expenses) produces zero transactions', () {
      final debts = SettlementEngine.simplify(
        groupId: 'grp-zero', currency: 'USD',
        expenses: [], splits: [],
      );
      expect(debts, isEmpty);
    });

    test('single payer with two debtors produces exactly two transactions',
        () {
      const gid = 'grp-2debts';
      final expenses = [
        _expense(id: 'e1', groupId: gid, payerId: 'P',
            amount: '60.00', currency: 'USD', usdAnchor: '60.00'),
      ];
      final splits = [
        _split(expenseId: 'e1', userId: 'A', usdOwed: '20.00'),
        _split(expenseId: 'e1', userId: 'B', usdOwed: '20.00'),
        _split(expenseId: 'e1', userId: 'P', usdOwed: '20.00'),
      ];

      final debts = SettlementEngine.simplify(
        groupId: gid, currency: 'USD',
        expenses: expenses, splits: splits,
      );

      expect(debts.length, equals(2));
      expect(debts.every((d) => d.toUserId == 'P'), isTrue,
          reason: 'Both debtors must pay the payer');
      final total = debts.fold(Decimal.zero, (s, d) => s + d.amount);
      expect(total, equals(Decimal.parse('40.00')),
          reason: 'Total paid must equal payer net credit: 60 − 20 = 40');
    });

    test('mutual netting: A owes B \$50, B owes A \$30 → net 1 payment of \$20',
        () {
      const gid = 'grp-mutual';
      final expenses = [
        _expense(id: 'eAB', groupId: gid, payerId: 'A',
            amount: '50.00', currency: 'USD', usdAnchor: '50.00'),
        _expense(id: 'eBA', groupId: gid, payerId: 'B',
            amount: '30.00', currency: 'USD', usdAnchor: '30.00'),
      ];
      final splits = [
        _split(expenseId: 'eAB', userId: 'B', usdOwed: '50.00'),
        _split(expenseId: 'eBA', userId: 'A', usdOwed: '30.00'),
      ];

      final debts = SettlementEngine.simplify(
        groupId: gid, currency: 'USD',
        expenses: expenses, splits: splits,
      );

      expect(debts.length, equals(1),
          reason: 'Mutual debts must net to a single payment');
      expect(debts.first.fromUserId, equals('B'));
      expect(debts.first.toUserId,   equals('A'));
      expect(debts.first.amount, equals(Decimal.parse('20.00')));
    });
  });
}

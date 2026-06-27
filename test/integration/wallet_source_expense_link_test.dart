// Integration test: source_expense_id link + dedupe in upsertWalletEntry.
//
// Verifies that upsertWalletEntry(entry, sourceExpenseId: ...) persists the
// source_expense_id and deduplicates — a second call with the same
// source_expense_id updates the existing mirror row instead of inserting
// a duplicate.
//
// Uses sqflite_common_ffi (in-memory DB) + stubbed CurrencyService.
// No network. No Supabase.

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:setall/core/services/currency_service.dart';
import 'package:setall/data/local/local_database.dart';
import 'package:setall/data/models/wallet_entry_model.dart';
import 'package:setall/data/repositories/setall_repository.dart';
import 'package:setall/domain/entities/expense.dart';

/// Stubbed rates: EUR→USD 1.08, GBP→USD 1.27, USD base.
class _StubRates extends CurrencyService {
  _StubRates() : super();

  @override
  Future<Decimal> getRate(String from, String to) async {
    if (from == to) return Decimal.one;
    final key = '$from→$to';
    const rates = {
      'EUR→USD': '1.08',
      'USD→EUR': '0.9259',
      'GBP→USD': '1.27',
      'USD→GBP': '0.7874',
      'GEL→USD': '0.3663',
      'USD→GEL': '2.7300',
    };
    return Decimal.parse(rates[key] ?? '1.0');
  }

  @override
  Future<Decimal> getRateToUsd(String from) => getRate(from, 'USD');
}

const _uid = 'test-source-expense-link-user';

void main() {
  late Database db;
  late SetAllRepository repo;

  setUpAll(() => sqfliteFfiInit());

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'device_user_id': _uid,
    });
    LocalDatabase.resetForTesting();

    db = await databaseFactoryFfi.openDatabase(
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
              base_currency_amount TEXT,
              created_at TEXT, updated_at TEXT, synced_at INTEGER,
              icon_codepoint INTEGER, icon_color INTEGER,
              attachment_urls TEXT, notes TEXT,
              source_expense_id TEXT
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
          await db.execute('''
            CREATE TABLE left_groups (group_id TEXT PRIMARY KEY, left_at TEXT)
          ''');
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
              old_amount TEXT, new_amount TEXT,
              currency TEXT, group_id TEXT, group_name TEXT,
              edited_by TEXT NOT NULL, edited_by_name TEXT,
              edited_at TEXT NOT NULL
            )
          ''');
        },
      ),
    );
    LocalDatabase.injectForTesting(db);

    // Seed the user's profile with USD as base currency.
    await db.insert('profiles', {
      'id': _uid,
      'name': 'Test User',
      'default_currency': 'USD',
      'is_ghost': 0,
    });

    repo = SetAllRepository(currencyService: _StubRates());
  });

  tearDown(() async {
    await db.close();
    LocalDatabase.resetForTesting();
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 1 — Round-trip: sourceExpenseId persists and reads back
  // ──────────────────────────────────────────────────────────────────────────
  group('source_expense_id round-trip', () {
    test('persists and reads back via WalletEntryModel', () async {
      const entryId  = 'mirror-entry-1';
      const sourceId = '00000000-0000-0000-0000-000000000001';

      final result = await repo.upsertWalletEntry(
        WalletEntryModel(
          id:          entryId,
          userId:      _uid,
          amount:      '50.00',
          currency:    'USD',
          description: 'Share · Dinner',
          category:    'Food & drink',
          isIncome:    false,
          createdAt:   DateTime(2026, 6, 26).toUtc().toIso8601String(),
        ),
        sourceExpenseId: sourceId,
      );

      // Returned model carries sourceExpenseId.
      expect(result.sourceExpenseId, sourceId);

      // DB row stores source_expense_id.
      final rows = await db.query('expenses',
          where: 'id = ?', whereArgs: [entryId]);
      expect(rows, hasLength(1));
      expect(rows.first['source_expense_id'], sourceId);

      // Read back via WalletEntryModel.fromJson.
      final model = WalletEntryModel.fromJson(rows.first);
      expect(model.sourceExpenseId, sourceId);
    });

    test('sourceExpenseId is null when not provided', () async {
      const entryId = 'mirror-entry-2';

      await repo.upsertWalletEntry(
        WalletEntryModel(
          id:          entryId,
          userId:      _uid,
          amount:      '25.00',
          currency:    'USD',
          description: 'Standalone entry',
          category:    'General',
          isIncome:    false,
          createdAt:   DateTime(2026, 6, 26).toUtc().toIso8601String(),
        ),
      );

      final rows = await db.query('expenses',
          where: 'id = ?', whereArgs: [entryId]);
      expect(rows, hasLength(1));
      expect(rows.first['source_expense_id'], isNull);

      final model = WalletEntryModel.fromJson(rows.first);
      expect(model.sourceExpenseId, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 2 — Dedupe: same sourceExpenseId → same row, updated
  // ──────────────────────────────────────────────────────────────────────────
  group('upsertWalletEntry dedupe by source_expense_id', () {
    test('second call with same sourceExpenseId updates, does not insert duplicate', () async {
      const sourceId = '00000000-0000-0000-0000-000000000002';

      // First call ──────────────────────────────────────────────────────────
      final first = await repo.upsertWalletEntry(
        WalletEntryModel(
          id:          'mirror-dup-1',
          userId:      _uid,
          amount:      '30.00',
          currency:    'USD',
          description: 'Share · Lunch',
          category:    'Food & drink',
          isIncome:    false,
          createdAt:   DateTime(2026, 6, 26).toUtc().toIso8601String(),
        ),
        sourceExpenseId: sourceId,
      );

      expect(first.sourceExpenseId, sourceId);

      // Verify exactly one row exists for this source_expense_id.
      var rows = await db.query('expenses',
          where: 'payer_id = ? AND source_expense_id = ? AND group_id IS NULL',
          whereArgs: [_uid, sourceId]);
      expect(rows, hasLength(1));
      expect(rows.first['amount'], '30.00');

      // Second call — same sourceExpenseId, different amount — should UPDATE ──
      final second = await repo.upsertWalletEntry(
        WalletEntryModel(
          id:          'mirror-dup-2', // different id
          userId:      _uid,
          amount:      '45.00',        // updated amount
          currency:    'USD',
          description: 'Share · Lunch (updated)',
          category:    'Food & drink',
          isIncome:    false,
          createdAt:   DateTime(2026, 6, 27).toUtc().toIso8601String(),
        ),
        sourceExpenseId: sourceId,
      );

      expect(second.sourceExpenseId, sourceId);

      // Still exactly one row — no duplicate.
      rows = await db.query('expenses',
          where: 'payer_id = ? AND source_expense_id = ? AND group_id IS NULL',
          whereArgs: [_uid, sourceId]);
      expect(rows, hasLength(1),
          reason: 'Must not insert a duplicate row for the same source_expense_id');

      // The row should have the updated values.
      expect(rows.first['amount'], '45.00',
          reason: 'Second call must update the existing mirror row');
      expect(rows.first['description'], 'Share · Lunch (updated)');
    });

    test('different sourceExpenseId creates separate rows', () async {
      const sourceA = '00000000-0000-0000-0000-000000000003';
      const sourceB = '00000000-0000-0000-0000-000000000004';

      await repo.upsertWalletEntry(
        WalletEntryModel(
          id:          'mirror-a',
          userId:      _uid,
          amount:      '10.00',
          currency:    'USD',
          description: 'Share · Coffee',
          category:    'Food & drink',
          isIncome:    false,
          createdAt:   DateTime(2026, 6, 26).toUtc().toIso8601String(),
        ),
        sourceExpenseId: sourceA,
      );

      await repo.upsertWalletEntry(
        WalletEntryModel(
          id:          'mirror-b',
          userId:      _uid,
          amount:      '20.00',
          currency:    'USD',
          description: 'Share · Train',
          category:    'Transport',
          isIncome:    false,
          createdAt:   DateTime(2026, 6, 26).toUtc().toIso8601String(),
        ),
        sourceExpenseId: sourceB,
      );

      // Both rows exist — no cross-dedupe across different sources.
      final rows = await db.query('expenses',
          where: 'payer_id = ? AND group_id IS NULL',
          whereArgs: [_uid]);
      expect(rows, hasLength(2));
      final sources = rows.map((r) => r['source_expense_id']).toSet();
      expect(sources, {sourceA, sourceB});
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Helpers for propagation tests
  // ──────────────────────────────────────────────────────────────────────────

  String isoNow() => DateTime.now().toUtc().toIso8601String();

  Future<void> seedGroupExpense({
    required String expenseId,
    required String groupId,
    required String amount,
    String currency = 'USD',
    String description = 'Test expense',
  }) async {
    await db.insert('groups', {
      'id':          groupId,
      'name':        'Test Group',
      'creator_id':  _uid,
      'created_by':  _uid,
      'type':        'normal',
      'is_deleted':  0,
      'created_at':  isoNow(),
      'updated_at':  isoNow(),
    });
    await db.insert('group_members', {
      'group_id':  groupId,
      'user_id':   _uid,
      'joined_at': isoNow(),
    });
    await db.insert('expenses', {
      'id':                  expenseId,
      'group_id':            groupId,
      'payer_id':            _uid,
      'created_by':          _uid,
      'amount':              amount,
      'description':         description,
      'currency':            currency,
      'split_type':          'even',
      'category':            'Food & drink',
      'is_income':           0,
      'created_at':          isoNow(),
      'universal_usd_amount': amount,
    });
    await db.insert('splits', {
      'id':                'split-$expenseId',
      'expense_id':        expenseId,
      'user_id':           _uid,
      'universal_usd_owed': amount,
      'entry_amount_owed':  amount,
      'created_at':         isoNow(),
    });
  }

  Future<void> createMirror({
    required String mirrorId,
    required String sourceExpenseId,
    required String amount,
    String currency = 'USD',
  }) async {
    await repo.upsertWalletEntry(
      WalletEntryModel(
        id:          mirrorId,
        userId:      _uid,
        amount:      amount,
        currency:    currency,
        description: 'Share · Test expense',
        category:    'Food & drink',
        isIncome:    false,
        createdAt:   isoNow(),
      ),
      sourceExpenseId: sourceExpenseId,
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 3 — Delete propagation: mirror removed when source expense deleted
  // ──────────────────────────────────────────────────────────────────────────
  group('delete propagation', () {
    test('deleteExpense removes linked mirror', () async {
      const expenseId = 'exp-del-1';
      const mirrorId  = 'mirror-del-1';

      await seedGroupExpense(expenseId: expenseId, groupId: 'grp-del-1', amount: '100.00');
      await createMirror(mirrorId: mirrorId, sourceExpenseId: expenseId, amount: '100.00');

      // Verify mirror exists before delete.
      var mirrors = await db.query('expenses',
          where: 'payer_id = ? AND source_expense_id = ? AND group_id IS NULL',
          whereArgs: [_uid, expenseId]);
      expect(mirrors, hasLength(1));

      final result = await repo.deleteExpense(expenseId);
      expect(result, isTrue);

      // Mirror must be gone.
      mirrors = await db.query('expenses',
          where: 'payer_id = ? AND source_expense_id = ? AND group_id IS NULL',
          whereArgs: [_uid, expenseId]);
      expect(mirrors, isEmpty);
    });

    test('deleteExpense is no-op when no mirror exists', () async {
      const expenseId = 'exp-del-2';

      await seedGroupExpense(expenseId: expenseId, groupId: 'grp-del-2', amount: '50.00');
      // No mirror created — delete should still succeed.

      final result = await repo.deleteExpense(expenseId);
      expect(result, isTrue);
    });

    test('deleteExpenses batch removes all linked mirrors', () async {
      const expA = 'exp-batch-a';
      const expB = 'exp-batch-b';
      const mirA = 'mirror-batch-a';
      const mirB = 'mirror-batch-b';

      await seedGroupExpense(expenseId: expA, groupId: 'grp-batch-a', amount: '30.00');
      await seedGroupExpense(expenseId: expB, groupId: 'grp-batch-b', amount: '70.00');
      await createMirror(mirrorId: mirA, sourceExpenseId: expA, amount: '30.00');
      await createMirror(mirrorId: mirB, sourceExpenseId: expB, amount: '70.00');

      var mirrors = await db.query('expenses',
          where: 'payer_id = ? AND group_id IS NULL AND source_expense_id IS NOT NULL',
          whereArgs: [_uid]);
      expect(mirrors, hasLength(2));

      final result = await repo.deleteExpenses([expA, expB]);
      expect(result, isTrue);

      mirrors = await db.query('expenses',
          where: 'payer_id = ? AND group_id IS NULL AND source_expense_id IS NOT NULL',
          whereArgs: [_uid]);
      expect(mirrors, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 4 — Edit propagation: mirror updated when source expense edited
  // ──────────────────────────────────────────────────────────────────────────
  group('edit propagation', () {
    test('edit group expense updates mirror amount', () async {
      const expenseId = 'exp-edit-1';
      const mirrorId  = 'mirror-edit-1';

      await seedGroupExpense(expenseId: expenseId, groupId: 'grp-edit-1', amount: '100.00');
      await createMirror(mirrorId: mirrorId, sourceExpenseId: expenseId, amount: '100.00');

      // Capture the mirror's original date — editing must NOT reset it to now.
      final before = await db.query('expenses',
          columns: ['created_at'],
          where: 'source_expense_id = ?', whereArgs: [expenseId]);
      final originalCreatedAt = before.first['created_at'];

      // Edit: change my share from 100.00 → 33.33 USD.
      final updated = await repo.updateExpense(
        expenseId:   expenseId,
        groupId:     'grp-edit-1',
        payerId:     _uid,
        amount:      Decimal.parse('100.00'),
        description: 'Test expense',
        currency:    'USD',
        splitType:   SplitType.even,
        splits:      [SplitInsert(userId: _uid, universalUsdOwed: Decimal.parse('33.33'))],
        category:    'Food & drink',
      );
      expect(updated, isNotNull);

      // Mirror must have the new share amount.
      final mirrors = await db.query('expenses',
          where: 'payer_id = ? AND source_expense_id = ? AND group_id IS NULL',
          whereArgs: [_uid, expenseId]);
      expect(mirrors, hasLength(1));
      expect(mirrors.first['amount'], '33.33');
      // …and its original date must be preserved (not jumped to today).
      expect(mirrors.first['created_at'], originalCreatedAt);
    });

    test('edit group expense to zero share removes mirror', () async {
      const expenseId = 'exp-edit-2';
      const mirrorId  = 'mirror-edit-2';

      await seedGroupExpense(expenseId: expenseId, groupId: 'grp-edit-2', amount: '100.00');
      await createMirror(mirrorId: mirrorId, sourceExpenseId: expenseId, amount: '100.00');

      // Edit: set my share to 0 (no longer a participant).
      final updated = await repo.updateExpense(
        expenseId:   expenseId,
        groupId:     'grp-edit-2',
        payerId:     _uid,
        amount:      Decimal.parse('100.00'),
        description: 'Test expense',
        currency:    'USD',
        splitType:   SplitType.even,
        splits:      [SplitInsert(userId: 'other-user', universalUsdOwed: Decimal.parse('100.00'))],
        category:    'Food & drink',
      );
      expect(updated, isNotNull);

      // Mirror must be gone.
      final mirrors = await db.query('expenses',
          where: 'payer_id = ? AND source_expense_id = ? AND group_id IS NULL',
          whereArgs: [_uid, expenseId]);
      expect(mirrors, isEmpty);
    });

    test('edit expense with no mirror is a no-op (no error)', () async {
      const expenseId = 'exp-edit-3';

      await seedGroupExpense(expenseId: expenseId, groupId: 'grp-edit-3', amount: '50.00');
      // No mirror — edit should succeed without errors.

      final updated = await repo.updateExpense(
        expenseId:   expenseId,
        groupId:     'grp-edit-3',
        payerId:     _uid,
        amount:      Decimal.parse('50.00'),
        description: 'Test expense',
        currency:    'USD',
        splitType:   SplitType.even,
        splits:      [SplitInsert(userId: _uid, universalUsdOwed: Decimal.parse('25.00'))],
        category:    'Food & drink',
      );
      expect(updated, isNotNull);
    });

    test('edit does not create duplicate mirrors', () async {
      const expenseId = 'exp-edit-4';
      const mirrorId  = 'mirror-edit-4';

      await seedGroupExpense(expenseId: expenseId, groupId: 'grp-edit-4', amount: '100.00');
      await createMirror(mirrorId: mirrorId, sourceExpenseId: expenseId, amount: '100.00');

      // First edit.
      await repo.updateExpense(
        expenseId:   expenseId,
        groupId:     'grp-edit-4',
        payerId:     _uid,
        amount:      Decimal.parse('100.00'),
        description: 'Test expense',
        currency:    'USD',
        splitType:   SplitType.even,
        splits:      [SplitInsert(userId: _uid, universalUsdOwed: Decimal.parse('50.00'))],
        category:    'Food & drink',
      );

      // Second edit.
      await repo.updateExpense(
        expenseId:   expenseId,
        groupId:     'grp-edit-4',
        payerId:     _uid,
        amount:      Decimal.parse('100.00'),
        description: 'Test expense (edited)',
        currency:    'USD',
        splitType:   SplitType.even,
        splits:      [SplitInsert(userId: _uid, universalUsdOwed: Decimal.parse('75.00'))],
        category:    'Food & drink',
      );

      // Still exactly one mirror.
      final mirrors = await db.query('expenses',
          where: 'payer_id = ? AND source_expense_id = ? AND group_id IS NULL',
          whereArgs: [_uid, expenseId]);
      expect(mirrors, hasLength(1));
      // Decimal.toString drops trailing zeros; 75.00 → '75'.
      expect(mirrors.first['amount'], '75');
      expect(mirrors.first['description'], 'Share · Test expense (edited)');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 5 — deleteGroup removes wallet mirrors (5c-ii)
  // ──────────────────────────────────────────────────────────────────────────
  group('deleteGroup mirror cleanup', () {
    test('deleteGroup (owner) removes linked mirror', () async {
      const expenseId = 'exp-delgrp-1';
      const groupId   = 'grp-del-1';
      const mirrorId  = 'mirror-delgrp-1';

      await seedGroupExpense(
        expenseId: expenseId, groupId: groupId, amount: '100.00');
      await createMirror(
        mirrorId: mirrorId, sourceExpenseId: expenseId, amount: '100.00');

      // Verify mirror exists before group delete.
      var mirrors = await db.query('expenses',
          where: 'payer_id = ? AND source_expense_id = ? AND group_id IS NULL',
          whereArgs: [_uid, expenseId]);
      expect(mirrors, hasLength(1));

      final result = await repo.deleteGroup(groupId);
      expect(result, isTrue);

      // Mirror must be gone after group delete.
      mirrors = await db.query('expenses',
          where: 'payer_id = ? AND source_expense_id = ? AND group_id IS NULL',
          whereArgs: [_uid, expenseId]);
      expect(mirrors, isEmpty);
    });

    test('deleteGroup with no mirrors is a no-op (no error)', () async {
      const expenseId = 'exp-delgrp-2';
      const groupId   = 'grp-del-2';

      await seedGroupExpense(
        expenseId: expenseId, groupId: groupId, amount: '50.00');
      // No mirror created — deleteGroup should still succeed.

      final result = await repo.deleteGroup(groupId);
      expect(result, isTrue);
    });

    test('deleteGroup deletes mirrors for all expenses in the group', () async {
      const expA = 'exp-delgrp-batch-a';
      const expB = 'exp-delgrp-batch-b';
      const groupId = 'grp-del-batch';
      const mirA = 'mirror-batch-delgrp-a';
      const mirB = 'mirror-batch-delgrp-b';

      await db.insert('groups', {
        'id': groupId, 'name': 'Batch Group', 'creator_id': _uid,
        'created_by': _uid, 'type': 'normal', 'is_deleted': 0,
        'created_at': isoNow(), 'updated_at': isoNow(),
      });
      await db.insert('group_members', {
        'group_id': groupId, 'user_id': _uid, 'joined_at': isoNow(),
      });
      for (final exp in [
        (id: expA, amt: '30.00'),
        (id: expB, amt: '70.00'),
      ]) {
        await db.insert('expenses', {
          'id': exp.id, 'group_id': groupId, 'payer_id': _uid,
          'created_by': _uid, 'amount': exp.amt, 'description': 'Test',
          'currency': 'USD', 'split_type': 'even', 'category': 'Food & drink',
          'is_income': 0, 'created_at': isoNow(), 'universal_usd_amount': exp.amt,
        });
        await db.insert('splits', {
          'id': 'split-$exp.id', 'expense_id': exp.id, 'user_id': _uid,
          'universal_usd_owed': exp.amt, 'entry_amount_owed': exp.amt,
          'created_at': isoNow(),
        });
      }
      await createMirror(mirrorId: mirA, sourceExpenseId: expA, amount: '30.00');
      await createMirror(mirrorId: mirB, sourceExpenseId: expB, amount: '70.00');

      var mirrors = await db.query('expenses',
          where: 'payer_id = ? AND group_id IS NULL AND source_expense_id IS NOT NULL',
          whereArgs: [_uid]);
      expect(mirrors, hasLength(2));

      final result = await repo.deleteGroup(groupId);
      expect(result, isTrue);

      mirrors = await db.query('expenses',
          where: 'payer_id = ? AND group_id IS NULL AND source_expense_id IS NOT NULL',
          whereArgs: [_uid]);
      expect(mirrors, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 6 — sourceGroupName resolution (5c-ii)
  // ──────────────────────────────────────────────────────────────────────────
  group('sourceGroupName', () {
    test('returns group name for a linked mirror', () async {
      const expenseId = 'exp-srcname-1';
      const groupId   = 'grp-srcname-1';
      const groupName = 'Test Group Name';

      // Seed with a specific group name.
      await db.insert('groups', {
        'id': groupId, 'name': groupName, 'creator_id': _uid,
        'created_by': _uid, 'type': 'normal', 'is_deleted': 0,
        'created_at': isoNow(), 'updated_at': isoNow(),
      });
      await db.insert('group_members', {
        'group_id': groupId, 'user_id': _uid, 'joined_at': isoNow(),
      });
      await db.insert('expenses', {
        'id': expenseId, 'group_id': groupId, 'payer_id': _uid,
        'created_by': _uid, 'amount': '100.00', 'description': 'Test',
        'currency': 'USD', 'split_type': 'even', 'category': 'Food & drink',
        'is_income': 0, 'created_at': isoNow(), 'universal_usd_amount': '100.00',
      });

      final name = await repo.sourceGroupName(expenseId);
      expect(name, groupName);
    });

    test('returns null when source expense does not exist', () async {
      final name = await repo.sourceGroupName('non-existent-expense-id');
      expect(name, isNull);
    });

    test('returns null when source expense has no group', () async {
      const expenseId = 'exp-srcname-2';

      await db.insert('expenses', {
        'id': expenseId, 'group_id': null, 'payer_id': _uid,
        'created_by': _uid, 'amount': '50.00', 'description': 'Personal',
        'currency': 'USD', 'split_type': 'even', 'category': 'General',
        'is_income': 0, 'created_at': isoNow(), 'universal_usd_amount': '50.00',
      });

      final name = await repo.sourceGroupName(expenseId);
      expect(name, isNull);
    });

    test('returns null when the group has been deleted', () async {
      const expenseId = 'exp-srcname-3';
      const groupId   = 'grp-srcname-3';

      await db.insert('groups', {
        'id': groupId, 'name': 'Gone Group', 'creator_id': _uid,
        'created_by': _uid, 'type': 'normal', 'is_deleted': 0,
        'created_at': isoNow(), 'updated_at': isoNow(),
      });
      await db.insert('expenses', {
        'id': expenseId, 'group_id': groupId, 'payer_id': _uid,
        'created_by': _uid, 'amount': '25.00', 'description': 'Test',
        'currency': 'USD', 'split_type': 'even', 'category': 'Food & drink',
        'is_income': 0, 'created_at': isoNow(), 'universal_usd_amount': '25.00',
      });

      // Delete the group from the DB (simulate gone group).
      await db.delete('groups', where: 'id = ?', whereArgs: [groupId]);

      final name = await repo.sourceGroupName(expenseId);
      expect(name, isNull);
    });
  });
}

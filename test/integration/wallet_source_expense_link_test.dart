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
              deleted_at TEXT NOT NULL, deleted_with_group_id TEXT
            )
          ''');
          await db.execute('''
            CREATE TABLE deleted_splits (
              id TEXT PRIMARY KEY, expense_id TEXT NOT NULL,
              user_id TEXT NOT NULL, amount_owed TEXT,
              universal_usd_owed TEXT, deleted_with_group_id TEXT NOT NULL
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
}

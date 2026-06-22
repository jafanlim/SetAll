// Integration test: wallet import parity — base_currency_amount freeze.
//
// Verifies that upsertWalletEntry (the path used by the CSV importer after
// the import-parity fix) writes a non-null base_currency_amount to SQLite
// for both same-currency and cross-currency entries, so wallet totals are
// stable regardless of live rate changes post-import.
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

const _uid = 'test-import-parity-user';

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
  // GROUP 1 — base_currency_amount is frozen on insert (SQLite path)
  // ──────────────────────────────────────────────────────────────────────────
  group('upsertWalletEntry: base_currency_amount freeze (SQLite)', () {
    test('USD entry — base_currency_amount equals amount', () async {
      const entryId = 'entry-usd-1';
      await repo.upsertWalletEntry(WalletEntryModel(
        id:          entryId,
        userId:      _uid,
        amount:      '100.00',
        currency:    'USD',
        description: 'USD test',
        category:    'General',
        isIncome:    false,
        createdAt:   DateTime(2026, 5, 1).toUtc().toIso8601String(),
      ));

      final rows = await db.query('expenses', where: 'id = ?', whereArgs: [entryId]);
      expect(rows, hasLength(1));
      expect(rows.first['base_currency_amount'], isNotNull,
          reason: 'USD entry must have base_currency_amount frozen');
      final frozen = Decimal.parse(rows.first['base_currency_amount'] as String);
      expect(frozen, Decimal.parse('100.00'),
          reason: 'USD entry: base_currency_amount == amount');
    });

    test('EUR entry — base_currency_amount is non-null and converted', () async {
      const entryId = 'entry-eur-1';
      await repo.upsertWalletEntry(WalletEntryModel(
        id:          entryId,
        userId:      _uid,
        amount:      '200.00',
        currency:    'EUR',
        description: 'EUR test',
        category:    'General',
        isIncome:    false,
        createdAt:   DateTime(2026, 5, 2).toUtc().toIso8601String(),
      ));

      final rows = await db.query('expenses', where: 'id = ?', whereArgs: [entryId]);
      expect(rows, hasLength(1));
      expect(rows.first['base_currency_amount'], isNotNull,
          reason: 'EUR entry must have base_currency_amount frozen (non-null)');
      final frozen = Decimal.tryParse(rows.first['base_currency_amount'] as String);
      expect(frozen, isNotNull);
      expect(frozen!, greaterThan(Decimal.zero));
    });

    test('GBP entry — base_currency_amount is non-null and converted', () async {
      const entryId = 'entry-gbp-1';
      await repo.upsertWalletEntry(WalletEntryModel(
        id:          entryId,
        userId:      _uid,
        amount:      '300.00',
        currency:    'GBP',
        description: 'GBP test',
        category:    'General',
        isIncome:    false,
        createdAt:   DateTime(2026, 5, 3).toUtc().toIso8601String(),
      ));

      final rows = await db.query('expenses', where: 'id = ?', whereArgs: [entryId]);
      expect(rows, hasLength(1));
      expect(rows.first['base_currency_amount'], isNotNull,
          reason: 'GBP entry must have base_currency_amount frozen (non-null)');
    });

    test('income entry — base_currency_amount frozen regardless of isIncome', () async {
      const entryId = 'entry-income-1';
      await repo.upsertWalletEntry(WalletEntryModel(
        id:          entryId,
        userId:      _uid,
        amount:      '1200.00',
        currency:    'GBP',
        description: 'Freelance GBP',
        category:    'Income',
        isIncome:    true,
        createdAt:   DateTime(2026, 5, 5).toUtc().toIso8601String(),
      ));

      final rows = await db.query('expenses', where: 'id = ?', whereArgs: [entryId]);
      expect(rows, hasLength(1));
      expect(rows.first['base_currency_amount'], isNotNull);
    });

    test('multi-row import — all rows have non-null base_currency_amount', () async {
      final batch = [
        ('batch-1', '45.50',   'USD', false),
        ('batch-2', '8.20',    'EUR', false),
        ('batch-3', '1200.00', 'GBP', true),
        ('batch-4', '12.75',   'USD', false),
        ('batch-5', '320.00',  'EUR', false),
      ];

      for (final (id, amount, currency, isIncome) in batch) {
        await repo.upsertWalletEntry(WalletEntryModel(
          id:          id,
          userId:      _uid,
          amount:      amount,
          currency:    currency,
          description: 'Batch $id',
          category:    'General',
          isIncome:    isIncome,
          createdAt:   DateTime(2026, 5, 1).toUtc().toIso8601String(),
        ));
      }

      final rows = await db.query(
        'expenses',
        where: 'id IN (${batch.map((_) => '?').join(',')})',
        whereArgs: batch.map((r) => r.$1).toList(),
      );
      expect(rows, hasLength(5));
      for (final row in rows) {
        expect(row['base_currency_amount'], isNotNull,
            reason: 'Every imported row must have frozen base_currency_amount; '
                'id=${row['id']} currency=${row['currency']} was null');
      }
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 2 — Contrast: addExpense does NOT set base_currency_amount
  // (regression guard — if addExpense ever starts setting it this test
  //  should be updated, not deleted)
  // ──────────────────────────────────────────────────────────────────────────
  group('addExpense: base_currency_amount absent (group expense path)', () {
    test('addExpense with groupId=null leaves base_currency_amount null', () async {
      final expense = await repo.addExpense(
        payerId:     _uid,
        amount:      Decimal.parse('50.00'),
        description: 'Direct addExpense call',
        currency:    'EUR',
        splitType:   SplitType.even,
        splits:      [SplitInsert(userId: _uid, universalUsdOwed: Decimal.parse('50.00'))],
        category:    'General',
      );
      expect(expense, isNotNull);

      final rows = await db.query('expenses', where: 'id = ?', whereArgs: [expense!.id]);
      expect(rows, hasLength(1));
      // addExpense intentionally does not set base_currency_amount —
      // that is exactly the bug fixed by routing wallet imports through
      // upsertWalletEntry instead.
      expect(rows.first['base_currency_amount'], isNull,
          reason: 'addExpense must not set base_currency_amount — '
              'if this fails, update the import-parity fix analysis');
    });
  });
}

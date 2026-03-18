// Integration test: multi-currency expense → USD anchor → retrieval precision.
//
// Verifies that an expense entered in a foreign currency (e.g. GEL) is:
//   1. Converted to USD using CurrencyService (stubbed rate).
//   2. Stored in SQLite with universal_usd_amount (Decimal, not double).
//   3. Retrieved with zero precision loss.
//   4. Split amounts preserve the Decimal invariant (sum == total).

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:setall/core/services/currency_service.dart';
import 'package:setall/core/utils/split_engine.dart';
import 'package:setall/data/local/local_database.dart';
import 'package:setall/data/repositories/setall_repository.dart';
import 'package:setall/domain/entities/expense.dart';

/// Stubbed CurrencyService that returns a fixed GEL→USD rate of 0.3663
/// (realistic rate as of 2026) without hitting any network endpoint.
class _StubbedCurrencyService extends CurrencyService {
  _StubbedCurrencyService() : super();

  static final Decimal gelToUsd = Decimal.parse('0.3663');

  @override
  Future<Decimal> getRate(String from, String to) async {
    if (from == to) return Decimal.one;
    if (from == 'GEL' && to == 'USD') return gelToUsd;
    if (from == 'USD' && to == 'GEL') {
      return (Decimal.one / gelToUsd).toDecimal(scaleOnInfinitePrecision: 6);
    }
    // EUR→USD stub
    if (from == 'EUR' && to == 'USD') return Decimal.parse('1.0842');
    if (from == 'USD' && to == 'EUR') return Decimal.parse('0.9223');
    return Decimal.one;
  }

  @override
  Future<Decimal> getRateToUsd(String fromCurrency) => getRate(fromCurrency, 'USD');
}

const _uid = 'test-user-usd-flow';

void main() {
  late Database db;
  late SetAllRepository repo;
  late _StubbedCurrencyService currencyService;

  setUpAll(() => sqfliteFfiInit());

  setUp(() async {
    SharedPreferences.setMockInitialValues({'device_user_id': _uid});
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

    currencyService = _StubbedCurrencyService();
    repo = SetAllRepository(currencyService: currencyService);
  });

  tearDown(() async {
    await db.close();
    LocalDatabase.resetForTesting();
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 1. GEL→USD conversion accuracy
  // ─────────────────────────────────────────────────────────────────────────
  group('GEL→USD conversion precision', () {
    test('100 GEL converts to exact USD using Decimal arithmetic', () async {
      final gelAmount = Decimal.parse('100.00');
      final rate = await currencyService.getRate('GEL', 'USD');
      final usdAmount = (gelAmount * rate).round(scale: 2);

      // 100 * 0.3663 = 36.63 exactly
      expect(usdAmount, equals(Decimal.parse('36.63')),
          reason: 'GEL→USD must use Decimal without floating-point drift');
    });

    test('indivisible GEL amount (e.g. 33.33) converts without precision loss',
        () async {
      final gelAmount = Decimal.parse('33.33');
      final rate = await currencyService.getRate('GEL', 'USD');
      final usdAmount = (gelAmount * rate).round(scale: 2);

      // 33.33 * 0.3663 = 12.207879 → rounded to 12.21
      expect(usdAmount, equals(Decimal.parse('12.21')));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. Full addExpense round-trip
  // ─────────────────────────────────────────────────────────────────────────
  group('addExpense USD anchor round-trip', () {
    test('GEL expense stores correct universal_usd_amount in SQLite', () async {
      final gelAmount = Decimal.parse('250.00');
      final expectedUsd = (gelAmount * _StubbedCurrencyService.gelToUsd).round(scale: 2);

      final expense = await repo.addExpense(
        payerId: _uid,
        amount: gelAmount,
        description: 'Georgian dinner',
        currency: 'GEL',
        splitType: SplitType.even,
        splits: [SplitInsert(userId: _uid, universalUsdOwed: gelAmount)],
        category: 'Food',
      );

      expect(expense, isNotNull);

      // Read back from SQLite
      final rows = await db.query('expenses', where: 'id = ?', whereArgs: [expense!.id]);
      expect(rows, hasLength(1));

      final storedUsd = Decimal.parse(rows.first['universal_usd_amount'] as String);
      expect(storedUsd, equals(expectedUsd),
          reason: 'universal_usd_amount must match Decimal computation exactly');
    });

    test('split universal_usd_owed matches the anchored USD amount', () async {
      final gelAmount = Decimal.parse('100.00');
      final expectedUsd = (gelAmount * _StubbedCurrencyService.gelToUsd).round(scale: 2);

      final expense = await repo.addExpense(
        payerId: _uid,
        amount: gelAmount,
        description: 'Split test',
        currency: 'GEL',
        splitType: SplitType.even,
        splits: [SplitInsert(userId: _uid, universalUsdOwed: gelAmount)],
      );

      final splitRows = await db.query(
        'splits',
        where: 'expense_id = ?',
        whereArgs: [expense!.id],
      );
      expect(splitRows, hasLength(1));

      final splitUsd = Decimal.parse(splitRows.first['universal_usd_owed'] as String);
      expect(splitUsd, equals(expectedUsd),
          reason: 'Split USD amount must match expense USD anchor');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. SplitEngine Decimal invariant with foreign currency
  // ─────────────────────────────────────────────────────────────────────────
  group('SplitEngine Decimal invariant (multi-currency)', () {
    test('5-way even split of 100 GEL (USD-anchored): sum == total', () {
      final gelAmount = Decimal.parse('100.00');
      final usdTotal = (gelAmount * _StubbedCurrencyService.gelToUsd).round(scale: 2);
      // 36.63 / 5 = 7.326 → penny distribution
      final participants = ['u1', 'u2', 'u3', 'u4', 'u5'];
      final splits = SplitEngine.splitEven(
        total: usdTotal,
        participantIds: participants,
        payerId: 'u1',
      );

      final sum = splits.fold(Decimal.zero, (a, s) => a + s.amountOwed);
      expect(sum, equals(usdTotal),
          reason: 'Split sum must exactly equal the USD-anchored total (no penny leak)');
    });

    test('3-way split of 33.33 USD: payer absorbs remainder', () {
      final total = Decimal.parse('33.33');
      final splits = SplitEngine.splitEven(
        total: total,
        participantIds: ['alice', 'bob', 'charlie'],
        payerId: 'alice',
      );

      final byUser = {for (final s in splits) s.userId: s.amountOwed};

      // 33.33 / 3 = 11.11 each, no remainder
      expect(byUser['alice'], equals(Decimal.parse('11.11')));
      expect(byUser['bob'], equals(Decimal.parse('11.11')));
      expect(byUser['charlie'], equals(Decimal.parse('11.11')));

      final sum = splits.fold(Decimal.zero, (a, s) => a + s.amountOwed);
      expect(sum, equals(total));
    });
  });
}

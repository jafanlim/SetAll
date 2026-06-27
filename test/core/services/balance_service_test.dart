// Hermetic tests for BalanceService netting (TASK 3 — net-balance correctness).
//
// Uses in-memory SQLite + stubbed CurrencyService (same pattern as
// wallet_import_parity_test.dart and import_dedup_test.dart).
// Verifies that:
//   - A↔B mutual debts net to zero
//   - One-directional debt shows correct non-zero side
//   - Group-scoped balance nets correctly
//   - Non-USD base currency conversion works
//   - Settled groups zero out
// No network. No Supabase.

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:setall/core/services/balance_service.dart';
import 'package:setall/core/services/currency_service.dart';
import 'package:setall/data/local/local_database.dart';
import 'package:setall/data/repositories/setall_repository.dart';

// ──────────────────────────────────────────────────────────────────────────────
// Stubbed rates
// ──────────────────────────────────────────────────────────────────────────────
class _StubRates extends CurrencyService {
  _StubRates() : super();

  @override
  Future<Decimal> getRate(String from, String to) async {
    if (from == to) return Decimal.one;
    const rates = {
      'EUR→USD': '1.08',
      'USD→EUR': '0.9259',
      'GBP→USD': '1.27',
      'USD→GBP': '0.7874',
      'GEL→USD': '0.3663',
    };
    return Decimal.parse(rates['$from→$to'] ?? '1.0');
  }

  @override
  Future<Decimal> getRateToUsd(String from) => getRate(from, 'USD');
}

const _uid = 'test-balance-user-a';
const _uidB = 'test-balance-user-b';
const _gid = 'test-balance-group';

// ──────────────────────────────────────────────────────────────────────────────
// DB helpers
// ──────────────────────────────────────────────────────────────────────────────
Future<void> _seedExpense({
  required Database db,
  required String id,
  required String groupId,
  required String payerId,
  required String amount,
  String currency = 'USD',
  String? universalUsdAmount,
  String description = '',
}) async {
  await db.insert('expenses', {
    'id': id,
    'group_id': groupId,
    'payer_id': payerId,
    'amount': amount,
    'currency': currency,
    'universal_usd_amount': universalUsdAmount ?? amount,
    'description': description,
    'category': 'General',
    'created_at': '2026-06-01T00:00:00.000Z',
    'is_income': 0,
  });
}

Future<void> _seedSplit({
  required Database db,
  required String id,
  required String expenseId,
  required String userId,
  required String universalUsdOwed,
}) async {
  await db.insert('splits', {
    'id': id,
    'expense_id': expenseId,
    'user_id': userId,
    'universal_usd_owed': universalUsdOwed,
    'created_at': '2026-06-01T00:00:00.000Z',
  });
}

void main() {
  late Database db;
  late SetAllRepository repo;
  late BalanceService svc;

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
              default_currency TEXT, settled_at TEXT,
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

    // Seed profile for _uid with USD as default.
    await db.insert('profiles', {
      'id': _uid,
      'name': 'User A',
      'default_currency': 'USD',
      'is_ghost': 0,
    });

    // Seed the group.
    await db.insert('groups', {
      'id': _gid,
      'name': 'Test Group',
      'creator_id': _uid,
      'type': 'normal',
      'is_deleted': 0,
      'created_at': '2026-06-01T00:00:00.000Z',
    });

    // Add both users as group members.
    await db.insert('group_members', {
      'group_id': _gid, 'user_id': _uid, 'joined_at': '2026-06-01T00:00:00.000Z',
    });
    await db.insert('group_members', {
      'group_id': _gid, 'user_id': _uidB, 'joined_at': '2026-06-01T00:00:00.000Z',
    });

    repo = SetAllRepository(currencyService: _StubRates());
    svc = BalanceService(repository: repo, currencyService: _StubRates());
  });

  tearDown(() async {
    await db.close();
    LocalDatabase.resetForTesting();
  });

  // ──────────────────────────────────────────────────────────────────────────
  // getBalanceSummary — netting
  // ──────────────────────────────────────────────────────────────────────────

  group('getBalanceSummary: netting', () {
    test('mutual debts A↔B 50/50 → youOwe 0.00, youAreOwed 0.00', () async {
      // A pays 50 (split A25/B25) → A is owed 25 from B
      // B pays 50 (split A25/B25) → A owes 25 to B
      // Net: 0.
      await _seedExpense(db: db, id: 'e1', groupId: _gid, payerId: _uid,
          amount: '50.00', universalUsdAmount: '50.00');
      await _seedSplit(db: db, id: 's1a', expenseId: 'e1', userId: _uid,
          universalUsdOwed: '25.00');
      await _seedSplit(db: db, id: 's1b', expenseId: 'e1', userId: _uidB,
          universalUsdOwed: '25.00');

      await _seedExpense(db: db, id: 'e2', groupId: _gid, payerId: _uidB,
          amount: '50.00', universalUsdAmount: '50.00');
      await _seedSplit(db: db, id: 's2a', expenseId: 'e2', userId: _uid,
          universalUsdOwed: '25.00');
      await _seedSplit(db: db, id: 's2b', expenseId: 'e2', userId: _uidB,
          universalUsdOwed: '25.00');

      final summary = await svc.getBalanceSummary();

      expect(summary.youOwe, '0.00',
          reason: 'A owes B 25 but B owes A 25 → net youOwe = 0');
      expect(summary.youAreOwed, '0.00',
          reason: 'B owes A 25 but A owes B 25 → net youAreOwed = 0');
      expect(summary.currency, 'USD');
    });

    test('one-directional debt: A paid 100, B owes 50 → youAreOwed 50.00', () async {
      // A pays 100, splits: A 50, B 50 → B owes A 50.
      // No offsetting expense from B.
      await _seedExpense(db: db, id: 'e1', groupId: _gid, payerId: _uid,
          amount: '100.00', universalUsdAmount: '100.00');
      await _seedSplit(db: db, id: 's1a', expenseId: 'e1', userId: _uid,
          universalUsdOwed: '50.00');
      await _seedSplit(db: db, id: 's1b', expenseId: 'e1', userId: _uidB,
          universalUsdOwed: '50.00');

      final summary = await svc.getBalanceSummary();

      expect(summary.youAreOwed, '50.00');
      expect(summary.youOwe, '0.00');
    });

    test('one-directional debt: A paid 0, B paid 100 (split A50/B50) → youOwe 50.00', () async {
      // B pays 100, A owes 50. A paid nothing.
      await _seedExpense(db: db, id: 'e1', groupId: _gid, payerId: _uidB,
          amount: '100.00', universalUsdAmount: '100.00');
      await _seedSplit(db: db, id: 's1a', expenseId: 'e1', userId: _uid,
          universalUsdOwed: '50.00');
      await _seedSplit(db: db, id: 's1b', expenseId: 'e1', userId: _uidB,
          universalUsdOwed: '50.00');

      final summary = await svc.getBalanceSummary();

      expect(summary.youOwe, '50.00');
      expect(summary.youAreOwed, '0.00');
    });

    test('no expenses → zero balance', () async {
      final summary = await svc.getBalanceSummary();

      expect(summary.youOwe, '0.00');
      expect(summary.youAreOwed, '0.00');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // getGroupBalanceSummary — scoped netting
  // ──────────────────────────────────────────────────────────────────────────

  group('getGroupBalanceSummary: scoped netting', () {
    test('A↔B mutual 50/50 within one group → net zero', () async {
      await _seedExpense(db: db, id: 'e1', groupId: _gid, payerId: _uid,
          amount: '50.00', universalUsdAmount: '50.00');
      await _seedSplit(db: db, id: 's1a', expenseId: 'e1', userId: _uid,
          universalUsdOwed: '25.00');
      await _seedSplit(db: db, id: 's1b', expenseId: 'e1', userId: _uidB,
          universalUsdOwed: '25.00');

      await _seedExpense(db: db, id: 'e2', groupId: _gid, payerId: _uidB,
          amount: '50.00', universalUsdAmount: '50.00');
      await _seedSplit(db: db, id: 's2a', expenseId: 'e2', userId: _uid,
          universalUsdOwed: '25.00');
      await _seedSplit(db: db, id: 's2b', expenseId: 'e2', userId: _uidB,
          universalUsdOwed: '25.00');

      final summary = await svc.getGroupBalanceSummary(_gid);

      expect(summary.youOwe, '0.00');
      expect(summary.youAreOwed, '0.00');
    });

    test('one-directional debt scoped to group → correct non-zero side', () async {
      await _seedExpense(db: db, id: 'e1', groupId: _gid, payerId: _uid,
          amount: '200.00', universalUsdAmount: '200.00');
      await _seedSplit(db: db, id: 's1a', expenseId: 'e1', userId: _uid,
          universalUsdOwed: '100.00');
      await _seedSplit(db: db, id: 's1b', expenseId: 'e1', userId: _uidB,
          universalUsdOwed: '100.00');

      final summary = await svc.getGroupBalanceSummary(_gid);

      expect(summary.youAreOwed, '100.00');
      expect(summary.youOwe, '0.00');
      expect(summary.currency, 'USD');
    });

    test('expense in other group not included', () async {
      // Seed group 2.
      const gid2 = 'test-balance-group-2';
      await db.insert('groups', {
        'id': gid2, 'name': 'Group 2', 'creator_id': _uid,
        'type': 'normal', 'is_deleted': 0,
        'created_at': '2026-06-01T00:00:00.000Z',
      });
      await db.insert('group_members', {
        'group_id': gid2, 'user_id': _uid,
        'joined_at': '2026-06-01T00:00:00.000Z',
      });
      await db.insert('group_members', {
        'group_id': gid2, 'user_id': _uidB,
        'joined_at': '2026-06-01T00:00:00.000Z',
      });

      // Expense in gid2: A paid 500, B owes 500.
      await _seedExpense(db: db, id: 'e-g2', groupId: gid2, payerId: _uid,
          amount: '500.00', universalUsdAmount: '500.00');
      await _seedSplit(db: db, id: 'sg2a', expenseId: 'e-g2', userId: _uid,
          universalUsdOwed: '250.00');
      await _seedSplit(db: db, id: 'sg2b', expenseId: 'e-g2', userId: _uidB,
          universalUsdOwed: '250.00');

      // Query gid: should see 0, not 250 from gid2.
      final summary = await svc.getGroupBalanceSummary(_gid);

      // The test group _gid has no expenses → null raw data → zero.
      expect(summary.youAreOwed, '0.00');
      expect(summary.youOwe, '0.00');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Base-currency conversion via stub rate (non-USD base)
  // ──────────────────────────────────────────────────────────────────────────

  group('Base-currency conversion', () {
    test('EUR base: A paid 100 USD → youAreOwed in EUR', () async {
      // Update profile to EUR base.
      await db.update('profiles', {'default_currency': 'EUR'}, where: 'id = ?', whereArgs: [_uid]);

      // A paid 100 USD (split A50/B50) → B owes A 50 USD.
      await _seedExpense(db: db, id: 'e1', groupId: _gid, payerId: _uid,
          amount: '100.00', universalUsdAmount: '100.00');
      await _seedSplit(db: db, id: 's1a', expenseId: 'e1', userId: _uid,
          universalUsdOwed: '50.00');
      await _seedSplit(db: db, id: 's1b', expenseId: 'e1', userId: _uidB,
          universalUsdOwed: '50.00');

      final summary = await svc.getBalanceSummary();

      expect(summary.currency, 'EUR');
      // 50 USD × 0.9259 EUR/USD = 46.295 → rounded to 46.30.
      expect(summary.youAreOwed, '46.30');
      expect(summary.youOwe, '0.00');
    });

    test('EUR base: A↔B mutual → still zero in EUR', () async {
      await db.update('profiles', {'default_currency': 'EUR'}, where: 'id = ?', whereArgs: [_uid]);

      await _seedExpense(db: db, id: 'e1', groupId: _gid, payerId: _uid,
          amount: '50.00', universalUsdAmount: '50.00');
      await _seedSplit(db: db, id: 's1a', expenseId: 'e1', userId: _uid,
          universalUsdOwed: '25.00');
      await _seedSplit(db: db, id: 's1b', expenseId: 'e1', userId: _uidB,
          universalUsdOwed: '25.00');

      await _seedExpense(db: db, id: 'e2', groupId: _gid, payerId: _uidB,
          amount: '50.00', universalUsdAmount: '50.00');
      await _seedSplit(db: db, id: 's2a', expenseId: 'e2', userId: _uid,
          universalUsdOwed: '25.00');
      await _seedSplit(db: db, id: 's2b', expenseId: 'e2', userId: _uidB,
          universalUsdOwed: '25.00');

      final summary = await svc.getBalanceSummary();

      expect(summary.currency, 'EUR');
      expect(summary.youAreOwed, '0.00');
      expect(summary.youOwe, '0.00');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Settled group — zeroed
  // ──────────────────────────────────────────────────────────────────────────

  group('Settled group zeroes', () {
    test('settled_at set → getGroupBalanceSummary returns zero', () async {
      // Seed an expense in the group, then mark it settled.
      await _seedExpense(db: db, id: 'e1', groupId: _gid, payerId: _uid,
          amount: '100.00', universalUsdAmount: '100.00');
      await _seedSplit(db: db, id: 's1a', expenseId: 'e1', userId: _uid,
          universalUsdOwed: '50.00');
      await _seedSplit(db: db, id: 's1b', expenseId: 'e1', userId: _uidB,
          universalUsdOwed: '50.00');

      // Mark group as settled.
      await db.update('groups', {'settled_at': '2026-06-15T00:00:00.000Z'},
          where: 'id = ?', whereArgs: [_gid]);

      final summary = await svc.getGroupBalanceSummary(_gid);

      expect(summary.youAreOwed, '0.00',
          reason: 'settled groups must return zero balance');
      expect(summary.youOwe, '0.00');
    });

    test('global balance excludes settled groups', () async {
      // Seed expense in the group, but group is settled.
      await _seedExpense(db: db, id: 'e1', groupId: _gid, payerId: _uid,
          amount: '100.00', universalUsdAmount: '100.00');
      await _seedSplit(db: db, id: 's1a', expenseId: 'e1', userId: _uid,
          universalUsdOwed: '50.00');
      await _seedSplit(db: db, id: 's1b', expenseId: 'e1', userId: _uidB,
          universalUsdOwed: '50.00');

      // Mark group as settled — _getBalanceRawDataLocal filters out
      // groups with non-null settled_at.
      await db.update('groups', {'settled_at': '2026-06-15T00:00:00.000Z'},
          where: 'id = ?', whereArgs: [_gid]);

      final summary = await svc.getBalanceSummary();

      // The group's expenses are excluded because settled_at IS NOT NULL.
      expect(summary.youAreOwed, '0.00');
      expect(summary.youOwe, '0.00');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Anti-vacuous guard
  // ──────────────────────────────────────────────────────────────────────────

  group('Anti-vacuous guard', () {
    test('mutual debt would show non-zero if netting were broken', () async {
      // A paid 50, B owes 25; B paid 50, A owes 25.
      // If BalanceService did NOT net, youAreOwed would be 25 AND youOwe would be 25.
      // With netting, both are 0.
      await _seedExpense(db: db, id: 'e1', groupId: _gid, payerId: _uid,
          amount: '50.00', universalUsdAmount: '50.00');
      await _seedSplit(db: db, id: 's1a', expenseId: 'e1', userId: _uid,
          universalUsdOwed: '25.00');
      await _seedSplit(db: db, id: 's1b', expenseId: 'e1', userId: _uidB,
          universalUsdOwed: '25.00');

      await _seedExpense(db: db, id: 'e2', groupId: _gid, payerId: _uidB,
          amount: '50.00', universalUsdAmount: '50.00');
      await _seedSplit(db: db, id: 's2a', expenseId: 'e2', userId: _uid,
          universalUsdOwed: '25.00');
      await _seedSplit(db: db, id: 's2b', expenseId: 'e2', userId: _uidB,
          universalUsdOwed: '25.00');

      final summary = await svc.getBalanceSummary();

      // ANTI-VACUOUS: without netting, raw totals would be
      //   youAreOwed = 25.00 (from e1) AND youOwe = 25.00 (from e2).
      // With netting, both must be 0.00.
      expect(summary.youAreOwed, '0.00',
          reason: 'ANTI-VACUOUS: without netting this would be 25.00');
      expect(summary.youOwe, '0.00',
          reason: 'ANTI-VACUOUS: without netting this would be 25.00');
    });
  });
}

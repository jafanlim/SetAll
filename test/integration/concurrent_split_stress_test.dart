// Concurrent Split Stress Test
//
// Torture-tests the SettlementEngine (Greedy Flow) and LocalDatabase with:
//   - 500+ transactions across multiple groups
//   - 20+ group members
//   - Timing assertions: Greedy Flow must resolve in < 100ms per group
//
// Uses only in-memory SQLite — no network, no Supabase.

import 'dart:math';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:setall/data/local/local_database.dart';
import 'package:setall/data/models/split_model.dart';
import 'package:setall/data/repositories/setall_repository.dart';
import 'package:setall/domain/services/settlement_engine.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Schema helpers (same structure as repository_crud_test.dart)
// ─────────────────────────────────────────────────────────────────────────────

Future<void> _createSchema(Database db, int _) async {
  await db.execute('''
    CREATE TABLE groups (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, creator_id TEXT NOT NULL,
      type TEXT NOT NULL DEFAULT 'normal', is_deleted INTEGER NOT NULL DEFAULT 0,
      deleted_at TEXT, created_at TEXT, updated_at TEXT, synced_at INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE group_members (
      group_id TEXT NOT NULL, user_id TEXT NOT NULL,
      joined_at TEXT, synced_at INTEGER, PRIMARY KEY (group_id, user_id)
    )
  ''');
  await db.execute('''
    CREATE TABLE expenses (
      id TEXT PRIMARY KEY, group_id TEXT, payer_id TEXT NOT NULL,
      amount TEXT NOT NULL, base_amount_at_entry TEXT, description TEXT,
      currency TEXT, split_type TEXT, category TEXT, universal_usd_amount TEXT,
      created_at TEXT, updated_at TEXT, synced_at INTEGER
    )
  ''');
  await db.execute('''
    CREATE TABLE splits (
      id TEXT PRIMARY KEY, expense_id TEXT NOT NULL, user_id TEXT NOT NULL,
      universal_usd_owed TEXT NOT NULL, entry_amount_owed TEXT,
      created_at TEXT, synced_at INTEGER, UNIQUE(expense_id, user_id)
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
    CREATE TABLE deleted_expenses (
      expense_id TEXT PRIMARY KEY, description TEXT, amount TEXT NOT NULL,
      currency TEXT, group_id TEXT, group_name TEXT,
      is_income INTEGER NOT NULL DEFAULT 0, category TEXT,
      deleted_by TEXT NOT NULL, deleted_at TEXT NOT NULL, deleted_with_group_id TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE deleted_splits (
      id TEXT PRIMARY KEY, expense_id TEXT NOT NULL, user_id TEXT NOT NULL,
      amount_owed TEXT, universal_usd_owed TEXT, deleted_with_group_id TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE deleted_groups_log (
      group_id TEXT PRIMARY KEY, group_name TEXT NOT NULL, creator_id TEXT NOT NULL,
      deleted_by_uid TEXT NOT NULL, deleted_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE exchange_rates (
      base_currency TEXT NOT NULL, target_currency TEXT NOT NULL,
      rate TEXT NOT NULL, last_updated TEXT,
      PRIMARY KEY (base_currency, target_currency)
    )
  ''');
  await db.execute('''
    CREATE TABLE user_categories (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, type TEXT NOT NULL DEFAULT 'expense',
      created_by TEXT NOT NULL, created_at TEXT
    )
  ''');
  await db.execute('''
    CREATE TABLE expense_edits (
      id TEXT PRIMARY KEY, expense_id TEXT NOT NULL, edited_by TEXT NOT NULL,
      edited_at TEXT NOT NULL
    )
  ''');
}

// ─────────────────────────────────────────────────────────────────────────────
// Data builders
// ─────────────────────────────────────────────────────────────────────────────

Map<String, dynamic> _buildExpense({
  required String id,
  required String groupId,
  required String payerId,
  required String amount,
  String currency = 'USD',
}) =>
    {
      'id': id,
      'group_id': groupId,
      'payer_id': payerId,
      'amount': amount,
      'currency': currency,
      'base_amount_at_entry': amount,
    };

SplitModel _buildSplit({
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
// Invariant validators
// ─────────────────────────────────────────────────────────────────────────────

/// Verifies that all settlement transactions clear all debts (net balance = 0).
void _assertFullySettled(
  List<Map<String, dynamic>> expenses,
  List<SplitModel> splits,
  List<SettlementTransaction> transactions,
) {
  final balances = <String, Decimal>{};

  for (final e in expenses) {
    final payer = e['payer_id'] as String;
    final amount = Decimal.parse(e['base_amount_at_entry'] as String);
    balances[payer] = (balances[payer] ?? Decimal.zero) + amount;
  }
  for (final s in splits) {
    final owed = Decimal.parse(s.universalUsdOwed);
    balances[s.userId] = (balances[s.userId] ?? Decimal.zero) - owed;
  }
  for (final t in transactions) {
    // fromUserId (debtor) pays t.amount → their paid increases → balance moves toward 0
    balances[t.fromUserId] =
        (balances[t.fromUserId] ?? Decimal.zero) + t.amount;
    // toUserId (creditor) receives t.amount → their net credit decreases toward 0
    balances[t.toUserId] =
        (balances[t.toUserId] ?? Decimal.zero) - t.amount;
  }

  for (final entry in balances.entries) {
    expect(entry.value.abs() <= Decimal.parse('0.02'), isTrue,
        reason: 'Member ${entry.key} has unsettled balance ${entry.value} '
            'after Greedy Flow — must be ~0');
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Test fixture
// ─────────────────────────────────────────────────────────────────────────────

late Database _db;

Future<void> _setUp() async {
  SharedPreferences.setMockInitialValues({'device_user_id': 'stress-owner'});
  _db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(version: 1, onCreate: _createSchema),
  );
  LocalDatabase.injectForTesting(_db);
  SetAllRepository(); // ensure prefs are wired
}

Future<void> _tearDown() async {
  LocalDatabase.resetForTesting();
  await _db.close();
}

// ─────────────────────────────────────────────────────────────────────────────
// Tests
// ─────────────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(_setUp);
  tearDown(_tearDown);

  // ── 1. 20-member group: Greedy Flow under 100ms ───────────────────────────
  group('20-member group — Greedy Flow performance', () {
    const groupId = 'stress-group-20';
    const memberCount = 20;
    const expenseCount = 100;

    test('resolves $expenseCount expenses among $memberCount members in < 100ms',
        () {
      final rng = Random(42);
      final members =
          List.generate(memberCount, (i) => 'stress-user-${i.toString().padLeft(3, '0')}');

      final expenses = <Map<String, dynamic>>[];
      final splits = <SplitModel>[];

      for (var i = 0; i < expenseCount; i++) {
        final eid = 'stress-exp-$i';
        final payer = members[i % memberCount];
        final amount = (rng.nextInt(500) + 10).toDouble();
        final perPerson = (amount / memberCount).toStringAsFixed(2);

        expenses.add(_buildExpense(
          id: eid,
          groupId: groupId,
          payerId: payer,
          amount: amount.toStringAsFixed(2),
        ));

        for (final member in members) {
          splits.add(_buildSplit(
            expenseId: eid,
            userId: member,
            usdOwed: perPerson,
          ));
        }
      }

      final sw = Stopwatch()..start();
      final transactions = SettlementEngine.simplify(
        groupId: groupId,
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(100),
          reason: 'Greedy Flow must resolve $expenseCount expenses /'
              ' $memberCount members in under 100ms '
              '(actual: ${sw.elapsedMilliseconds}ms)');

      expect(transactions.length, lessThanOrEqualTo(memberCount - 1),
          reason: 'Greedy Flow must produce at most N-1 transactions for N members');

      _assertFullySettled(expenses, splits, transactions);
    });
  });

  // ── 2. 500+ transactions stress test ─────────────────────────────────────
  group('500+ transactions across 5 groups', () {
    const groupCount = 5;
    const membersPerGroup = 10;
    const expensesPerGroup = 100; // 5 × 100 = 500 total

    test('500 transactions all resolve correctly with no unsettled balances',
        () {
      final rng = Random(99);
      var totalTransactions = 0;

      for (var g = 0; g < groupCount; g++) {
        final gid = 'bulk-group-$g';
        final members = List.generate(
            membersPerGroup, (i) => 'bulk-user-$g-$i');

        final expenses = <Map<String, dynamic>>[];
        final splits = <SplitModel>[];

        for (var i = 0; i < expensesPerGroup; i++) {
          final eid = 'bulk-exp-$g-$i';
          final payer = members[i % membersPerGroup];
          final amount = (rng.nextInt(200) + 5).toDouble();
          final perPerson = (amount / membersPerGroup).toStringAsFixed(2);

          expenses.add(_buildExpense(
            id: eid,
            groupId: gid,
            payerId: payer,
            amount: amount.toStringAsFixed(2),
          ));

          for (final member in members) {
            splits.add(_buildSplit(
              expenseId: eid,
              userId: member,
              usdOwed: perPerson,
            ));
          }
        }

        final sw = Stopwatch()..start();
        final transactions = SettlementEngine.simplify(
          groupId: gid,
          currency: 'USD',
          expenses: expenses,
          splits: splits,
        );
        sw.stop();

        expect(sw.elapsedMilliseconds, lessThan(100),
            reason: 'Group $g: Greedy Flow exceeded 100ms (${sw.elapsedMilliseconds}ms)');

        _assertFullySettled(expenses, splits, transactions);
        totalTransactions += transactions.length;
      }

      expect(totalTransactions, greaterThan(0),
          reason: 'Should produce settlement transactions for non-zero debts');
    });
  });

  // ── 3. Correctness: zero-sum groups produce no transactions ───────────────
  group('Zero-sum correctness', () {
    test('group where everyone paid exactly their share → 0 transactions', () {
      const gid = 'zero-sum-group';
      const memberCount = 10;
      const members = [
        'u0', 'u1', 'u2', 'u3', 'u4', 'u5', 'u6', 'u7', 'u8', 'u9'
      ];

      // Each member pays exactly 100 for 10 expenses, owes 100 total.
      final expenses = <Map<String, dynamic>>[];
      final splits = <SplitModel>[];

      for (var i = 0; i < memberCount; i++) {
        final eid = 'zero-exp-$i';
        expenses.add(_buildExpense(
          id: eid,
          groupId: gid,
          payerId: members[i],
          amount: (memberCount * 10).toStringAsFixed(2),
        ));
        for (final m in members) {
          splits.add(_buildSplit(
            expenseId: eid,
            userId: m,
            usdOwed: '10.00',
          ));
        }
      }

      final txns = SettlementEngine.simplify(
        groupId: gid,
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );

      expect(txns, isEmpty,
          reason: 'When everyone is exactly even, no settlement transactions '
              'should be emitted');
    });
  });

  // ── 4. Greedy Flow produces ≤ N-1 transactions for N debtors ─────────────
  group('Transaction minimization invariant', () {
    test('N payers, 1 paid-for-all → exactly N-1 transactions', () {
      const gid = 'min-txn-group';
      const memberCount = 20;
      final members =
          List.generate(memberCount, (i) => 'min-user-$i');
      const totalAmount = 200.0;
      const perPerson = 10.0;

      // Only member 0 paid for everything.
      final expense = _buildExpense(
        id: 'min-exp-0',
        groupId: gid,
        payerId: members[0],
        amount: totalAmount.toStringAsFixed(2),
      );
      final splits = members
          .map((m) => _buildSplit(
                expenseId: 'min-exp-0',
                userId: m,
                usdOwed: perPerson.toStringAsFixed(2),
              ))
          .toList();

      final txns = SettlementEngine.simplify(
        groupId: gid,
        currency: 'USD',
        expenses: [expense],
        splits: splits,
      );

      // Payer 0 is creditor (net +190). Everyone else is debtor.
      // Greedy matches all 19 debtors → 19 transactions total.
      expect(txns.length, equals(memberCount - 1));
      expect(txns.every((t) => t.toUserId == members[0]), isTrue,
          reason: 'All payments should flow to the sole payer');
    });
  });

  // ── 5. SQLite write throughput ─────────────────────────────────────────────
  group('SQLite bulk write throughput', () {
    test('batch-insert 500 expense rows in < 2s', () async {
      final sw = Stopwatch()..start();
      await _db.transaction((txn) async {
        for (var i = 0; i < 500; i++) {
          await txn.insert('expenses', {
            'id': 'bulk-write-exp-$i',
            'group_id': 'bulk-write-group',
            'payer_id': 'bulk-write-user-${i % 20}',
            'amount': '${(i + 1) * 1.5}',
            'currency': 'USD',
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      });
      sw.stop();

      final countRows = await _db.rawQuery('SELECT COUNT(*) as c FROM expenses');
      final count = countRows.first['c'] as int;
      expect(count, equals(500));
      expect(sw.elapsedMilliseconds, lessThan(2000),
          reason: 'Batch insert of 500 rows must complete in < 2s '
              '(actual: ${sw.elapsedMilliseconds}ms)');
    });

    test('batch-insert 500 split rows in < 2s', () async {
      await _db.insert('expenses', {
        'id': 'parent-exp',
        'group_id': 'split-bulk-group',
        'payer_id': 'owner',
        'amount': '5000.00',
        'currency': 'USD',
        'created_at': DateTime.now().toIso8601String(),
      });

      final sw = Stopwatch()..start();
      await _db.transaction((txn) async {
        for (var i = 0; i < 500; i++) {
          await txn.insert('splits', {
            'id': 'bulk-split-$i',
            'expense_id': 'parent-exp',
            'user_id': 'bulk-split-user-$i',
            'universal_usd_owed': '10.00',
            'created_at': DateTime.now().toIso8601String(),
          }, conflictAlgorithm: ConflictAlgorithm.replace);
        }
      });
      sw.stop();

      expect(sw.elapsedMilliseconds, lessThan(2000),
          reason: 'Batch insert of 500 split rows must complete in < 2s '
              '(actual: ${sw.elapsedMilliseconds}ms)');
    });
  });
}

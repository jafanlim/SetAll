// Hermetic tests for SettlementEngine.simplify (TASK 3 — net-balance correctness).
//
// Zero I/O. Pure static function. Covers:
//   A↔B mutual offset (the carried-over bug repro)
//   Partial offset, single-payer-multi-debtor, 3-party chain, multi-currency,
//   cents rounding, empty input, anti-vacuous guard.

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:setall/data/models/split_model.dart';
import 'package:setall/domain/services/settlement_engine.dart';

/// Build an expense map matching the contract of SettlementEngine.simplify.
Map<String, dynamic> _expense({
  required String id,
  required String groupId,
  required String payerId,
  required String amount,
  String currency = 'USD',
  String? universalUsdAmount,
}) {
  return {
    'id': id,
    'group_id': groupId,
    'payer_id': payerId,
    'amount': amount,
    'currency': currency,
    'universal_usd_amount': universalUsdAmount,
  };
}

/// Build a SplitModel with universalUsdOwed.
SplitModel _split({
  required String id,
  required String expenseId,
  required String userId,
  required String universalUsdOwed,
}) {
  return SplitModel(
    id: id,
    expenseId: expenseId,
    userId: userId,
    universalUsdOwed: universalUsdOwed,
  );
}

const _g = 'g1';

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // THE BUG REPRO — A↔B mutual offset
  // ──────────────────────────────────────────────────────────────────────────
  group('A↔B mutual offset (the carried-over bug)', () {
    test('A pays 100 (split 50/50), B pays 100 (split 50/50) → 0 txns', () {
      // A pays 100 → A is +100 (payer), A is −50 (debtor own split), B is −50
      // B pays 100 → B is +100 (payer), B is −50 (debtor own split), A is −50
      // Net: A = +100 −50 −50 = 0, B = +100 −50 −50 = 0 → zero transactions.
      final expenses = [
        _expense(id: 'e1', groupId: _g, payerId: 'A', amount: '100.00',
            universalUsdAmount: '100.00'),
        _expense(id: 'e2', groupId: _g, payerId: 'B', amount: '100.00',
            universalUsdAmount: '100.00'),
      ];
      final splits = [
        _split(id: 's1', expenseId: 'e1', userId: 'A', universalUsdOwed: '50.00'),
        _split(id: 's2', expenseId: 'e1', userId: 'B', universalUsdOwed: '50.00'),
        _split(id: 's3', expenseId: 'e2', userId: 'A', universalUsdOwed: '50.00'),
        _split(id: 's4', expenseId: 'e2', userId: 'B', universalUsdOwed: '50.00'),
      ];

      final result = SettlementEngine.simplify(
        groupId: _g,
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );

      // ANTI-VACUOUS: assert isEmpty, not just "no throw".
      expect(result, isEmpty,
          reason: 'A↔B each paid 100 with symmetric splits → net 0 → 0 txns');
    });

    test('A pays 100 (split 70/30), B pays 50 (split 25/25) → one txn', () {
      // A: +100 (payer e1) −70 (own split e1) −25 (split from e2) = +5
      // B:  +50 (payer e2) −30 (split from e1) −25 (own split e2) = −5
      // → B owes A 5.00.
      final expenses = [
        _expense(id: 'e1', groupId: _g, payerId: 'A', amount: '100.00',
            universalUsdAmount: '100.00'),
        _expense(id: 'e2', groupId: _g, payerId: 'B', amount: '50.00',
            universalUsdAmount: '50.00'),
      ];
      final splits = [
        _split(id: 's1', expenseId: 'e1', userId: 'A', universalUsdOwed: '70.00'),
        _split(id: 's2', expenseId: 'e1', userId: 'B', universalUsdOwed: '30.00'),
        _split(id: 's3', expenseId: 'e2', userId: 'A', universalUsdOwed: '25.00'),
        _split(id: 's4', expenseId: 'e2', userId: 'B', universalUsdOwed: '25.00'),
      ];

      final result = SettlementEngine.simplify(
        groupId: _g,
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );

      expect(result, hasLength(1));
      final txn = result.first;
      expect(txn.fromUserId, 'B');
      expect(txn.toUserId, 'A');
      expect(txn.amount, Decimal.parse('5.00'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Partial offset
  // ──────────────────────────────────────────────────────────────────────────
  group('Partial offset', () {
    test('A pays 100 (split 50/50), B pays 40 (split 20/20) → B→A 30', () {
      // A: +100 −50 −20 = +30
      // B: +40  −50 −20 = −30 → B owes A 30.
      final expenses = [
        _expense(id: 'e1', groupId: _g, payerId: 'A', amount: '100.00',
            universalUsdAmount: '100.00'),
        _expense(id: 'e2', groupId: _g, payerId: 'B', amount: '40.00',
            universalUsdAmount: '40.00'),
      ];
      final splits = [
        _split(id: 's1', expenseId: 'e1', userId: 'A', universalUsdOwed: '50.00'),
        _split(id: 's2', expenseId: 'e1', userId: 'B', universalUsdOwed: '50.00'),
        _split(id: 's3', expenseId: 'e2', userId: 'A', universalUsdOwed: '20.00'),
        _split(id: 's4', expenseId: 'e2', userId: 'B', universalUsdOwed: '20.00'),
      ];

      final result = SettlementEngine.simplify(
        groupId: _g,
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );

      expect(result, hasLength(1));
      expect(result.first.fromUserId, 'B');
      expect(result.first.toUserId, 'A');
      expect(result.first.amount, Decimal.parse('30.00'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // One payer, two debtors
  // ──────────────────────────────────────────────────────────────────────────
  group('One payer, two debtors', () {
    test('A pays 90 (split 30/30/30) → two txns: B→A 30, C→A 30', () {
      // A: +90 −30 = +60
      // B: −30
      // C: −30
      // → 2 txns, exact.
      final expenses = [
        _expense(id: 'e1', groupId: _g, payerId: 'A', amount: '90.00',
            universalUsdAmount: '90.00'),
      ];
      final splits = [
        _split(id: 's1', expenseId: 'e1', userId: 'A', universalUsdOwed: '30.00'),
        _split(id: 's2', expenseId: 'e1', userId: 'B', universalUsdOwed: '30.00'),
        _split(id: 's3', expenseId: 'e1', userId: 'C', universalUsdOwed: '30.00'),
      ];

      final result = SettlementEngine.simplify(
        groupId: _g,
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );

      expect(result, hasLength(2));
      final amounts = result.map((t) => t.amount).toSet();
      expect(amounts, contains(Decimal.parse('30.00')));
      final debtors = result.map((t) => t.fromUserId).toSet();
      expect(debtors, {'B', 'C'});
      final creditors = result.map((t) => t.toUserId).toSet();
      expect(creditors, {'A'});
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // 3-party chain nets to minimal set
  // ──────────────────────────────────────────────────────────────────────────
  group('3-party chain', () {
    test('A→B 50, B→C 30, C→A 20 → nets to 2 txns max', () {
      // A pays 50 for A+B (split A25/B25)  → A net +25, B net −25
      // B pays 30 for B+C (split B15/C15)  → B net +15, C net −15
      // C pays 20 for C+A (split C10/A10)  → C net +10, A net −10
      // Net: A = +25−10 = +15, B = −25+15 = −10, C = −15+10 = −5
      // → B owes A 10, C owes A 5 → 2 txns.
      final expenses = [
        _expense(id: 'e1', groupId: _g, payerId: 'A', amount: '50.00',
            universalUsdAmount: '50.00'),
        _expense(id: 'e2', groupId: _g, payerId: 'B', amount: '30.00',
            universalUsdAmount: '30.00'),
        _expense(id: 'e3', groupId: _g, payerId: 'C', amount: '20.00',
            universalUsdAmount: '20.00'),
      ];
      final splits = [
        _split(id: 's1', expenseId: 'e1', userId: 'A', universalUsdOwed: '25.00'),
        _split(id: 's2', expenseId: 'e1', userId: 'B', universalUsdOwed: '25.00'),
        _split(id: 's3', expenseId: 'e2', userId: 'B', universalUsdOwed: '15.00'),
        _split(id: 's4', expenseId: 'e2', userId: 'C', universalUsdOwed: '15.00'),
        _split(id: 's5', expenseId: 'e3', userId: 'C', universalUsdOwed: '10.00'),
        _split(id: 's6', expenseId: 'e3', userId: 'A', universalUsdOwed: '10.00'),
      ];

      final result = SettlementEngine.simplify(
        groupId: _g,
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );

      // 3 debtors/creditors → at most 2 transactions (N−1).
      expect(result.length, lessThanOrEqualTo(2));
      // B owes A 10, C owes A 5.
      final totalSettled = result.fold<Decimal>(
          Decimal.zero, (sum, t) => sum + t.amount);
      expect(totalSettled, Decimal.parse('15.00'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Multi-currency via universal_usd_amount / universalUsdOwed
  // ──────────────────────────────────────────────────────────────────────────
  group('Multi-currency USD netting', () {
    test('EUR expense + GBP expense → net in USD via universal fields', () {
      // A pays 80 EUR (=96 USD universal), split A48/B48 USD.
      // B pays 50 GBP (=63.50 USD universal), split A31.75/B31.75 USD.
      // Net: A = +96 −48 −31.75 = +16.25
      //       B = +63.50 −48 −31.75 = −16.25
      // → B owes A 16.25.
      final expenses = [
        _expense(id: 'e1', groupId: _g, payerId: 'A', amount: '80.00',
            currency: 'EUR', universalUsdAmount: '96.00'),
        _expense(id: 'e2', groupId: _g, payerId: 'B', amount: '50.00',
            currency: 'GBP', universalUsdAmount: '63.50'),
      ];
      final splits = [
        _split(id: 's1', expenseId: 'e1', userId: 'A', universalUsdOwed: '48.00'),
        _split(id: 's2', expenseId: 'e1', userId: 'B', universalUsdOwed: '48.00'),
        _split(id: 's3', expenseId: 'e2', userId: 'A', universalUsdOwed: '31.75'),
        _split(id: 's4', expenseId: 'e2', userId: 'B', universalUsdOwed: '31.75'),
      ];

      final result = SettlementEngine.simplify(
        groupId: _g,
        currency: 'USD', // display label
        expenses: expenses,
        splits: splits,
      );

      expect(result, hasLength(1));
      expect(result.first.fromUserId, 'B');
      expect(result.first.toUserId, 'A');
      expect(result.first.amount, Decimal.parse('16.25'));
      expect(result.first.currency, 'USD');
    });

    test('universal_usd_amount absent → falls back to amount (same-currency)', () {
      // No universal fields → parse `amount` directly as Decimal.
      // A pays 100 USD (split 60/40) → A: +60, B: −40.
      final expenses = [
        _expense(id: 'e1', groupId: _g, payerId: 'A', amount: '100.00',
            currency: 'USD', universalUsdAmount: null),
      ];
      final splits = [
        _split(id: 's1', expenseId: 'e1', userId: 'A', universalUsdOwed: '60.00'),
        _split(id: 's2', expenseId: 'e1', userId: 'B', universalUsdOwed: '40.00'),
      ];

      final result = SettlementEngine.simplify(
        groupId: _g,
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );

      expect(result, hasLength(1));
      expect(result.first.fromUserId, 'B');
      expect(result.first.toUserId, 'A');
      expect(result.first.amount, Decimal.parse('40.00'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Cents rounding
  // ──────────────────────────────────────────────────────────────────────────
  group('Cents rounding', () {
    test('amounts round to 2 decimal places', () {
      // A pays 10.005 (split 5.0025/5.0025). With .round(scale: 2),
      // each amount should round to 2 decimal places.
      // A: +10.005 −5.0025 −5.0025 = −0.00 → rounds cleanly to 0.
      // But let's use a case that produces a visible rounding:
      // A pays 10.00 (split A3.333/B3.333/C3.334) = 10.00 total
      // A: +10 −3.333 = +6.667
      // B: −3.333, C: −3.334
      // → greedy match: B→A 3.33, C→A 3.33 (rounded).
      // Remaining: A +0.007 (rounded to 0, so no 3rd txn for sub-cent).
      final expenses = [
        _expense(id: 'e1', groupId: _g, payerId: 'A', amount: '10.00',
            universalUsdAmount: '10.00'),
      ];
      final splits = [
        _split(id: 's1', expenseId: 'e1', userId: 'A', universalUsdOwed: '3.333'),
        _split(id: 's2', expenseId: 'e1', userId: 'B', universalUsdOwed: '3.333'),
        _split(id: 's3', expenseId: 'e1', userId: 'C', universalUsdOwed: '3.334'),
      ];

      final result = SettlementEngine.simplify(
        groupId: _g,
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );

      for (final txn in result) {
        // Every amount must have at most 2 decimal places.
        expect(txn.amount.toStringAsFixed(2), txn.amount.toString());
      }

      // Sub-cent remainders are dropped (not accumulated into an extra txn).
      final total = result.fold<Decimal>(
          Decimal.zero, (sum, t) => sum + t.amount);
      // 10.00 − 3.333 − 3.333 − 3.334 = 0.000 inside the engine, but we
      // settled 3.33 + 3.33 = 6.66 — the 0.007 net of A is < 0.01 so no 3rd txn.
      expect(total, Decimal.parse('6.66'));
    });

    test('sub-cent net balances do not produce transactions', () {
      // A pays 0.01 (split A0.006/B0.004).
      // A: +0.01 −0.006 = +0.004, B: −0.004.
      // payment = 0.004, round(scale: 2) = 0.00 (Decimal HALF_UP: 004 < 005) → skipped.
      final expenses = [
        _expense(id: 'e1', groupId: _g, payerId: 'A', amount: '0.01',
            universalUsdAmount: '0.01'),
      ];
      final splits = [
        _split(id: 's1', expenseId: 'e1', userId: 'A', universalUsdOwed: '0.006'),
        _split(id: 's2', expenseId: 'e1', userId: 'B', universalUsdOwed: '0.004'),
      ];

      final result = SettlementEngine.simplify(
        groupId: _g,
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );

      expect(result, isEmpty,
          reason: 'sub-cent payment rounds to 0.00 → no transaction emitted');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Empty / edge
  // ──────────────────────────────────────────────────────────────────────────
  group('Empty / edge', () {
    test('no expenses → no transactions', () {
      final result = SettlementEngine.simplify(
        groupId: _g,
        currency: 'USD',
        expenses: const [],
        splits: const [],
      );
      expect(result, isEmpty);
    });

    test('no splits → no transactions (payer owes themselves nothing)', () {
      final expenses = [
        _expense(id: 'e1', groupId: _g, payerId: 'A', amount: '100.00',
            universalUsdAmount: '100.00'),
      ];
      // A pays 100 with no splits → net +100, no debtors → no txns.
      final result = SettlementEngine.simplify(
        groupId: _g,
        currency: 'USD',
        expenses: expenses,
        splits: const [],
      );
      expect(result, isEmpty);
    });

    test('expenses from a different group are ignored', () {
      final expenses = [
        _expense(id: 'e1', groupId: 'other-g', payerId: 'A', amount: '100.00',
            universalUsdAmount: '100.00'),
      ];
      final splits = [
        _split(id: 's1', expenseId: 'e1', userId: 'B', universalUsdOwed: '100.00'),
      ];

      final result = SettlementEngine.simplify(
        groupId: _g,
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );
      expect(result, isEmpty,
          reason: 'expenses from other groups are filtered out');
    });

    test('splits for expenses not in group are ignored', () {
      final expenses = [
        _expense(id: 'e1', groupId: _g, payerId: 'A', amount: '100.00',
            universalUsdAmount: '100.00'),
      ];
      // s1 references e2 (not in the group's expenses) → ignored.
      final splits = [
        _split(id: 's1', expenseId: 'e2', userId: 'B', universalUsdOwed: '100.00'),
      ];

      final result = SettlementEngine.simplify(
        groupId: _g,
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );
      // A paid 100, split references a non-existent expense → no debtor → no txn.
      expect(result, isEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // Anti-vacuous guard
  // ──────────────────────────────────────────────────────────────────────────
  group('Anti-vacuous guard', () {
    test('mutual debt with non-zero initial → would return txns if not netted', () {
      // This test confirms the engine actually nets — if it broke and returned
      // raw payer/debtor pairs without netting, this would show 2 txns.
      // A pays 50 (split A25/B25) → raw: B owes A 25
      // B pays 50 (split A25/B25) → raw: A owes B 25
      // Without netting: 2 txns. With netting: 0 txns.
      final expenses = [
        _expense(id: 'e1', groupId: _g, payerId: 'A', amount: '50.00',
            universalUsdAmount: '50.00'),
        _expense(id: 'e2', groupId: _g, payerId: 'B', amount: '50.00',
            universalUsdAmount: '50.00'),
      ];
      final splits = [
        _split(id: 's1', expenseId: 'e1', userId: 'A', universalUsdOwed: '25.00'),
        _split(id: 's2', expenseId: 'e1', userId: 'B', universalUsdOwed: '25.00'),
        _split(id: 's3', expenseId: 'e2', userId: 'A', universalUsdOwed: '25.00'),
        _split(id: 's4', expenseId: 'e2', userId: 'B', universalUsdOwed: '25.00'),
      ];

      final result = SettlementEngine.simplify(
        groupId: _g,
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );

      // If the engine stopped netting, this would be non-empty.
      // The raw per-expense view would produce 1 txn per expense (B→A 25 and A→B 25).
      expect(result, isEmpty,
          reason: 'ANTI-VACUOUS: without netting, raw expense-by-expense '
              'would return 2 txns (B→A 25 + A→B 25). Empty confirms netting works.');
    });
  });
}

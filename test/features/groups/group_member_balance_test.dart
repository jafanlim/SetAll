import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setall/domain/services/settlement_engine.dart';
import 'package:setall/features/groups/presentation/screens/group_member_balance_helper.dart';

void main() {
  // ── Helper: create a SettlementTransaction ────────────────────────────
  SettlementTransaction makeTx({
    required String from,
    required String to,
    required String amount,
    String currency = 'USD',
  }) {
    return SettlementTransaction(
      fromUserId: from,
      toUserId: to,
      amount: Decimal.parse(amount),
      currency: currency,
    );
  }

  group('computeMemberNetPosition', () {
    // ── 3.1 Even split: A pays 30, 3-way even ──────────────────────────
    test('even 3-way split: A isOwed 20, B/C owe 10 each', () {
      // A paid 30, split evenly → A isOwed 20, B owes 10, C owes 10.
      // Simplified debts: B → A 10, C → A 10.
      final debts = [
        makeTx(from: 'B', to: 'A', amount: '10.00'),
        makeTx(from: 'C', to: 'A', amount: '10.00'),
      ];

      final a = computeMemberNetPosition(memberId: 'A', debts: debts);
      expect(a.position, NetPosition.isOwed);
      expect(a.displayAmount, Decimal.parse('20.00'));

      final b = computeMemberNetPosition(memberId: 'B', debts: debts);
      expect(b.position, NetPosition.owes);
      expect(b.displayAmount, Decimal.parse('10.00'));

      final c = computeMemberNetPosition(memberId: 'C', debts: debts);
      expect(c.position, NetPosition.owes);
      expect(c.displayAmount, Decimal.parse('10.00'));
    });

    // ── 3.1 Third-party debt (not involving current user) ───────────────
    test('third-party debt: B owes C, A unaffected', () {
      // B owes C 15. A has no involvement.
      final debts = [
        makeTx(from: 'B', to: 'C', amount: '15.00'),
      ];

      final a = computeMemberNetPosition(memberId: 'A', debts: debts);
      expect(a.position, NetPosition.settled);
      expect(a.displayAmount, Decimal.zero);

      final b = computeMemberNetPosition(memberId: 'B', debts: debts);
      expect(b.position, NetPosition.owes);
      expect(b.displayAmount, Decimal.parse('15.00'));

      final c = computeMemberNetPosition(memberId: 'C', debts: debts);
      expect(c.position, NetPosition.isOwed);
      expect(c.displayAmount, Decimal.parse('15.00'));
    });

    // ── 3.1 Fully settled group ─────────────────────────────────────────
    test('fully settled group: all members settled', () {
      final result = computeMemberNetPosition(
        memberId: 'anyone',
        debts: <SettlementTransaction>[],
      );
      expect(result.position, NetPosition.settled);
      expect(result.displayAmount, Decimal.zero);
    });

    test('member with balanced debts is settled', () {
      // A owes B 10, C owes A 10 → A's net is 0.
      final debts = [
        makeTx(from: 'A', to: 'B', amount: '10.00'),
        makeTx(from: 'C', to: 'A', amount: '10.00'),
      ];

      final a = computeMemberNetPosition(memberId: 'A', debts: debts);
      expect(a.position, NetPosition.settled);
      expect(a.displayAmount, Decimal.zero);
    });

    // ── 3.2 Sub-cent net → settled up (PR #40 rounding rule) ────────────
    test('sub-cent positive net rounds to settled', () {
      final debts = [
        makeTx(from: 'B', to: 'A', amount: '0.004'),
      ];

      final a = computeMemberNetPosition(memberId: 'A', debts: debts);
      expect(a.position, NetPosition.settled,
          reason: '0.004 rounds to 0.00 → settled, never "is owed 0.00"');
      expect(a.displayAmount, Decimal.zero);
    });

    test('sub-cent negative net rounds to settled', () {
      final debts = [
        makeTx(from: 'A', to: 'B', amount: '0.004'),
      ];

      final a = computeMemberNetPosition(memberId: 'A', debts: debts);
      expect(a.position, NetPosition.settled,
          reason: '-0.004 rounds to 0.00 → settled, never "owes 0.00"');
      expect(a.displayAmount, Decimal.zero);
    });

    test('exactly one cent is NOT settled', () {
      final debts = [
        makeTx(from: 'B', to: 'A', amount: '0.01'),
      ];

      final a = computeMemberNetPosition(memberId: 'A', debts: debts);
      expect(a.position, NetPosition.isOwed);
      expect(a.displayAmount, Decimal.parse('0.01'));
    });

    test('exactly -1 cent is NOT settled', () {
      final debts = [
        makeTx(from: 'A', to: 'B', amount: '0.01'),
      ];

      final a = computeMemberNetPosition(memberId: 'A', debts: debts);
      expect(a.position, NetPosition.owes);
      expect(a.displayAmount, Decimal.parse('0.01'));
    });

    test('0.009 rounds to 0.01 → not settled', () {
      final debts = [
        makeTx(from: 'B', to: 'A', amount: '0.009'),
      ];

      final a = computeMemberNetPosition(memberId: 'A', debts: debts);
      // 0.009 rounds to 0.01 at scale 2
      expect(a.position, NetPosition.isOwed);
      expect(a.displayAmount, Decimal.parse('0.01'));
    });

    // ── Currency independence ───────────────────────────────────────────
    test('uses amount from debts regardless of currency label', () {
      // Same amounts, different currency labels — net position is the same.
      final debts = [
        makeTx(from: 'B', to: 'A', amount: '50.00', currency: 'GEL'),
        makeTx(from: 'A', to: 'C', amount: '20.00', currency: 'GEL'),
      ];

      final a = computeMemberNetPosition(memberId: 'A', debts: debts);
      expect(a.position, NetPosition.isOwed);
      expect(a.displayAmount, Decimal.parse('30.00')); // 50 - 20 = 30
    });

    // ── Edge cases ──────────────────────────────────────────────────────
    test('single member with only outgoing debts', () {
      final debts = [
        makeTx(from: 'A', to: 'B', amount: '100.00'),
        makeTx(from: 'A', to: 'C', amount: '50.00'),
      ];

      final a = computeMemberNetPosition(memberId: 'A', debts: debts);
      expect(a.position, NetPosition.owes);
      expect(a.displayAmount, Decimal.parse('150.00'));
    });

    test('large amounts with precise Decimal math', () {
      final debts = [
        makeTx(from: 'B', to: 'A', amount: '999999.99'),
        makeTx(from: 'C', to: 'A', amount: '0.01'),
      ];

      final a = computeMemberNetPosition(memberId: 'A', debts: debts);
      expect(a.position, NetPosition.isOwed);
      expect(a.displayAmount, Decimal.parse('1000000.00'));
    });
  });
}

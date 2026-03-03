import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setall/core/utils/debt_simplification_engine.dart';

void main() {
  group('DebtSimplificationEngine regression guard', () {
    test('simple 3-person split produces minimal transactions', () {
      // Alice pays 30, Bob owes 10, Carol owes 10, Alice owes 10 of her own expense.
      final expenses = [
        {
          'id': 'e1',
          'group_id': 'g1',
          'payer_id': 'alice',
          'amount': '30.00',
          'currency': 'USD',
          'base_amount_at_entry': null,
        },
      ];
      final splits = [
        {'expense_id': 'e1', 'user_id': 'alice', 'amount_owed': '10.00'},
        {'expense_id': 'e1', 'user_id': 'bob', 'amount_owed': '10.00'},
        {'expense_id': 'e1', 'user_id': 'carol', 'amount_owed': '10.00'},
      ];

      final result = DebtSimplificationEngine.simplify(
        groupId: 'g1',
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );

      expect(result.length, 2);
      final total = result.fold(Decimal.zero, (sum, d) => sum + d.amount);
      expect(total, Decimal.parse('20.00'));
    });

    test('settled group returns no debts', () {
      final expenses = [
        {
          'id': 'e1',
          'group_id': 'g1',
          'payer_id': 'alice',
          'amount': '20.00',
          'currency': 'USD',
          'base_amount_at_entry': null,
        },
        {
          'id': 'e2',
          'group_id': 'g1',
          'payer_id': 'bob',
          'amount': '20.00',
          'currency': 'USD',
          'base_amount_at_entry': null,
        },
      ];
      final splits = [
        {'expense_id': 'e1', 'user_id': 'alice', 'amount_owed': '10.00'},
        {'expense_id': 'e1', 'user_id': 'bob', 'amount_owed': '10.00'},
        {'expense_id': 'e2', 'user_id': 'alice', 'amount_owed': '10.00'},
        {'expense_id': 'e2', 'user_id': 'bob', 'amount_owed': '10.00'},
      ];

      final result = DebtSimplificationEngine.simplify(
        groupId: 'g1',
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );

      expect(result, isEmpty);
    });

    test('base_amount_at_entry overrides raw amount for multi-currency', () {
      // Expense in GBP, base (USD) value frozen at entry.
      final expenses = [
        {
          'id': 'e1',
          'group_id': 'g1',
          'payer_id': 'alice',
          'amount': '10.00',
          'currency': 'GBP',
          'base_amount_at_entry': '12.50',
        },
      ];
      final splits = [
        {'expense_id': 'e1', 'user_id': 'alice', 'amount_owed': '5.00'},
        {'expense_id': 'e1', 'user_id': 'bob', 'amount_owed': '5.00'},
      ];

      final result = DebtSimplificationEngine.simplify(
        groupId: 'g1',
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );

      expect(result.length, 1);
      expect(result.first.fromUserId, 'bob');
      expect(result.first.toUserId, 'alice');
      // bob owes half of base 12.50 = 6.25
      expect(result.first.amount, Decimal.parse('6.25'));
    });

    test('group isolation: debts from other groups are ignored', () {
      final expenses = [
        {
          'id': 'e1',
          'group_id': 'g1',
          'payer_id': 'alice',
          'amount': '100.00',
          'currency': 'USD',
          'base_amount_at_entry': null,
        },
        {
          'id': 'e2',
          'group_id': 'g2',
          'payer_id': 'alice',
          'amount': '200.00',
          'currency': 'USD',
          'base_amount_at_entry': null,
        },
      ];
      final splits = [
        {'expense_id': 'e1', 'user_id': 'alice', 'amount_owed': '50.00'},
        {'expense_id': 'e1', 'user_id': 'bob', 'amount_owed': '50.00'},
        {'expense_id': 'e2', 'user_id': 'alice', 'amount_owed': '100.00'},
        {'expense_id': 'e2', 'user_id': 'carol', 'amount_owed': '100.00'},
      ];

      final g1Result = DebtSimplificationEngine.simplify(
        groupId: 'g1',
        currency: 'USD',
        expenses: expenses,
        splits: splits,
      );

      expect(g1Result.length, 1);
      expect(g1Result.first.fromUserId, 'bob');
      expect(g1Result.first.amount, Decimal.parse('50.00'));
    });
  });
}

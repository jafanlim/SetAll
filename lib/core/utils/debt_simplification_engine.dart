import 'package:decimal/decimal.dart';

/// One suggested payment: from [fromUserId] to [toUserId] amount [amount].
/// Privacy: only within same group_id.
class SimplifiedDebt {
  const SimplifiedDebt({
    required this.fromUserId,
    required this.toUserId,
    required this.amount,
    required this.currency,
  });

  final String fromUserId;
  final String toUserId;
  final Decimal amount;
  final String currency;
}

/// Group-scoped debt simplification. Settles debts strictly within a group_id.
/// Uses greedy flow to minimize the number of transactions. All math in Decimal.
class DebtSimplificationEngine {
  DebtSimplificationEngine._();

  /// [expenses]: list of { id, group_id, payer_id, amount (string), currency }
  /// [splits]: list of { expense_id, user_id, amount_owed (string) }
  /// Returns list of simplified debts for that group only.
  static List<SimplifiedDebt> simplify({
    required String groupId,
    required String currency,
    required List<Map<String, dynamic>> expenses,
    required List<Map<String, dynamic>> splits,
  }) {
    final groupExpenses = expenses.where((e) => e['group_id'] == groupId).toList();
    final expenseIds = groupExpenses.map((e) => e['id'] as String).toSet();
    final groupSplits = splits.where((s) => expenseIds.contains(s['expense_id'])).toList();

    // Net balance per user: total lent (paid) - total owed (from splits). Decimal only.
    final netBalances = <String, Decimal>{};

    for (final e in groupExpenses) {
      final payerId = e['payer_id'] as String;
      final amount = _parseDecimal(e['amount']);
      netBalances[payerId] = (netBalances[payerId] ?? Decimal.zero) + amount;
    }

    for (final s in groupSplits) {
      final userId = s['user_id'] as String;
      final amount = _parseDecimal(s['amount_owed']);
      netBalances[userId] = (netBalances[userId] ?? Decimal.zero) - amount;
    }

    // Greedy: creditors (positive balance) get paid by debtors (negative balance).
    // Sort so we process largest creditors and largest debtors first to minimize transactions.
    final creditors = <MapEntry<String, Decimal>>[];
    final debtors = <MapEntry<String, Decimal>>[];
    for (final e in netBalances.entries) {
      if (e.value > Decimal.zero) {
        creditors.add(e);
      } else if (e.value < Decimal.zero) {
        debtors.add(MapEntry(e.key, -e.value));
      }
    }

    creditors.sort((a, b) => b.value.compareTo(a.value));
    debtors.sort((a, b) => b.value.compareTo(a.value));

    final result = <SimplifiedDebt>[];
    var i = 0;
    var j = 0;

    while (i < creditors.length && j < debtors.length) {
      final cred = creditors[i];
      final deb = debtors[j];
      final amount = cred.value < deb.value ? cred.value : deb.value;
      if (amount <= Decimal.zero) break;

      result.add(SimplifiedDebt(
        fromUserId: deb.key,
        toUserId: cred.key,
        amount: amount,
        currency: currency,
      ));

      if (cred.value == amount) {
        i++;
      } else {
        creditors[i] = MapEntry(cred.key, cred.value - amount);
      }
      if (deb.value == amount) {
        j++;
      } else {
        debtors[j] = MapEntry(deb.key, deb.value - amount);
      }
    }

    return result;
  }

  static Decimal _parseDecimal(dynamic v) {
    if (v == null) return Decimal.zero;
    if (v is Decimal) return v;
    return Decimal.tryParse(v.toString()) ?? Decimal.zero;
  }
}

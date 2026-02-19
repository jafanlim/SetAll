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
///
/// Multi-currency correctness: when [base_amount_at_entry] is available on an
/// expense (schema v4+), all amounts are normalised to that frozen base value
/// before computing net balances. This eliminates currency-mixing errors in
/// groups with expenses in multiple currencies (e.g. GBP + GEL + EUR).
///
/// Legacy expenses (no base_amount_at_entry) fall back to raw [amount] and
/// are treated as if they are in [currency] (same single-currency behaviour
/// as before, correct for homogeneous groups).
class DebtSimplificationEngine {
  DebtSimplificationEngine._();

  /// [expenses]: list of expense rows with at minimum:
  ///   { id, group_id, payer_id, amount (string), currency (string),
  ///     base_amount_at_entry (string|null) }
  /// [splits]: list of split rows with at minimum:
  ///   { expense_id, user_id, amount_owed (string) }
  /// [currency]: the display currency for the returned [SimplifiedDebt] objects
  ///   (typically the user's base currency or the group's primary currency).
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

    // Build lookup: expenseId → expense row
    final expenseById = <String, Map<String, dynamic>>{
      for (final e in groupExpenses) e['id'] as String: e,
    };

    // Net balance per user in base currency: total lent (paid) – total owed (from splits).
    // We normalise to base currency via base_amount_at_entry when available.
    final netBalances = <String, Decimal>{};

    for (final e in groupExpenses) {
      final payerId = e['payer_id'] as String;
      // Use frozen base amount when available (eliminates multi-currency mixing).
      final baseStr = e['base_amount_at_entry']?.toString();
      final baseTotal = baseStr != null ? Decimal.tryParse(baseStr) : null;
      final amount = baseTotal ?? _parseDecimal(e['amount']);
      netBalances[payerId] = (netBalances[payerId] ?? Decimal.zero) + amount;
    }

    for (final s in groupSplits) {
      final userId = s['user_id'] as String;
      final rawOwed = _parseDecimal(s['amount_owed']);

      // Compute the proportional base-currency share for this split.
      final ex = expenseById[s['expense_id'] as String];
      Decimal baseOwed = rawOwed;
      if (ex != null) {
        final baseStr = ex['base_amount_at_entry']?.toString();
        final baseTotal = baseStr != null ? Decimal.tryParse(baseStr) : null;
        if (baseTotal != null && baseTotal > Decimal.zero) {
          final expenseRaw = _parseDecimal(ex['amount']);
          if (expenseRaw > Decimal.zero) {
            // split_base = (split_amount_owed / expense_amount) * base_total
            baseOwed = ((rawOwed * baseTotal) / expenseRaw)
                .toDecimal(scaleOnInfinitePrecision: 10)
                .round(scale: 4);
          } else {
            baseOwed = baseTotal;
          }
        }
      }

      netBalances[userId] = (netBalances[userId] ?? Decimal.zero) - baseOwed;
    }

    // Greedy: creditors (positive balance) get paid by debtors (negative balance).
    // Sort largest first to minimise number of transactions.
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
        amount: amount.round(scale: 2),
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

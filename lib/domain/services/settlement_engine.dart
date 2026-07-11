import 'package:decimal/decimal.dart';
import '../../data/models/split_model.dart';

/// One suggested payment in a group settlement:
/// [fromUserId] should pay [amount] to [toUserId].
/// Privacy: only within a single group_id scope.
class SettlementTransaction {
  const SettlementTransaction({
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

/// Group-scoped debt simplification using the Greedy Flow algorithm.
///
/// Settles debts strictly within a group_id by minimizing the number of
/// transactions. All math is performed with [Decimal] for exact precision.
///
/// Algorithm:
/// 1. Compute net balances for all members (total paid as payer − total owed).
/// 2. Separate members into creditors (positive net) and debtors (negative net).
/// 3. Iteratively match the largest debtor with the largest creditor.
/// 4. Continue until all debts are resolved.
///
/// Uses [SplitModel.universalUsdOwed] (schema v8+) for normalized USD values,
/// enabling accurate multi-currency handling without runtime conversion.
class SettlementEngine {
  SettlementEngine._();

  /// Simplifies debts for [groupId] using the Greedy Flow algorithm.
  ///
  /// [groupId]: scope filter — only expenses/splits for this group are used.
  /// [currency]: the display currency label for returned [SettlementTransaction]s.
  /// [usdToBaseRate]: rate to convert USD net balances to [currency] (e.g.
  ///   `getRate('USD', 'GEL')`).  Default [Decimal.one] preserves backward
  ///   compatibility (USD base — no conversion).
  /// [expenses]: raw expense maps, each containing at minimum:
  ///   { id, group_id, payer_id, amount (string), currency (string),
  ///     universal_usd_amount (string|null) }
  /// [splits]: [SplitModel] list with [universalUsdOwed] populated.
  ///
  /// Returns a minimal list of [SettlementTransaction]s that fully settles the group.
  static List<SettlementTransaction> simplify({
    required String groupId,
    required String currency,
    Decimal? usdToBaseRate,
    required List<Map<String, dynamic>> expenses,
    required List<SplitModel> splits,
  }) {
    final groupExpenses =
        expenses.where((e) => e['group_id'] == groupId).toList();
    final expenseIds =
        groupExpenses.map((e) => e['id'] as String).toSet();
    final groupSplits =
        splits.where((s) => expenseIds.contains(s.expenseId)).toList();

    // Step 1: Compute net balances.
    // Net balance = total paid (as payer) − total owed (from splits).
    final netBalances = <String, Decimal>{};

    for (final expense in groupExpenses) {
      final payerId = expense['payer_id'] as String;
      final universalStr = expense['universal_usd_amount']?.toString();
      final universalAmount = universalStr != null
          ? Decimal.tryParse(universalStr)
          : null;
      // Fallback: only use raw `amount` when the expense is already in USD;
      // otherwise we would mix group-currency payer vs USD splits (mixed-currency net).
      final amount = universalAmount ??
          (expense['currency'] == 'USD'
              ? _parseDecimal(expense['amount'])
              : Decimal.zero);
      netBalances[payerId] =
          (netBalances[payerId] ?? Decimal.zero) + amount;
    }

    for (final split in groupSplits) {
      final owedAmount =
          Decimal.tryParse(split.universalUsdOwed) ?? Decimal.zero;
      netBalances[split.userId] =
          (netBalances[split.userId] ?? Decimal.zero) - owedAmount;
    }

    // Convert each member's USD net to the display (base) currency before
    // splitting into creditors/debtors.  This mirrors balance_service's
    // convert-then-net so the two reconcile.
    final rate = usdToBaseRate ?? Decimal.one;
    if (rate != Decimal.one) {
      for (final entry in netBalances.entries.toList()) {
        netBalances[entry.key] =
            (entry.value * rate).round(scale: 2);
      }
    }

    // Step 2: Separate into creditors (positive) and debtors (negative).
    final creditors = <MapEntry<String, Decimal>>[];
    final debtors = <MapEntry<String, Decimal>>[];

    for (final entry in netBalances.entries) {
      if (entry.value > Decimal.zero) {
        creditors.add(entry);
      } else if (entry.value < Decimal.zero) {
        debtors.add(MapEntry(entry.key, -entry.value));
      }
    }

    // Step 3: Sort largest first to minimize transaction count.
    creditors.sort((a, b) => b.value.compareTo(a.value));
    debtors.sort((a, b) => b.value.compareTo(a.value));

    // Step 4: Greedy Flow — match largest debtor with largest creditor.
    final transactions = <SettlementTransaction>[];
    var ci = 0;
    var di = 0;

    while (ci < creditors.length && di < debtors.length) {
      final creditor = creditors[ci];
      final debtor = debtors[di];

      final rawPayment = creditor.value < debtor.value
          ? creditor.value
          : debtor.value;

      final payment = rawPayment.round(scale: 2);
      if (payment <= Decimal.zero) {
        // Sub-cent remainder; cannot settle. Skip the smaller balance
        // to avoid an infinite loop.
        if (creditor.value < debtor.value) {
          ci++;
        } else {
          di++;
        }
        continue;
      }

      transactions.add(SettlementTransaction(
        fromUserId: debtor.key,
        toUserId: creditor.key,
        amount: payment,
        currency: currency,
      ));

      if (creditor.value == payment) {
        ci++;
      } else {
        creditors[ci] =
            MapEntry(creditor.key, creditor.value - payment);
      }

      if (debtor.value == payment) {
        di++;
      } else {
        debtors[di] = MapEntry(debtor.key, debtor.value - payment);
      }
    }

    return transactions;
  }

  static Decimal _parseDecimal(dynamic v) {
    if (v == null) return Decimal.zero;
    if (v is Decimal) return v;
    return Decimal.tryParse(v.toString()) ?? Decimal.zero;
  }
}

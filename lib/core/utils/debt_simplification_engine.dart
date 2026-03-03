import 'package:decimal/decimal.dart';
import '../../data/models/split_model.dart';

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

/// Group-scoped debt simplification using the Greedy Flow algorithm.
/// Settles debts strictly within a group_id by minimizing the number of transactions.
/// All math performed in Decimal for precision.
///
/// The algorithm works by:
/// 1. Computing net balances for all members (paid - owed)
/// 2. Separating members into "Payers" (negative balance) and "Receivers" (positive balance)
/// 3. Iteratively matching the largest payer with the largest receiver
/// 4. Continuing until all debts are settled
///
/// Uses universal_usd_owed fields from SplitModel (Schema v4+) for accurate
/// multi-currency handling by working with normalized USD/base values.
class DebtSimplificationEngine {
  DebtSimplificationEngine._();

  /// Simplifies debts within a group using the Greedy Flow algorithm.
  ///
  /// [groupId]: The group ID to process
  /// [currency]: The display currency for returned SimplifiedDebt objects
  /// [expenses]: List of expense maps with at minimum:
  ///   { id, group_id, payer_id, amount (string), currency (string),
  ///     base_amount_at_entry (string|null) }
  /// [splits]: List of SplitModel objects with universal_usd_owed fields
  /// 
  /// Returns list of optimized SimplifiedDebt objects for the group.
  static List<SimplifiedDebt> simplify({
    required String groupId,
    required String currency,
    required List<Map<String, dynamic>> expenses,
    required List<SplitModel> splits,
  }) {
    // Filter expenses and splits for the specific group
    final groupExpenses = expenses.where((e) => e['group_id'] == groupId).toList();
    final expenseIds = groupExpenses.map((e) => e['id'] as String).toSet();
    final groupSplits = splits.where((s) => expenseIds.contains(s.expenseId)).toList();

    // Step 1: Calculate net balances for all group members
    // Net balance = total paid (as payer) - total owed (from splits)
    final netBalances = <String, Decimal>{};

    // Add amounts paid by each payer (positive contribution to net balance)
    for (final expense in groupExpenses) {
      final payerId = expense['payer_id'] as String;
      
      // Use frozen base amount when available for multi-currency accuracy
      final baseStr = expense['base_amount_at_entry']?.toString();
      final baseAmount = baseStr != null ? Decimal.tryParse(baseStr) : null;
      final amount = baseAmount ?? _parseDecimal(expense['amount']);
      
      netBalances[payerId] = (netBalances[payerId] ?? Decimal.zero) + amount;
    }

    // Subtract amounts owed by each user (negative contribution to net balance)
    // Use universal_usd_owed from SplitModel for normalized USD/base values
    for (final split in groupSplits) {
      final userId = split.userId;
      final owedAmount = Decimal.tryParse(split.universalUsdOwed) ?? Decimal.zero;
      
      netBalances[userId] = (netBalances[userId] ?? Decimal.zero) - owedAmount;
    }

    // Step 2: Separate members into Payers (negative balance) and Receivers (positive balance)
    final receivers = <MapEntry<String, Decimal>>[];  // Positive balance - should receive money
    final payers = <MapEntry<String, Decimal>>[];     // Negative balance - should pay money
    
    for (final entry in netBalances.entries) {
      if (entry.value > Decimal.zero) {
        receivers.add(entry);  // This person is owed money
      } else if (entry.value < Decimal.zero) {
        payers.add(MapEntry(entry.key, -entry.value));  // Convert to positive amount owed
      }
      // Zero balance individuals are ignored (they're settled)
    }

    // Step 3: Sort by amount (largest first) to minimize number of transactions
    receivers.sort((a, b) => b.value.compareTo(a.value));  // Largest receiver first
    payers.sort((a, b) => b.value.compareTo(a.value));    // Largest payer first

    // Step 4: Greedy Flow - iteratively match largest payer with largest receiver
    final simplifiedDebts = <SimplifiedDebt>[];
    var receiverIndex = 0;
    var payerIndex = 0;

    while (receiverIndex < receivers.length && payerIndex < payers.length) {
      final receiver = receivers[receiverIndex];
      final payer = payers[payerIndex];
      
      // Calculate payment amount (minimum of what payer owes and receiver should receive)
      final paymentAmount = receiver.value < payer.value 
          ? receiver.value 
          : payer.value;
      
      if (paymentAmount > Decimal.zero) {
        simplifiedDebts.add(SimplifiedDebt(
          fromUserId: payer.key,      // Person who owes money
          toUserId: receiver.key,     // Person who should receive money
          amount: paymentAmount.round(scale: 2),
          currency: currency,
        ));
      }

      // Update balances and advance indices as needed
      if (receiver.value == paymentAmount) {
        receiverIndex++;  // This receiver is fully paid
      } else {
        // Update receiver's remaining amount
        receivers[receiverIndex] = MapEntry(
          receiver.key, 
          receiver.value - paymentAmount
        );
      }
      
      if (payer.value == paymentAmount) {
        payerIndex++;  // This payer has fully settled their debt
      } else {
        // Update payer's remaining amount
        payers[payerIndex] = MapEntry(
          payer.key, 
          payer.value - paymentAmount
        );
      }
    }

    return simplifiedDebts;
  }

  static Decimal _parseDecimal(dynamic v) {
    if (v == null) return Decimal.zero;
    if (v is Decimal) return v;
    return Decimal.tryParse(v.toString()) ?? Decimal.zero;
  }
}

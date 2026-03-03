/// Split entity: amount a user owes for an expense.
class Split {
  const Split({
    required this.id,
    required this.expenseId,
    required this.userId,
    required this.universalUsdOwed,
  });

  final String id;
  final String expenseId;
  final String userId;
  final String universalUsdOwed; // Use string for Decimal compatibility
}

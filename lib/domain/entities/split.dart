/// Split entity: amount a user owes for an expense.
class Split {
  const Split({
    required this.id,
    required this.expenseId,
    required this.userId,
    required this.amountOwed,
  });

  final String id;
  final String expenseId;
  final String userId;
  final String amountOwed; // Use string for Decimal compatibility
}

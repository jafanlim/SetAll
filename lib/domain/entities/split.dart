/// Split entity: amount a user owes for an expense.
class Split {
  const Split({
    required this.id,
    required this.expenseId,
    required this.userId,
    required this.universalUsdOwed,
    this.entryAmountOwed,
  });

  final String id;
  final String expenseId;
  final String userId;
  final String universalUsdOwed;  // Use string for Decimal compatibility
  final String? entryAmountOwed; // Amount in the expense's entry currency (no USD conversion)
}

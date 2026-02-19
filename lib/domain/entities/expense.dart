/// Expense entity.
enum SplitType { even, manual, parts }

/// Splitwise-style categories.
const List<String> kExpenseCategories = [
  'General',
  'Food & drink',
  'Transport',
  'Entertainment',
  'Bills & utilities',
  'Shopping',
  'Travel',
  'Other',
];

class Expense {
  const Expense({
    required this.id,
    required this.groupId,
    required this.payerId,
    required this.amount,
    this.description = '',
    this.currency = 'USD',
    this.splitType = SplitType.even,
    this.category = 'General',
    this.createdAt,
  });

  final String id;
  final String groupId;
  final String payerId;
  final String amount; // Use string for Decimal compatibility
  final String description;
  final String currency;
  final SplitType splitType;
  final String category;
  /// ISO date or datetime string from DB for display.
  final String? createdAt;
}

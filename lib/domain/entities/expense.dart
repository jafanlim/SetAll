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
    this.createdBy,
    this.originalAmount,
    this.originalCurrency,
    this.exchangeRateApplied,
    this.universalUsdAmount,
  });

  final String id;
  final String groupId;
  final String payerId;

  /// The stored amount (string for Decimal compatibility).
  /// For expenses entered in a foreign currency, this is the amount converted
  /// to the user's base currency at entry time. [universalUsdAmount] is the
  /// canonical frozen USD value since schema v8.
  final String amount;

  final String description;
  final String currency;
  final SplitType splitType;
  final String category;
  final String? createdAt;

  /// The user ID who created this expense (maps to Supabase auth.uid()).
  final String? createdBy;

  /// Original amount before USD conversion (null when entered in USD).
  final String? originalAmount;

  /// Original currency code before conversion (null when entered in USD).
  final String? originalCurrency;

  /// Exchange rate used at entry time: 1 [originalCurrency] = [exchangeRateApplied] [currency].
  final String? exchangeRateApplied;

  /// Pre-computed total in pure USD at the time of entry.
  ///
  /// This is the **definitive** field for balance calculations (schema v8+).
  /// It is immune to future rate changes.
  /// NULL for expenses created before schema v8.
  final String? universalUsdAmount;
}

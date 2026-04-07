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
    this.groupId,
    required this.payerId,
    required this.amount,
    this.description = '',
    this.currency = 'USD',
    this.splitType = SplitType.even,
    this.category = 'General',
    this.isIncome = false,
    this.createdAt,
    this.createdBy,
    this.originalAmount,
    this.originalCurrency,
    this.exchangeRateApplied,
    this.universalUsdAmount,
    this.baseCurrencyAmount,
    this.iconCodepoint,
    this.iconColor,
    this.attachmentUrls,
    this.notes,
  });

  final String id;
  final String? groupId;
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

  /// When true, this entry is income (positive cash-flow) in the wallet.
  final bool isIncome;

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

  /// Frozen total in the user's base currency at entry time (schema v33+).
  ///
  /// Eliminates USD-rate drift in wallet totals: wallet total = SUM of this
  /// field instead of re-converting [universalUsdAmount] at live rates.
  /// NULL for group expenses and for wallet entries created before schema v33.
  final String? baseCurrencyAmount;

  /// Icon codepoint (e.g. IconData.codePoint). NULL means use default.
  final int? iconCodepoint;

  /// Accent colour as ARGB integer. NULL means use default.
  final int? iconColor;

  /// Storage paths of attached files (e.g. ["uid/expId/receipt.jpg"]).
  /// NULL or empty means no attachments.
  final List<String>? attachmentUrls;

  /// Long-form notes. Also populated with content of .txt / .md attachments.
  final String? notes;
}

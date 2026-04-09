import 'dart:convert';

class WalletEntryModel {
  const WalletEntryModel({
    required this.id,
    required this.userId,
    required this.amount,
    this.isIncome = false,
    this.description = '',
    this.category = 'Other',
    this.currency = 'USD',
    this.originalAmount,
    this.originalCurrency,
    this.exchangeRateApplied,
    this.universalUsdAmount = '0',
    this.baseCurrencyAmount,
    this.iconCodepoint,
    this.iconColor,
    this.notes,
    this.attachmentUrls,
    this.deletedAt,
    this.createdAt,
    this.updatedAt,
    this.syncedAt,
  });

  final String id;
  final String userId;
  final String amount;
  final bool isIncome;
  final String description;
  final String category;
  final String currency;
  final String? originalAmount;
  final String? originalCurrency;
  final String? exchangeRateApplied;
  final String universalUsdAmount;
  /// Frozen base-currency amount computed at save time (schema v33+).
  /// Used as annotation on category rows: ≈ baseCurrency amount.
  final String? baseCurrencyAmount;
  final int? iconCodepoint;
  final int? iconColor;
  final String? notes;
  final List<String>? attachmentUrls;
  final String? deletedAt;
  final String? createdAt;
  final String? updatedAt;
  final int? syncedAt;

  factory WalletEntryModel.fromJson(Map<String, dynamic> json) {
    return WalletEntryModel(
      id: json['id'] as String,
      userId: (json['user_id'] ?? '').toString(),
      amount: (json['amount'] ?? '0').toString(),
      isIncome: switch (json['is_income']) {
        final bool b => b,
        final int i  => i != 0,
        _            => false,
      },
      description: (json['description'] as String?) ?? '',
      category: (json['category'] as String?) ?? 'Other',
      currency: (json['currency'] as String?) ?? 'USD',
      originalAmount: json['original_amount']?.toString(),
      originalCurrency: json['original_currency'] as String?,
      exchangeRateApplied: json['exchange_rate_applied']?.toString(),
      universalUsdAmount: (json['universal_usd_amount'])?.toString() ?? '0',
      baseCurrencyAmount: json['base_currency_amount']?.toString(),
      iconCodepoint: json['icon_codepoint'] as int?,
      iconColor: json['icon_color'] as int?,
      notes: json['notes'] as String?,
      attachmentUrls: _parseUrls(json['attachment_urls']),
      deletedAt: json['deleted_at'] as String?,
      createdAt: json['created_at'] as String?,
      updatedAt: json['updated_at'] as String?,
      syncedAt: json['synced_at'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'amount': amount,
    'is_income': isIncome ? 1 : 0,
    'description': description,
    'category': category,
    'currency': currency,
    if (originalAmount != null)     'original_amount': originalAmount,
    if (originalCurrency != null)   'original_currency': originalCurrency,
    if (exchangeRateApplied != null)'exchange_rate_applied': exchangeRateApplied,
    'universal_usd_amount': universalUsdAmount,
    if (baseCurrencyAmount != null) 'base_currency_amount': baseCurrencyAmount,
    if (iconCodepoint != null)      'icon_codepoint': iconCodepoint,
    if (iconColor != null)          'icon_color': iconColor,
    if (notes != null)              'notes': notes,
    'attachment_urls': attachmentUrls == null ? null : jsonEncode(attachmentUrls),
    if (deletedAt != null)          'deleted_at': deletedAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  Map<String, dynamic> toSupabaseJson() => {
    'id': id,
    'user_id': userId,
    'amount': double.tryParse(amount) ?? 0,
    'is_income': isIncome,
    'description': description,
    'category': category,
    'currency': currency,
    if (originalAmount != null)      'original_amount': double.tryParse(originalAmount!),
    if (originalCurrency != null)    'original_currency': originalCurrency,
    if (exchangeRateApplied != null) 'exchange_rate_applied': double.tryParse(exchangeRateApplied!),
    'universal_usd_amount': double.tryParse(universalUsdAmount) ?? 0,
    if (iconCodepoint != null)       'icon_codepoint': iconCodepoint,
    if (iconColor != null)           'icon_color': (iconColor!).toSigned(32),
    if (notes != null)               'notes': notes,
    'attachment_urls': attachmentUrls == null ? null : jsonEncode(attachmentUrls),
    if (deletedAt != null)           'deleted_at': deletedAt,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };

  WalletEntryModel copyWith({
    String? id,
    String? userId,
    String? amount,
    bool? isIncome,
    String? description,
    String? category,
    String? currency,
    String? originalAmount,
    String? originalCurrency,
    String? exchangeRateApplied,
    String? universalUsdAmount,
    String? baseCurrencyAmount,
    int? iconCodepoint,
    int? iconColor,
    String? notes,
    List<String>? attachmentUrls,
    String? deletedAt,
    String? createdAt,
    String? updatedAt,
    int? syncedAt,
  }) => WalletEntryModel(
    id:                   id                   ?? this.id,
    userId:               userId               ?? this.userId,
    amount:               amount               ?? this.amount,
    isIncome:             isIncome             ?? this.isIncome,
    description:          description          ?? this.description,
    category:             category             ?? this.category,
    currency:             currency             ?? this.currency,
    originalAmount:       originalAmount       ?? this.originalAmount,
    originalCurrency:     originalCurrency     ?? this.originalCurrency,
    exchangeRateApplied:  exchangeRateApplied  ?? this.exchangeRateApplied,
    universalUsdAmount:   universalUsdAmount   ?? this.universalUsdAmount,
    baseCurrencyAmount:   baseCurrencyAmount   ?? this.baseCurrencyAmount,
    iconCodepoint:        iconCodepoint        ?? this.iconCodepoint,
    iconColor:            iconColor            ?? this.iconColor,
    notes:                notes                ?? this.notes,
    attachmentUrls:       attachmentUrls       ?? this.attachmentUrls,
    deletedAt:            deletedAt            ?? this.deletedAt,
    createdAt:            createdAt            ?? this.createdAt,
    updatedAt:            updatedAt            ?? this.updatedAt,
    syncedAt:             syncedAt             ?? this.syncedAt,
  );

  static List<String>? _parseUrls(dynamic raw) {
    if (raw == null) return null;
    if (raw is List) return raw.cast<String>();
    if (raw is String && raw.isNotEmpty) {
      try { return List<String>.from(jsonDecode(raw) as List); } catch (_) {}
    }
    return null;
  }
}

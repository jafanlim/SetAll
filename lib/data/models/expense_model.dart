import '../../domain/entities/expense.dart';

class ExpenseModel extends Expense {
  const ExpenseModel({
    required super.id,
    required super.groupId,
    required super.payerId,
    required super.amount,
    super.description = '',
    super.currency = 'USD',
    super.splitType = SplitType.even,
    super.category = 'General',
    super.createdAt,
    super.originalAmount,
    super.originalCurrency,
    super.exchangeRateApplied,
    super.baseAmountAtEntry,
  });

  static SplitType _splitTypeFromString(String? v) {
    switch (v) {
      case 'manual':
        return SplitType.manual;
      case 'parts':
        return SplitType.parts;
      default:
        return SplitType.even;
    }
  }

  factory ExpenseModel.fromJson(Map<String, dynamic> json) {
    return ExpenseModel(
      id: json['id'] as String,
      groupId: json['group_id'] as String,
      payerId: json['payer_id'] as String,
      amount: (json['amount'] ?? '0').toString(),
      description: (json['description'] as String?) ?? '',
      currency: (json['currency'] as String?) ?? 'USD',
      splitType: _splitTypeFromString(json['split_type'] as String?),
      category: (json['category'] as String?) ?? 'General',
      createdAt: json['created_at'] as String?,
      originalAmount: json['original_amount']?.toString(),
      originalCurrency: json['original_currency'] as String?,
      exchangeRateApplied: json['exchange_rate_applied']?.toString(),
      baseAmountAtEntry: json['universal_usd_amount']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'group_id': groupId,
        'payer_id': payerId,
        'amount': amount,
        'description': description,
        'currency': currency,
        'split_type': splitType.name,
        'category': category,
        'created_at': createdAt,
        if (originalAmount != null) 'original_amount': originalAmount,
        if (originalCurrency != null) 'original_currency': originalCurrency,
        if (exchangeRateApplied != null) 'exchange_rate_applied': exchangeRateApplied,
        // CHANGED: Mapped to universal_usd_amount
        if (baseAmountAtEntry != null) 'universal_usd_amount': baseAmountAtEntry,
      };
}
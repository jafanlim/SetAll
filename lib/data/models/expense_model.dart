import 'dart:convert';

import '../../domain/entities/expense.dart';

class ExpenseModel extends Expense {
  const ExpenseModel({
    required super.id,
    super.groupId,
    required super.payerId,
    required super.amount,
    super.description = '',
    super.currency = 'USD',
    super.splitType = SplitType.even,
    super.category = 'General',
    super.isIncome = false,
    super.createdAt,
    super.createdBy,
    super.originalAmount,
    super.originalCurrency,
    super.exchangeRateApplied,
    super.universalUsdAmount,
    super.iconCodepoint,
    super.iconColor,
    super.attachmentUrls,
    super.notes,
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
      groupId: json['group_id'] as String?,
      payerId: (json['payer_id'] ?? '').toString(),
      // 'amount' is the raw total
      amount: (json['amount'] ?? '0').toString(),
      description: (json['description'] as String?) ?? '',
      currency: (json['currency'] as String?) ?? 'USD',
      splitType: _splitTypeFromString(json['split_type'] as String?),
      category: (json['category'] as String?) ?? 'General',
      isIncome: switch (json['is_income']) {
        final bool b => b,
        final int i => i != 0,
        _ => false,
      },
      createdAt: json['created_at'] as String?,
      createdBy: json['created_by'] as String?,
      originalAmount: json['original_amount']?.toString(),
      originalCurrency: json['original_currency'] as String?,
      exchangeRateApplied: json['exchange_rate_applied']?.toString(),
      // 'universal_usd_amount' is the USD anchor
      universalUsdAmount: (json['universal_usd_amount'])?.toString(),
      iconCodepoint: json['icon_codepoint'] as int?,
      iconColor: json['icon_color'] as int?,
      attachmentUrls: _parseAttachmentUrls(json['attachment_urls']),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (groupId != null) 'group_id': groupId,
        'payer_id': payerId,
        'amount': amount,
        'description': description,
        'currency': currency,
        'split_type': splitType.name,
        'category': category,
        'is_income': isIncome ? 1 : 0,
        'created_at': createdAt,
        if (createdBy != null) 'created_by': createdBy,
        'universal_usd_amount': universalUsdAmount, // Key MUST be universal_usd_amount
        if (originalAmount != null) 'original_amount': originalAmount,
        if (originalCurrency != null) 'original_currency': originalCurrency,
        if (exchangeRateApplied != null) 'exchange_rate_applied': exchangeRateApplied,
        if (iconCodepoint != null) 'icon_codepoint': iconCodepoint,
        if (iconColor != null) 'icon_color': iconColor,
        if (attachmentUrls != null && attachmentUrls!.isNotEmpty)
          'attachment_urls': jsonEncode(attachmentUrls),
        if (notes != null && notes!.isNotEmpty) 'notes': notes,
      };

  static List<String>? _parseAttachmentUrls(dynamic raw) {
    if (raw == null) return null;
    try {
      if (raw is String && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.cast<String>();
      }
    } catch (_) {}
    return null;
  }
}
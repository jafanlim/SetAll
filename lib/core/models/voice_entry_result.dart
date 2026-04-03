class VoiceEntryResult {
  final String type;
  final double amount;
  final String currency;
  final String description;
  final String category;
  final bool isIncome;
  final String? groupNameHint;
  final String splitMode;
  final String? needsClarification;

  const VoiceEntryResult({
    required this.type,
    required this.amount,
    required this.currency,
    required this.description,
    required this.category,
    required this.isIncome,
    this.groupNameHint,
    required this.splitMode,
    this.needsClarification,
  });

  factory VoiceEntryResult.fromJson(Map<String, dynamic> json) => VoiceEntryResult(
    type: json['type'] as String? ?? 'wallet',
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    currency: json['currency'] as String? ?? 'USD',
    description: json['description'] as String? ?? '',
    category: json['category'] as String? ?? 'Other',
    isIncome: json['isIncome'] == true,
    groupNameHint: json['groupNameHint'] as String?,
    splitMode: json['splitMode'] as String? ?? 'even',
    needsClarification: json['needsClarification'] as String?,
  );
}

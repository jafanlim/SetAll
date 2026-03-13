import '../../domain/entities/split.dart';

class SplitModel extends Split {
  const SplitModel({
    required super.id,
    required super.expenseId,
    required super.userId,
    required super.universalUsdOwed,
    super.entryAmountOwed,
  });

   factory SplitModel.fromJson(Map<String, dynamic> json) {
    return SplitModel(
      id: json['id'] as String,
      expenseId: json['expense_id'] as String,
      userId: json['user_id'] as String,
      // Support both the new column name (universal_usd_owed, schema v8+) and
      // the old name (amount_owed) for DBs not yet migrated via 20260220110135.
      universalUsdOwed: (json['universal_usd_owed'] ?? json['amount_owed'] ?? '0').toString(),
      entryAmountOwed: json['entry_amount_owed']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'expense_id': expenseId,
        'user_id': userId,
        'universal_usd_owed': universalUsdOwed,
        if (entryAmountOwed != null) 'entry_amount_owed': entryAmountOwed,
      };
}

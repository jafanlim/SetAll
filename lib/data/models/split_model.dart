import '../../domain/entities/split.dart';

class SplitModel extends Split {
  const SplitModel({
    required super.id,
    required super.expenseId,
    required super.userId,
    required super.amountOwed,
  });

   factory SplitModel.fromJson(Map<String, dynamic> json) {
    return SplitModel(
      id: json['id'] as String,
      expenseId: json['expense_id'] as String,
      userId: json['user_id'] as String,
      // CHANGED: Support both num (Supabase) and String (SQLite)
      amountOwed: (json['universal_usd_owed'] ?? '0').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'expense_id': expenseId,
        'user_id': userId,
        // CHANGED
        'universal_usd_owed': amountOwed,
      };
}

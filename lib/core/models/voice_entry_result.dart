// ── Voice action sealed hierarchy ─────────────────────────────────────────

sealed class VoiceAction {
  const VoiceAction();

  static VoiceAction fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'add_expense';
    switch (type) {
      case 'create_group':
        return CreateGroupAction(
          name: json['name'] as String? ?? '',
        );
      case 'add_member':
        return AddMemberAction(
          memberNameHint: json['memberNameHint'] as String? ?? '',
          groupNameHint: json['groupNameHint'] as String?,
        );
      case 'add_expense':
      case 'add_income':
      default:
        return AddExpenseAction(
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
  }
}

class AddExpenseAction extends VoiceAction {
  final double amount;
  final String currency;
  final String description;
  final String category;
  final bool isIncome;
  final String? groupNameHint;
  final String splitMode;
  final String? needsClarification;

  const AddExpenseAction({
    required this.amount,
    required this.currency,
    required this.description,
    required this.category,
    required this.isIncome,
    this.groupNameHint,
    required this.splitMode,
    this.needsClarification,
  });

  AddExpenseAction copyWith({String? needsClarification}) => AddExpenseAction(
    amount: amount,
    currency: currency,
    description: description,
    category: category,
    isIncome: isIncome,
    groupNameHint: groupNameHint,
    splitMode: splitMode,
    needsClarification: needsClarification ?? this.needsClarification,
  );
}

class CreateGroupAction extends VoiceAction {
  final String name;
  const CreateGroupAction({required this.name});
}

class AddMemberAction extends VoiceAction {
  final String memberNameHint;
  final String? groupNameHint;
  const AddMemberAction({required this.memberNameHint, this.groupNameHint});
}

// ── Top-level parse response ───────────────────────────────────────────────

class VoiceParseResponse {
  final List<VoiceAction> actions;
  final String? needsClarification;

  const VoiceParseResponse({
    required this.actions,
    this.needsClarification,
  });

  factory VoiceParseResponse.fromJson(Map<String, dynamic> json) {
    // Top-level clarification (e.g. empty transcript → amount)
    if (json.containsKey('needsClarification') && !json.containsKey('actions')) {
      return VoiceParseResponse(
        actions: const [],
        needsClarification: json['needsClarification'] as String?,
      );
    }

    // New multi-action shape
    if (json.containsKey('actions')) {
      final rawList = json['actions'] as List<dynamic>;
      return VoiceParseResponse(
        actions: rawList
            .map((e) => VoiceAction.fromJson(e as Map<String, dynamic>))
            .toList(),
        needsClarification: json['needsClarification'] as String?,
      );
    }

    // Fallback: old flat shape — wrap in single add_expense
    return VoiceParseResponse(
      actions: [VoiceAction.fromJson(json)],
    );
  }
}

// ── Backward-compat alias ──────────────────────────────────────────────────
// Code that still references VoiceEntryResult can be migrated incrementally.
typedef VoiceEntryResult = AddExpenseAction;

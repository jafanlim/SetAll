import '../../data/models/expense_model.dart';
import '../../data/models/wallet_entry_model.dart';

/// Discriminated union for the Omni Activity Feed.
/// Each variant maps to a distinct UI tile in [ActivityScreen].
sealed class ActivityEvent {
  const ActivityEvent({required this.timestamp});

  /// ISO-8601 string used for chronological sorting & date-section headers.
  final String timestamp;
}

/// A shared or personal expense entry.
class ExpenseEvent extends ActivityEvent {
  const ExpenseEvent({
    required super.timestamp,
    required this.expense,
    required this.groupName,
    this.payerName = '',
  });

  final ExpenseModel expense;

  /// Empty string when [expense.groupId] is null (personal wallet entry).
  final String groupName;

  /// Display name of the payer (empty string falls back to "You" in the tile).
  final String payerName;
}

/// A group was created by the current user or someone else in the group.
class GroupCreatedEvent extends ActivityEvent {
  const GroupCreatedEvent({
    required super.timestamp,
    required this.groupId,
    required this.groupName,
    required this.createdByYou,
  });

  final String groupId;
  final String groupName;
  final bool createdByYou;
}

/// A group was deleted by the current user.
class GroupDeletedEvent extends ActivityEvent {
  const GroupDeletedEvent({
    required super.timestamp,
    required this.groupId,
    required this.groupName,
    required this.creatorId,
    required this.deletedAt,
  });

  final String groupId;
  final String groupName;
  /// The original creator/owner of the group.
  final String creatorId;
  /// UTC timestamp of when the group was soft-deleted (used for 90-day window).
  final DateTime deletedAt;
}

/// An expense was deleted by any user (personal or group).
/// The snapshot of the expense data is preserved for display and potential restore.
class ExpenseDeletedEvent extends ActivityEvent {
  const ExpenseDeletedEvent({
    required super.timestamp,
    required this.expenseId,
    required this.description,
    required this.amount,
    required this.currency,
    required this.groupId,
    required this.groupName,
    required this.isIncome,
    required this.deletedByYou,
    required this.deletedByName,
    required this.deletedAt,
    required this.category,
    this.deletedWithGroupId,
  });

  final String  expenseId;
  final String  description;
  final String  amount;
  final String  currency;
  final String? groupId;
  final String  groupName;
  final bool    isIncome;
  final bool    deletedByYou;
  final String  deletedByName;
  final DateTime deletedAt;
  final String  category;
  /// Non-null when this expense was cascade-deleted together with its group.
  final String? deletedWithGroupId;
}

/// An expense was edited (description, category, amount, etc.) by any user.
class ExpenseEditedEvent extends ActivityEvent {
  const ExpenseEditedEvent({
    required super.timestamp,
    required this.expenseId,
    required this.oldDescription,
    required this.newDescription,
    required this.oldCategory,
    required this.newCategory,
    required this.oldAmount,
    required this.newAmount,
    required this.currency,
    required this.groupId,
    required this.groupName,
    required this.editedByYou,
    required this.editedByName,
  });

  final String  expenseId;
  final String  oldDescription;
  final String  newDescription;
  final String  oldCategory;
  final String  newCategory;
  final String  oldAmount;
  final String  newAmount;
  final String  currency;
  final String? groupId;
  final String  groupName;
  final bool    editedByYou;
  final String  editedByName;
}

/// A member was added to a group.
class MemberAddedEvent extends ActivityEvent {
  const MemberAddedEvent({
    required super.timestamp,
    required this.groupId,
    required this.groupName,
    required this.addedByName,
    required this.addedByYou,
    required this.addedUserName,
    required this.addedYou,
  });

  final String groupId;
  final String groupName;
  final String addedByName;
  final bool addedByYou;
  final String addedUserName;
  final bool addedYou;
}

/// A wallet entry was deleted by the current user — snapshot preserved for display.
class WalletEntryDeletedEvent extends ActivityEvent {
  const WalletEntryDeletedEvent({
    required super.timestamp,
    required this.entryId,
    required this.description,
    required this.amount,
    required this.currency,
    required this.isIncome,
    required this.category,
    required this.deletedAt,
  });

  final String   entryId;
  final String   description;
  final String   amount;
  final String   currency;
  final bool     isIncome;
  final String   category;
  final DateTime deletedAt;
}

/// A wallet entry (personal income or expense) from the wallet_entries table.
class WalletActivityEvent extends ActivityEvent {
  const WalletActivityEvent({
    required super.timestamp,
    required this.entry,
  });

  final WalletEntryModel entry;
}

/// A group was marked as fully settled.
class GroupSettledEvent extends ActivityEvent {
  const GroupSettledEvent({
    required super.timestamp,
    required this.groupId,
    required this.groupName,
    required this.settledByUid,
    required this.settledByName,
    required this.settledByYou,
  });

  final String groupId;
  final String groupName;
  final String settledByUid;
  final String settledByName;
  final bool settledByYou;
}

/// A group's settled status was cleared (reopened).
class GroupReopenedEvent extends ActivityEvent {
  const GroupReopenedEvent({
    required super.timestamp,
    required this.groupId,
    required this.groupName,
    required this.reopenedByYou,
    required this.reopenedByName,
  });

  final String groupId;
  final String groupName;
  final bool reopenedByYou;
  final String reopenedByName;
}

/// A settlement was recorded in a group.
class SettlementEvent extends ActivityEvent {
  const SettlementEvent({
    required super.timestamp,
    required this.fromUserId,
    required this.toUserId,
    required this.fromName,
    required this.toName,
    required this.amount,
    required this.currency,
    required this.isYouSender,
  });

  final String fromUserId;
  final String toUserId;
  final String fromName;
  final String toName;
  final String amount;
  final String currency;

  /// True when the current user is the one who settled (paid).
  final bool isYouSender;
}

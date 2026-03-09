import '../../data/models/expense_model.dart';

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
  });

  final ExpenseModel expense;

  /// Empty string when [expense.groupId] is null (personal wallet entry).
  final String groupName;
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

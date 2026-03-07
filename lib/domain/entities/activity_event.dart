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

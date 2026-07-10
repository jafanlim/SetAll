import 'package:decimal/decimal.dart';

import '../../../../domain/services/settlement_engine.dart';

/// Position of a member's net balance within a group.
enum NetPosition {
  /// Member is owed money (positive net).
  isOwed,

  /// Member owes money (negative net).
  owes,

  /// Member is settled (net rounds to zero).
  settled,
}

/// Per-member net balance label computed from simplified debts.
///
/// Pure function — no I/O, no providers. Testable in isolation.
///
/// Net = Σ(t.amount where t.toUserId == memberId) −
///       Σ(t.amount where t.fromUserId == memberId).
///
/// Applies the sub-cent rounding rule (PR #40): if |rounded net| < 0.01,
/// the position is treated as [NetPosition.settled] with a zero display amount.
({NetPosition position, Decimal displayAmount}) computeMemberNetPosition({
  required String memberId,
  required List<SettlementTransaction> debts,
}) {
  var net = Decimal.zero;
  for (final t in debts) {
    if (t.toUserId == memberId) net += t.amount;
    if (t.fromUserId == memberId) net -= t.amount;
  }

  final rounded = net.round(scale: 2);
  final absRounded = rounded.abs();

  // Sub-cent rule (PR #40 Math-Guard): if |rounded| < 0.01, treat as settled.
  if (absRounded < Decimal.parse('0.01')) {
    return (position: NetPosition.settled, displayAmount: Decimal.zero);
  }

  if (rounded > Decimal.zero) {
    return (position: NetPosition.isOwed, displayAmount: rounded);
  }
  return (position: NetPosition.owes, displayAmount: -rounded);
}

import 'package:decimal/decimal.dart';

/// Result of a single user's share for an expense.
class SplitResult {
  const SplitResult({
    required this.userId,
    required this.amountOwed,
  });

  final String userId;
  final Decimal amountOwed;
}

/// Handles even and custom (manual/parts) splits with precise decimal math.
class SplitEngine {
  SplitEngine._();

  /// Even split: total / participantCount. Remainder applied to first participant.
  static List<SplitResult> splitEven({
    required Decimal total,
    required List<String> participantIds,
  }) {
    if (participantIds.isEmpty) return [];
    if (total <= Decimal.zero) {
      return participantIds.map((id) => SplitResult(userId: id, amountOwed: Decimal.zero)).toList();
    }

    final n = Decimal.fromInt(participantIds.length);
    final base = (total / n).toDecimal(scaleOnInfinitePrecision: 2).round(scale: 2);
    // First participant gets remainder so total adds up exactly
    final remainder = total - (base * (n - Decimal.one));

    final results = <SplitResult>[];
    for (var i = 0; i < participantIds.length; i++) {
      final amount = (i == 0) ? remainder : base;
      results.add(SplitResult(userId: participantIds[i], amountOwed: amount));
    }
    return results;
  }

  /// Manual/parts split: each participant has a weight (or fixed amount).
  /// If [amountsOwed] is provided, those are used as fixed amounts (must sum to [total]).
  /// Otherwise [weights] are used (relative parts); if weights missing, treated as equal.
  static List<SplitResult> splitCustom({
    required Decimal total,
    required List<String> participantIds,
    List<Decimal>? weights,
    List<Decimal>? amountsOwed,
  }) {
    if (participantIds.isEmpty) return [];

    if (amountsOwed != null && amountsOwed.length == participantIds.length) {
      return List.generate(
        participantIds.length,
        (i) => SplitResult(userId: participantIds[i], amountOwed: amountsOwed[i]),
      );
    }

    final w = weights ?? List.filled(participantIds.length, Decimal.one);
    if (w.length != participantIds.length) {
      throw ArgumentError('weights length must match participantIds');
    }
    final sumWeights = w.fold<Decimal>(Decimal.zero, (a, b) => a + b);
    if (sumWeights <= Decimal.zero) {
      throw ArgumentError('Sum of weights must be positive');
    }

    var allocated = Decimal.zero;
    final results = <SplitResult>[];
    for (var i = 0; i < participantIds.length; i++) {
      Decimal amount;
      if (i == participantIds.length - 1) {
        amount = total - allocated;
      } else {
        amount = ((total * w[i]) / sumWeights).toDecimal(scaleOnInfinitePrecision: 2).round(scale: 2);
        allocated += amount;
      }
      results.add(SplitResult(userId: participantIds[i], amountOwed: amount));
    }
    return results;
  }
}

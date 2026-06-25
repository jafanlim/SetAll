import 'package:decimal/decimal.dart';

/// A detected recurring-payment candidate before the user confirms/dismisses.
class RecurringCandidate {
  const RecurringCandidate({
    required this.description,
    required this.amount,
    required this.currency,
    required this.category,
    required this.intervalDays,
    required this.lastSeenAt,
    required this.confidence,
    required this.occurrences,
  });

  final String description;
  final Decimal amount;
  final String currency;
  final String category;
  final int intervalDays;
  final DateTime lastSeenAt;
  /// 0.0–1.0 heuristic confidence score.
  final double confidence;
  /// Raw occurrence dates that contributed to this candidate.
  final List<DateTime> occurrences;

  DateTime get nextExpected =>
      lastSeenAt.add(Duration(days: intervalDays));
}

/// Canonical duplicate-signature shared between the Splitwise importer and the
/// bank-statement ingestion pipeline.
///
/// Two rows match when they share the same calendar day (in local time),
/// normalized description, amount rounded to cents, and currency.  Dates are
/// normalized to local time so a stored UTC `created_at` and a locally-parsed
/// CSV/statement date compare on the same day.
library;

import 'package:decimal/decimal.dart';

String importDedupSig(
  DateTime date,
  String description,
  Decimal amount,
  String currency,
) {
  final d = date.toLocal();
  final day = '${d.year}-${d.month}-${d.day}';
  return '$day|${description.trim().toLowerCase()}'
      '|${amount.round(scale: 2)}|${currency.trim().toUpperCase()}';
}

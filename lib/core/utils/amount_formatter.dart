import 'package:decimal/decimal.dart';

/// Formats a raw amount string to always display 2 decimal places.
/// e.g. "100" → "100.00", "100.0" → "100.00", "99.5" → "99.50"
/// Falls back to the original string if parsing fails.
String formatAmount(String? raw) {
  if (raw == null || raw.isEmpty) return '0.00';
  final d = Decimal.tryParse(raw);
  if (d == null) return raw;
  return d.toStringAsFixed(2);
}

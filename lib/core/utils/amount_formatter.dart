import 'package:decimal/decimal.dart';

/// Zero-decimal currencies (whole units only — no cents).
const _kZeroDecimalCurrencies = {
  'JPY', 'KRW', 'VND', 'IDR', 'CLP', 'PYG', 'UGX', 'RWF',
  'BIF', 'GNF', 'KMF', 'MGA', 'XAF', 'XOF', 'XPF',
};

/// Crypto / high-precision currencies that should display up to 6 dp.
const _kHighPrecisionCurrencies = {
  'BTC', 'ETH', 'LTC', 'BCH', 'XRP', 'ADA', 'DOT', 'SOL',
  'DOGE', 'MATIC', 'BNB', 'AVAX', 'LINK', 'UNI', 'ATOM',
};

/// Returns the canonical number of decimal places for [currency].
int decimalPlacesFor(String currency) {
  final upper = currency.toUpperCase();
  if (_kZeroDecimalCurrencies.contains(upper)) return 0;
  if (_kHighPrecisionCurrencies.contains(upper)) return 6;
  return 2;
}

/// Formats a raw amount string to always display 2 decimal places.
/// e.g. "100" → "100.00", "100.0" → "100.00", "99.5" → "99.50"
/// Falls back to the original string if parsing fails.
String formatAmount(String? raw) {
  if (raw == null || raw.isEmpty) return '0.00';
  final d = Decimal.tryParse(raw);
  if (d == null) return raw;
  return d.toStringAsFixed(2);
}

/// Formats [raw] using the correct decimal places for [currency].
/// e.g. formatAmountForCurrency("1500", "JPY") → "1500"
///      formatAmountForCurrency("0.00045", "BTC") → "0.000450"
///      formatAmountForCurrency("12.5", "USD")  → "12.50"
String formatAmountForCurrency(String? raw, String currency) {
  if (raw == null || raw.isEmpty) {
    final dp = decimalPlacesFor(currency);
    return dp == 0 ? '0' : '0.${'0' * dp}';
  }
  final d = Decimal.tryParse(raw);
  if (d == null) return raw;
  final dp = decimalPlacesFor(currency);
  // High-precision currencies: show trailing zeros only when significant.
  // Minimum 2 dp, maximum 6 dp, trailing zeros stripped beyond 2 dp.
  if (dp == 6) {
    final fixed = d.toStringAsFixed(6); // e.g. "0.000450", "1.000000"
    final parts = fixed.split('.');
    final decimals = parts[1]; // always 6 chars
    // Find last non-zero position (0-indexed from left)
    int lastNonZero = 1; // minimum index = 1 → at least 2 dp
    for (int i = decimals.length - 1; i >= 2; i--) {
      if (decimals[i] != '0') { lastNonZero = i; break; }
    }
    // Keep max(2, lastNonZero+1) decimal places
    final keepDp = lastNonZero < 2 ? 2 : lastNonZero + 1;
    return '${parts[0]}.${decimals.substring(0, keepDp)}';
  }
  return d.toStringAsFixed(dp);
}

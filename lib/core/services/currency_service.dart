import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

/// Live exchange rates with optional manual override (e.g. bank fees).
/// Uses Frankfurter API (no key required). All money math in Decimal.
class CurrencyService {
  CurrencyService({http.Client? client, SharedPreferences? prefs})
      : _client = client ?? http.Client(),
        _prefs = prefs;

  static const String _baseUrl = 'https://api.frankfurter.dev/latest';
  static const String _prefsPrefix = 'setall_rate_override_';

  final http.Client _client;
  final SharedPreferences? _prefs;

  /// In-memory cache: "USD_EUR" -> rate (1 USD = rate EUR).
  final Map<String, Decimal> _cache = {};
  DateTime? _cacheTime;
  static const Duration _cacheValid = Duration(minutes: 15);

  /// Get rate from [fromCurrency] to [toCurrency] (1 from = ? to).
  /// If same currency, returns Decimal.one.
  /// Uses manual override if set (supports inverse: e.g. "1 USD = 4 EUR" gives EUR->USD = 1/4), else live API.
  Future<Decimal> getRate(String fromCurrency, String toCurrency) async {
    if (fromCurrency == toCurrency) return Decimal.one;

    final key = '${fromCurrency}_$toCurrency';
    var override = await _getManualOverride(fromCurrency, toCurrency);
    if (override == null) {
      final inverseOverride = await _getManualOverride(toCurrency, fromCurrency);
      if (inverseOverride != null && inverseOverride > Decimal.zero) {
        final rational = Decimal.one / inverseOverride;
        override = rational.toDecimal(scaleOnInfinitePrecision: 6);
        _cache[key] = override;
      }
    }
    if (override != null) return override;

    if (_cache.containsKey(key) && _cacheTime != null && DateTime.now().difference(_cacheTime!) < _cacheValid) {
      return _cache[key]!;
    }

    try {
      final rate = await _fetchRate(fromCurrency, toCurrency);
      _cache[key] = rate;
      _cacheTime = DateTime.now();
      return rate;
    } catch (_) {
      return _cache[key] ?? Decimal.one;
    }
  }

  /// Fetch live rate from Frankfurter.
  Future<Decimal> _fetchRate(String from, String to) async {
    final uri = Uri.parse('$_baseUrl?from=$from&to=$to');
    final response = await _client.get(uri);
    if (response.statusCode != 200) throw Exception('Rate fetch failed: ${response.statusCode}');
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final rates = json['rates'] as Map<String, dynamic>?;
    if (rates == null || !rates.containsKey(to)) throw Exception('Rate not found for $to');
    final value = rates[to];
    if (value is num) return Decimal.parse(value.toString());
    throw Exception('Invalid rate value');
  }

  /// Manual override (e.g. bank fee): 1 [from] = [rate] [to].
  Future<void> setManualOverride(String fromCurrency, String toCurrency, Decimal rate) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString('$_prefsPrefix${fromCurrency}_$toCurrency', rate.toString());
    final key = '${fromCurrency}_$toCurrency';
    _cache[key] = rate;
    _cacheTime = DateTime.now();
  }

  /// Clear manual override for this pair.
  Future<void> clearManualOverride(String fromCurrency, String toCurrency) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.remove('$_prefsPrefix${fromCurrency}_$toCurrency');
    _cache.remove('${fromCurrency}_$toCurrency');
  }

  Future<Decimal?> _getManualOverride(String from, String to) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final s = prefs.getString('$_prefsPrefix${from}_$to');
    if (s == null || s.isEmpty) return null;
    return Decimal.tryParse(s);
  }

  /// Convert [amount] from [fromCurrency] to [toCurrency] using getRate.
  Future<Decimal> convert(Decimal amount, String fromCurrency, String toCurrency) async {
    final rate = await getRate(fromCurrency, toCurrency);
    return (amount * rate).round(scale: 2);
  }
}

import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

import 'currency_sync_service.dart';

/// Resolves exchange rates with a three-tier priority:
///
///  1. **Manual override** – a user-entered rate for this specific transaction
///     (e.g. bank fee, cash exchange).  Stored in SharedPreferences.
///  2. **Supabase DB rates** – fetched by [CurrencySyncService] from the
///     `exchange_rates` table (Edge Function updates it every 24h).  Cached in
///     SharedPreferences → works fully offline.
///  3. **Live Frankfurter API** – last-resort fallback when DB rates are not yet
///     populated (first launch with no cache) AND the device is online.
///
/// All monetary arithmetic uses [Decimal] – no floating-point rounding errors.
class CurrencyService {
  CurrencyService({
    http.Client? client,
    SharedPreferences? prefs,
    CurrencySyncService? syncService,
  })  : _client = client ?? http.Client(),
        _prefs = prefs,
        _syncService = syncService;

  static const String _baseUrl = 'https://api.frankfurter.dev/latest';
  static const String _prefsPrefix = 'setall_rate_override_';

  final http.Client _client;
  final SharedPreferences? _prefs;
  final CurrencySyncService? _syncService;

  /// In-memory live-API cache (15-min TTL, fallback only).
  final Map<String, Decimal> _liveCache = {};
  DateTime? _liveCacheTime;
  static const Duration _liveCacheValid = Duration(minutes: 15);

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Get rate: 1 [fromCurrency] = ? [toCurrency].
  ///
  /// Resolution order:
  ///   Manual override → Supabase DB rates → Frankfurter live API.
  Future<Decimal> getRate(String fromCurrency, String toCurrency) async {
    if (fromCurrency == toCurrency) return Decimal.one;

    final key = '${fromCurrency}_$toCurrency';

    // --- 1. Manual override (highest priority) ---
    var override = await _getManualOverride(fromCurrency, toCurrency);
    if (override == null) {
      // Check stored inverse (e.g. if user stored USD→EUR, derive EUR→USD)
      final inv = await _getManualOverride(toCurrency, fromCurrency);
      if (inv != null && inv > Decimal.zero) {
        override = (Decimal.one / inv).toDecimal(scaleOnInfinitePrecision: 6);
        _liveCache[key] = override;
      }
    }
    if (override != null) return override;

    // --- 2. Supabase DB rates (primary source, cached offline) ---
    if (_syncService != null) {
      try {
        final dbRate = await _syncService.getRate(fromCurrency, toCurrency);
        if (dbRate != null && dbRate > Decimal.zero) {
          _liveCache[key] = dbRate;
          return dbRate;
        }
      } catch (_) {}
    }

    // --- 3. Live Frankfurter API (last resort) ---
    if (_liveCache.containsKey(key) &&
        _liveCacheTime != null &&
        DateTime.now().difference(_liveCacheTime!) < _liveCacheValid) {
      return _liveCache[key]!;
    }
    try {
      final rate = await _fetchLiveRate(fromCurrency, toCurrency);
      _liveCache[key] = rate;
      _liveCacheTime = DateTime.now();
      return rate;
    } catch (_) {
      return _liveCache[key] ?? Decimal.one;
    }
  }

  /// Get rate from [fromCurrency] to USD.
  Future<Decimal> getRateToUsd(String fromCurrency) async {
    return getRate(fromCurrency, 'USD');
  }

  /// Convenience: convert [amount] from [fromCurrency] to [toCurrency].
  Future<Decimal> convert(
    Decimal amount,
    String fromCurrency,
    String toCurrency,
  ) async {
    final rate = await getRate(fromCurrency, toCurrency);
    return (amount * rate).round(scale: 2);
  }

  // ---------------------------------------------------------------------------
  // Manual override (per-transaction)
  // ---------------------------------------------------------------------------

  /// Persist a manual rate: 1 [from] = [rate] [to].
  Future<void> setManualOverride(
    String fromCurrency,
    String toCurrency,
    Decimal rate,
  ) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.setString(
      '$_prefsPrefix${fromCurrency}_$toCurrency',
      rate.toString(),
    );
    _liveCache['${fromCurrency}_$toCurrency'] = rate;
    _liveCacheTime = DateTime.now();
  }

  /// Remove manual override for this pair.
  Future<void> clearManualOverride(
    String fromCurrency,
    String toCurrency,
  ) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    await prefs.remove('$_prefsPrefix${fromCurrency}_$toCurrency');
    _liveCache.remove('${fromCurrency}_$toCurrency');
  }

  // ---------------------------------------------------------------------------
  // Private helpers
  // ---------------------------------------------------------------------------

  Future<Decimal?> _getManualOverride(String from, String to) async {
    final prefs = _prefs ?? await SharedPreferences.getInstance();
    final s = prefs.getString('$_prefsPrefix${from}_$to');
    if (s == null || s.isEmpty) return null;
    return Decimal.tryParse(s);
  }

  Future<Decimal> _fetchLiveRate(String from, String to) async {
    final uri = Uri.parse('$_baseUrl?from=$from&to=$to');
    final response = await _client.get(uri);
    if (response.statusCode != 200) {
      throw Exception('Rate fetch failed: ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final rates = json['rates'] as Map<String, dynamic>?;
    if (rates == null || !rates.containsKey(to)) {
      throw Exception('Rate not found for $to');
    }
    final value = rates[to];
    if (value is num) return Decimal.parse(value.toString());
    throw Exception('Invalid rate value');
  }
}

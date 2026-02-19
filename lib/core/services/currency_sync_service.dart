import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Fetches exchange rates from the Supabase `exchange_rates` table, which is
/// populated by the `sync-exchange-rates` Edge Function every 24 hours.
///
/// This is the **single source of truth** for all currency conversions:
///  - One network round-trip per 24h for the entire platform (not per device).
///  - Rates are cached to SharedPreferences for full offline support.
///  - All Flutter clients read from the local cache; the Edge Function is the
///    only consumer of the external third-party API.
class CurrencySyncService {
  CurrencySyncService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;

  static const String _cacheKey = 'setall_v2_exchange_rates';
  static const String _cacheTimeKey = 'setall_v2_exchange_rates_ts';

  /// In-memory cache (avoids repeated SharedPreferences reads within a session).
  Map<String, Decimal>? _memCache;

  // ---------------------------------------------------------------------------
  // Public API
  // ---------------------------------------------------------------------------

  /// Returns rate: 1 [from] = ? [to].
  /// All Supabase rates are stored as: 1 USD = X target.
  /// Cross-rates are computed as: (to_rate / from_rate).
  Future<Decimal?> getRate(String from, String to) async {
    if (from == to) return Decimal.one;
    final rates = await _getRates();
    if (rates == null || rates.isEmpty) return null;
    return _crossRate(rates, from.toUpperCase(), to.toUpperCase());
  }

  /// Sync rates from Supabase now and store to cache.
  /// Call once on app startup (non-blocking – errors are swallowed).
  Future<void> syncRates() async {
    try {
      final fresh = await _fetchFromSupabase();
      if (fresh != null && fresh.isNotEmpty) {
        _memCache = fresh;
        await _persist(fresh);
      }
    } catch (_) {
      // Sync is best-effort; offline users will use cached rates.
    }
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  Future<Map<String, Decimal>?> _getRates() async {
    if (_memCache != null) return _memCache;

    // Try Supabase first (if online)
    try {
      final fresh = await _fetchFromSupabase();
      if (fresh != null && fresh.isNotEmpty) {
        _memCache = fresh;
        await _persist(fresh);
        return _memCache;
      }
    } catch (_) {}

    // Fall back to local cache
    final cached = await _loadCache();
    _memCache = cached;
    return cached;
  }

  Future<Map<String, Decimal>?> _fetchFromSupabase() async {
    if (_client == null) return null;
    final rows = await _client
        .from('exchange_rates')
        .select('target_currency, rate')
        .eq('base_currency', 'USD') as List;

    if (rows.isEmpty) return null;
    final map = <String, Decimal>{};
    for (final row in rows) {
      final r = row as Map<String, dynamic>;
      final target = (r['target_currency'] as String).toUpperCase();
      final rate = Decimal.tryParse(r['rate'].toString());
      if (rate != null && rate > Decimal.zero) {
        map[target] = rate;
      }
    }
    return map;
  }

  /// Compute cross-rate from stored USD-based rates.
  /// 1 USD = fromRate [from], 1 USD = toRate [to]
  /// 1 [from] = toRate / fromRate [to]
  Decimal? _crossRate(Map<String, Decimal> rates, String from, String to) {
    if (from == 'USD') return rates[to];
    if (to == 'USD') {
      final fromRate = rates[from];
      if (fromRate == null || fromRate == Decimal.zero) return null;
      return (Decimal.one / fromRate).toDecimal(scaleOnInfinitePrecision: 10);
    }
    final fromRate = rates[from];
    final toRate = rates[to];
    if (fromRate == null || fromRate == Decimal.zero || toRate == null) return null;
    return (toRate / fromRate).toDecimal(scaleOnInfinitePrecision: 10);
  }

  Future<void> _persist(Map<String, Decimal> rates) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(rates.map((k, v) => MapEntry(k, v.toString())));
      await prefs.setString(_cacheKey, encoded);
      await prefs.setInt(_cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
  }

  Future<Map<String, Decimal>> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString(_cacheKey);
      if (json == null) return {};
      final raw = jsonDecode(json) as Map<String, dynamic>;
      return raw.map((k, v) {
        final rate = Decimal.tryParse(v.toString()) ?? Decimal.zero;
        return MapEntry(k, rate);
      });
    } catch (_) {
      return {};
    }
  }
}

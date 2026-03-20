import 'package:shared_preferences/shared_preferences.dart';

/// Persists dashboard analytics widget order and visibility.
///
/// Pattern: direct [SharedPreferences.getInstance] — consistent with
/// [CurrencyService], [DateFormatService], [NotificationService], etc.
class DashboardPreferencesService {
  DashboardPreferencesService._();

  static const String _orderKey = 'analytics_widget_order';

  /// Default widget order when no preference has been saved.
  static const List<String> defaultOrder = [
    kTileDonut,
    kTileTrend,
    kTileQuickStats,
  ];

  static Future<List<String>> loadOrder() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_orderKey);
    if (raw == null || raw.isEmpty) return List.of(defaultOrder);
    // Guard: ensure any new default tiles present in defaultOrder but absent
    // from the saved list are appended (forward-compat for future tile additions).
    final result = List<String>.from(raw);
    for (final id in defaultOrder) {
      if (!result.contains(id)) result.add(id);
    }
    return result;
  }

  static Future<void> saveOrder(List<String> order) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_orderKey, order);
  }
}

/// Tile IDs for analytics chart widgets on the dashboard.
const String kTileDonut      = 'categories_donut';
const String kTileTrend      = 'net_trend_line';
const String kTileQuickStats = 'quick_stats_row';

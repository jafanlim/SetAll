import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Matches the keys in regional_screen.dart
const String _kDateFmtKey = 'regional_date_format';
const String _kManualFmt  = 'regional_manual_override';

/// App-wide date formatting service.
/// Call [DateFormatService.instance.format(dateTime)] anywhere in the UI
/// to get a consistently formatted date string that respects the user's
/// Regional Settings preference.
class DateFormatService {
  DateFormatService._();
  static final DateFormatService instance = DateFormatService._();

  // Cached so widgets don't hit SharedPreferences on every build.
  String _pattern = 'dd/MM/yyyy';
  bool   _loaded  = false;

  /// Load (or reload) prefs. Call once at app start and after the user
  /// changes their regional setting.
  Future<void> reload() async {
    final p = await SharedPreferences.getInstance();
    final manual   = p.getBool(_kManualFmt)    ?? false;
    final manualFmt = p.getString(_kDateFmtKey) ?? 'DD/MM/YYYY';

    if (manual) {
      _pattern = _toIntlPattern(manualFmt);
    } else {
      _pattern = _systemPattern();
    }
    _loaded = true;
  }

  /// Synchronously returns a formatted date string.
  /// If prefs haven't been loaded yet, returns EU-style as safe default.
  String format(DateTime dt) {
    return DateFormat(_pattern).format(dt.toLocal());
  }

  /// Full timestamp: date + time.
  String formatWithTime(DateTime dt) {
    return DateFormat('$_pattern  HH:mm').format(dt.toLocal());
  }

  /// Short: e.g. "14 Mar" (no year, always unambiguous).
  String formatShort(DateTime dt) {
    return DateFormat('d MMM').format(dt.toLocal());
  }

  /// Medium: e.g. "14 Mar 2025".
  String formatMedium(DateTime dt) {
    return DateFormat('d MMM yyyy').format(dt.toLocal());
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  String _toIntlPattern(String token) {
    switch (token) {
      case 'MM/DD/YYYY': return 'MM/dd/yyyy';
      case 'YYYY-MM-DD': return 'yyyy-MM-dd';
      default:           return 'dd/MM/yyyy'; // DD/MM/YYYY
    }
  }

  /// Derives the correct date field order from the intl locale data rather
  /// than a hardcoded country list. DateFormat.yMd() returns the locale's
  /// actual short-date skeleton (e.g. "M/d/y" for en_US, "d/M/y" for en_GB,
  /// "y-MM-dd" for ja). We inspect the position of 'M' vs 'd' vs 'y' in that
  /// skeleton to determine the canonical order.
  String _systemPattern() {
    try {
      final localeStr = WidgetsBinding.instance.platformDispatcher.locale.toString();
      final skeleton  = DateFormat.yMd(localeStr).pattern ?? '';
      final mPos = skeleton.indexOf('M');
      final dPos = skeleton.indexOf('d');
      final yPos = skeleton.indexOf('y');
      if (yPos >= 0 && yPos < mPos && yPos < dPos) return 'yyyy-MM-dd'; // YMD (ja, zh, ko)
      if (mPos >= 0 && dPos >= 0 && mPos < dPos) return 'MM/dd/yyyy';   // MDY (en_US, etc.)
    } catch (_) {}
    return 'dd/MM/yyyy'; // DMY safe default (en_GB, en_GE, en_NZ, etc.)
  }

  bool get isLoaded => _loaded;
}

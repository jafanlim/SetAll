import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _regionChannel = MethodChannel('com.setall.app/region');

// Matches the keys in regional_screen.dart
const String _kDateFmtKey  = 'regional_date_format';
const String _kManualFmt   = 'regional_manual_override';
const String _kTimeFmtKey  = 'regional_time_format';   // '24h' | '12h'
const String _kManualTime  = 'regional_manual_time_override';

/// App-wide date formatting service.
/// Call [DateFormatService.instance.format(dateTime)] anywhere in the UI
/// to get a consistently formatted date string that respects the user's
/// Regional Settings preference.
class DateFormatService {
  DateFormatService._();
  static final DateFormatService instance = DateFormatService._();

  // Cached so widgets don't hit SharedPreferences on every build.
  String _pattern     = 'dd/MM/yyyy';
  String _timePattern = 'HH:mm'; // 24h default
  bool   _loaded      = false;

  /// Load (or reload) prefs. Call once at app start and after the user
  /// changes their regional setting.
  Future<void> reload() async {
    final p = await SharedPreferences.getInstance();
    final manual    = p.getBool(_kManualFmt)    ?? false;
    final manualFmt = p.getString(_kDateFmtKey) ?? 'DD/MM/YYYY';

    if (manual) {
      _pattern = _toIntlPattern(manualFmt);
    } else {
      _pattern = await _systemPatternAsync();
    }

    final manualTime   = p.getBool(_kManualTime)   ?? false;
    final timeFmtToken = p.getString(_kTimeFmtKey) ?? '24h';
    if (manualTime) {
      _timePattern = timeFmtToken == '12h' ? 'h:mm a' : 'HH:mm';
    } else {
      _timePattern = await _systemTimePatternAsync();
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
    return DateFormat('$_pattern  $_timePattern').format(dt.toLocal());
  }

  /// Time only.
  String formatTimeOnly(DateTime dt) {
    return DateFormat(_timePattern).format(dt.toLocal());
  }

  /// Whether the current effective time format is 24-hour.
  bool get is24Hour => !_timePattern.contains('a');

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

  /// Async version: on macOS queries the region locale via platform channel
  /// (Locale.current.identifier), which reflects System Settings → Region
  /// independently of the preferred language. Falls back to the intl-skeleton
  /// approach on other platforms.
  /// Detects system 24h/12h preference.
  /// macOS encodes this in the locale extension: @hours=h23 (24h) or @hours=h12 (12h).
  /// Falls back to locale-driven detection via intl.
  Future<String> _systemTimePatternAsync() async {
    String? localeStr;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      try {
        localeStr = await _regionChannel.invokeMethod<String>('getRegionLocale');
      } catch (_) {}
    }
    localeStr ??= WidgetsBinding.instance.platformDispatcher.locale.toString();
    // Check for explicit @hours= ICU extension
    final hoursMatch = RegExp(r'[@;]hours=(h\d+)', caseSensitive: false)
        .firstMatch(localeStr);
    if (hoursMatch != null) {
      final h = hoursMatch.group(1)!.toLowerCase();
      // h23 / h24 → 24-hour; h12 / h11 → 12-hour
      return (h == 'h23' || h == 'h24') ? 'HH:mm' : 'h:mm a';
    }
    // Fallback: use intl to ask what jm() skeleton looks like
    try {
      final skeleton = DateFormat.jm(localeStr).pattern ?? '';
      if (skeleton.contains('a') || skeleton.contains('h')) return 'h:mm a';
    } catch (_) {}
    return 'HH:mm'; // 24h safe default
  }

  Future<String> _systemPatternAsync() async {
    String? localeStr;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) {
      try {
        localeStr = await _regionChannel.invokeMethod<String>('getRegionLocale');
      } catch (_) {}
    }
    localeStr ??= WidgetsBinding.instance.platformDispatcher.locale.toString();
    return _patternFromLocale(localeStr);
  }

  /// Determines date field order from a locale identifier string.
  /// Priority:
  ///   1. Country code from locale (e.g. "GE" from "en_GE" or "ka_GE") —
  ///      most reliable when region locale comes from the platform channel.
  ///   2. intl skeleton fallback for language-only locales (e.g. "ja", "zh").
  ///   3. DMY safe default.
  static String _patternFromLocale(String localeStr) {
    // macOS appends an ICU region extension: e.g. "en_US@rg=gezzzz"
    // where "ge" is the ISO 3166-1 country code for Georgia.
    // Extract it first — it overrides the locale's own country code.
    String? regionCountry;
    final rgMatch = RegExp(r'[@;]rg=([a-z]{2})zzzz', caseSensitive: false)
        .firstMatch(localeStr);
    if (rgMatch != null) {
      regionCountry = rgMatch.group(1)!.toUpperCase(); // e.g. "GE"
    }

    // Normalise separator: macOS may use underscore or hyphen
    final normalised = localeStr.replaceAll('-', '_').split('@').first;
    final parts = normalised.split('_');

    // Country code: prefer @rg region extension, then locale's own country code
    final country = regionCountry ?? (parts.length >= 2 ? parts[1].toUpperCase() : '');
    final lang    = parts.first.toLowerCase();

    // Country-code-driven lookup (covers cases like en_GE where intl falls
    // back to en → MDY, but the actual region format for GE is DMY)
    const mdyCountries = {'US', 'CA', 'PH', 'MH', 'FM', 'PR', 'AS', 'GU', 'VI', 'MP'};
    const ymdLanguages = {'ja', 'zh', 'ko', 'mn', 'hu'};

    if (country.isNotEmpty) {
      if (mdyCountries.contains(country)) return 'MM/dd/yyyy';
      // For all other countries (GE, GB, NZ, AU, DE, FR, RU, etc.) → DMY
      if (country.length == 2) return 'dd/MM/yyyy';
    }

    // Language-only fallback (e.g. "ja", "zh", "ko" with no country code)
    if (ymdLanguages.contains(lang)) return 'yyyy-MM-dd';

    // intl skeleton as last resort
    try {
      final skeleton = DateFormat.yMd(localeStr).pattern ?? '';
      final mPos = skeleton.indexOf('M');
      final dPos = skeleton.indexOf('d');
      final yPos = skeleton.indexOf('y');
      if (yPos >= 0 && yPos < mPos && yPos < dPos) return 'yyyy-MM-dd';
      if (mPos >= 0 && dPos >= 0 && mPos < dPos)   return 'MM/dd/yyyy';
    } catch (_) {}

    return 'dd/MM/yyyy';
  }

  bool get isLoaded => _loaded;
}

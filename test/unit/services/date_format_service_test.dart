import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

// ignore_for_file: depend_on_referenced_packages
// We import the source file to reach @visibleForTesting members.
import 'package:setall/core/services/date_format_service.dart';

void main() {
  group('_patternFromLocale', () {
    // ── spec 3.1: exact acceptance cases ──────────────────────────────────

    test('en_GE → dd/MM/yyyy (English language, Georgia region)', () {
      expect(
        DateFormatService.patternFromLocale('en_GE'),
        'dd/MM/yyyy',
      );
    });

    test('en_US → MM/dd/yyyy (English language, United States region)', () {
      expect(
        DateFormatService.patternFromLocale('en_US'),
        'MM/dd/yyyy',
      );
    });

    test('en_US@rg=gezzzz → dd/MM/yyyy (ICU region override wins)', () {
      expect(
        DateFormatService.patternFromLocale('en_US@rg=gezzzz'),
        'dd/MM/yyyy',
      );
    });

    test('ka_GE → dd/MM/yyyy (Georgian language, Georgia region)', () {
      expect(
        DateFormatService.patternFromLocale('ka_GE'),
        'dd/MM/yyyy',
      );
    });

    test('ja → yyyy-MM-dd (Japanese, no country code → language fallback)', () {
      expect(
        DateFormatService.patternFromLocale('ja'),
        'yyyy-MM-dd',
      );
    });

    // ── YMD countries carrying a country code (reachable on iOS/Android once
    //    the region channel is wired) — country short-circuit must NOT force
    //    DMY. Regression guard for the ja_JP=dd/MM/yyyy latent bug. ──────────
    test('ja_JP → yyyy-MM-dd (Japan region, not DMY)', () {
      expect(DateFormatService.patternFromLocale('ja_JP'), 'yyyy-MM-dd');
    });

    test('zh_CN → yyyy-MM-dd (China region)', () {
      expect(DateFormatService.patternFromLocale('zh_CN'), 'yyyy-MM-dd');
    });

    test('ko_KR → yyyy-MM-dd (Korea region)', () {
      expect(DateFormatService.patternFromLocale('ko_KR'), 'yyyy-MM-dd');
    });

    test('en_US@rg=jpzzzz → yyyy-MM-dd (ICU region override to Japan)', () {
      expect(
        DateFormatService.patternFromLocale('en_US@rg=jpzzzz'),
        'yyyy-MM-dd',
      );
    });

    test('empty string → safe default (does not throw)', () {
      final result = DateFormatService.patternFromLocale('');
      // Empty string has no country code and no recognised language →
      // falls through to the intl skeleton try/catch, which fails,
      // → returns the safe default 'dd/MM/yyyy'.
      expect(result, isNotEmpty);
      expect(result, isA<String>());
      // Documented default
      expect(result, 'dd/MM/yyyy');
    });

    // ── bonus: hyphen separator (Android-style, e.g. "en-GE") ──────────

    test('en-GE (hyphen separator) → dd/MM/yyyy', () {
      expect(
        DateFormatService.patternFromLocale('en-GE'),
        'dd/MM/yyyy',
      );
    });

    test('en-US (hyphen separator) → MM/dd/yyyy', () {
      expect(
        DateFormatService.patternFromLocale('en-US'),
        'MM/dd/yyyy',
      );
    });
  });

  group('12h/24h detection with region-bearing identifier', () {
    // ── spec 3.2: jm() skeleton fallback path works with en_GE ─────────

    setUpAll(() async {
      // DateFormat.jm() needs locale data initialised for non-default locales.
      await initializeDateFormatting('en_GE');
      await initializeDateFormatting('en_GB');
    });

    test('en_GE → jm() skeleton resolves without throwing', () {
      // This mimics the fallback path in _systemTimePatternAsync:
      // no @hours= extension → falls through to DateFormat.jm(localeStr).
      final skeleton = DateFormat.jm('en_GE').pattern;
      expect(skeleton, isNotNull);
      expect(skeleton, isNotEmpty);
      // en_GE resolves to a skeleton (the exact 12h/24h result depends on
      // the CLDR data bundled with intl). The key assertion is that the
      // region-bearing identifier does not throw and the result is usable.
    });

    test('en_US → jm() skeleton resolves with am/pm (12h)', () {
      // en_US locale data is bundled — no explicit init needed.
      final skeleton = DateFormat.jm('en_US').pattern;
      expect(skeleton, isNotNull);
      expect(skeleton, isNotEmpty);
      expect(skeleton!.contains('a'), isTrue,
          reason: 'US (en_US) should resolve to 12h time skeleton, got: $skeleton');
    });

    test('en_GB → jm() skeleton resolves without throwing (24h)', () {
      final skeleton = DateFormat.jm('en_GB').pattern;
      expect(skeleton, isNotNull);
      expect(skeleton, isNotEmpty);
      expect(skeleton!.contains('a'), isFalse,
          reason: 'UK (en_GB) should resolve to 24h time skeleton, got: $skeleton');
    });
  });
}

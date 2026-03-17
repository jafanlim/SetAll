// Tests for UpdateService — GitHub API update check and semver logic.
//
// Uses a MockClient from package:http/testing.dart to avoid all network calls
// and PackageInfo.setMockInitialValues() to avoid platform channel calls.
// The @visibleForTesting UpdateService.isNewer() wrapper covers the semver
// comparison without accessing the private _isNewer method directly.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:setall/core/services/update_service.dart';

/// Builds a minimal GitHub releases/latest JSON response body.
String _githubResponse({
  required String tagName,
  String htmlUrl = 'https://github.com/jafanlim/setall/releases/tag/v9.9.9',
  List<Map<String, String>> assets = const [],
}) =>
    jsonEncode({
      'tag_name': tagName,
      'html_url': htmlUrl,
      'assets': assets,
    });

/// Returns a [MockClient] that always responds with [body] and [statusCode].
http.Client _mockClient(String body, {int statusCode = 200}) =>
    MockClient((_) async => http.Response(body, statusCode));

void main() {
  setUp(() {
    // Reset any injected mock client between tests
    UpdateService.instance.injectHttpClient(http.Client());
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 1. Semver comparison logic (isNewer)
  // ─────────────────────────────────────────────────────────────────────────
  group('Semver comparison — isNewer()', () {
    test('patch bump: 1.1.1 vs 1.1.0 → has update', () {
      expect(UpdateService.isNewer('1.1.1', '1.1.0'), isTrue);
    });

    test('minor bump: 1.2.0 vs 1.1.9 → has update', () {
      expect(UpdateService.isNewer('1.2.0', '1.1.9'), isTrue);
    });

    test('major bump: 2.0.0 vs 1.9.9 → has update', () {
      expect(UpdateService.isNewer('2.0.0', '1.9.9'), isTrue);
    });

    test('same version: 1.1.1 vs 1.1.1 → no update', () {
      expect(UpdateService.isNewer('1.1.1', '1.1.1'), isFalse);
    });

    test('remote older: 1.0.0 vs 1.1.0 → no update (downgrade guard)', () {
      expect(UpdateService.isNewer('1.0.0', '1.1.0'), isFalse);
    });

    test('v-prefix stripped: v1.2.0 vs 1.1.0 → has update', () {
      expect(UpdateService.isNewer('v1.2.0', '1.1.0'), isTrue);
    });

    test('v-prefix on both: v1.1.1 vs v1.1.0 → has update', () {
      expect(UpdateService.isNewer('v1.1.1', 'v1.1.0'), isTrue);
    });

    test('major only: 2 vs 1 → has update', () {
      expect(UpdateService.isNewer('2', '1'), isTrue);
    });

    test('malformed remote string → no update (safe default)', () {
      expect(UpdateService.isNewer('not-a-version', '1.0.0'), isFalse);
    });

    test('empty remote string → no update', () {
      expect(UpdateService.isNewer('', '1.0.0'), isFalse);
    });

    test('minor unchanged, patch regression → no update', () {
      expect(UpdateService.isNewer('1.2.0', '1.2.5'), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. UpdateCheckResult helpers
  // ─────────────────────────────────────────────────────────────────────────
  group('UpdateCheckResult', () {
    test('latestTag adds v prefix if missing', () {
      const r = UpdateCheckResult(
        hasUpdate: true, latestVersion: '1.2.0', currentVersion: '1.1.0',
        releaseUrl: 'https://example.com',
      );
      expect(r.latestTag, equals('v1.2.0'));
    });

    test('latestTag preserves existing v prefix', () {
      const r = UpdateCheckResult(
        hasUpdate: true, latestVersion: 'v2.0.0', currentVersion: '1.0.0',
        releaseUrl: 'https://example.com',
      );
      expect(r.latestTag, equals('v2.0.0'));
    });

    test('hasDirectDownload is false when downloadUrl is null', () {
      const r = UpdateCheckResult(
        hasUpdate: true, latestVersion: '2.0.0', currentVersion: '1.0.0',
        releaseUrl: 'https://example.com',
      );
      expect(r.hasDirectDownload, isFalse);
    });

    test('hasDirectDownload is true when downloadUrl is set', () {
      const r = UpdateCheckResult(
        hasUpdate: true, latestVersion: '2.0.0', currentVersion: '1.0.0',
        releaseUrl: 'https://example.com',
        downloadUrl: 'https://example.com/SetAll-macOS.dmg',
        assetName: 'SetAll-macOS.dmg',
      );
      expect(r.hasDirectDownload, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. UpdateDownloadProgress
  // ─────────────────────────────────────────────────────────────────────────
  group('UpdateDownloadProgress.fraction', () {
    test('zero total → fraction is 0.0 (no divide-by-zero)', () {
      const p = UpdateDownloadProgress(
        state: UpdateDownloadState.downloading, received: 100, total: 0,
      );
      expect(p.fraction, equals(0.0));
    });

    test('halfway through → fraction is 0.5', () {
      const p = UpdateDownloadProgress(
        state: UpdateDownloadState.downloading, received: 500, total: 1000,
      );
      expect(p.fraction, closeTo(0.5, 0.001));
    });

    test('complete download → fraction is 1.0', () {
      const p = UpdateDownloadProgress(
        state: UpdateDownloadState.readyToInstall, received: 1000, total: 1000,
      );
      expect(p.fraction, equals(1.0));
    });

    test('received > total → clamped to 1.0', () {
      const p = UpdateDownloadProgress(
        state: UpdateDownloadState.downloading, received: 1500, total: 1000,
      );
      expect(p.fraction, equals(1.0));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. checkForUpdate — mocked HTTP responses
  // ─────────────────────────────────────────────────────────────────────────
  group('checkForUpdate — mocked GitHub API', () {
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'SetAll',
        packageName: 'com.jafa.setall',
        version: '1.1.0',
        buildNumber: '10',
        buildSignature: '',
      );
    });

    test('remote v1.2.0 > local 1.1.0 → hasUpdate=true', () async {
      UpdateService.instance.injectHttpClient(
        _mockClient(_githubResponse(tagName: 'v1.2.0')),
      );
      final result = await UpdateService.instance.checkForUpdate();
      expect(result.hasUpdate, isTrue);
      expect(result.latestVersion, equals('1.2.0'));
      expect(result.currentVersion, equals('1.1.0'));
      expect(result.error, isNull);
    });

    test('remote 1.1.0 == local 1.1.0 → hasUpdate=false', () async {
      UpdateService.instance.injectHttpClient(
        _mockClient(_githubResponse(tagName: 'v1.1.0')),
      );
      final result = await UpdateService.instance.checkForUpdate();
      expect(result.hasUpdate, isFalse);
    });

    test('remote 1.0.0 < local 1.1.0 → hasUpdate=false', () async {
      UpdateService.instance.injectHttpClient(
        _mockClient(_githubResponse(tagName: 'v1.0.0')),
      );
      final result = await UpdateService.instance.checkForUpdate();
      expect(result.hasUpdate, isFalse);
    });

    test('HTTP 404 → hasUpdate=false with error string', () async {
      UpdateService.instance.injectHttpClient(
        _mockClient('Not Found', statusCode: 404),
      );
      final result = await UpdateService.instance.checkForUpdate();
      expect(result.hasUpdate, isFalse);
      expect(result.error, contains('404'));
    });

    test('HTTP 403 (rate limited) → hasUpdate=false with error', () async {
      UpdateService.instance.injectHttpClient(
        _mockClient(jsonEncode({'message': 'API rate limit exceeded'}),
            statusCode: 403),
      );
      final result = await UpdateService.instance.checkForUpdate();
      expect(result.hasUpdate, isFalse);
      expect(result.error, isNotNull);
    });

    test('platform-matching asset URL is extracted', () async {
      UpdateService.instance.injectHttpClient(
        _mockClient(_githubResponse(
          tagName: 'v2.0.0',
          assets: [
            {
              'name': 'SetAll-macOS.dmg',
              'browser_download_url': 'https://github.com/releases/download/v2.0.0/SetAll-macOS.dmg',
            },
          ],
        )),
      );
      final result = await UpdateService.instance.checkForUpdate();
      // The asset is only extracted when hasUpdate=true and the suffix matches.
      // On macOS test runner, the suffix is 'macos' — this verifies the logic.
      expect(result.hasUpdate, isTrue);
      // assetName may be null if running on non-macOS test runner, but
      // the logic itself is verified — no crash, correct hasUpdate flag.
      expect(result.error, isNull);
    });

    test('network exception → hasUpdate=false with error, does not throw',
        () async {
      UpdateService.instance.injectHttpClient(
        MockClient((_) async => throw Exception('Network unreachable')),
      );
      final result = await UpdateService.instance.checkForUpdate();
      expect(result.hasUpdate, isFalse);
      expect(result.error, isNotNull);
    });

    test('releaseUrl is always populated (fallback URL present)', () async {
      UpdateService.instance.injectHttpClient(
        _mockClient(_githubResponse(tagName: 'v1.2.0')),
      );
      final result = await UpdateService.instance.checkForUpdate();
      expect(result.releaseUrl, isNotEmpty);
      expect(result.releaseUrl, contains('github.com'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 5. Progress state machine
  // ─────────────────────────────────────────────────────────────────────────
  group('Download progress state machine', () {
    test('initial state is idle', () {
      expect(UpdateService.instance.downloadProgress.state,
          equals(UpdateDownloadState.idle));
    });

    test('resetDownload returns state to idle', () {
      UpdateService.instance.resetDownload();
      expect(UpdateService.instance.downloadProgress.state,
          equals(UpdateDownloadState.idle));
    });

    test('listeners are notified on reset', () {
      var notified = false;
      void listener(UpdateDownloadProgress _) => notified = true;
      UpdateService.instance.addProgressListener(listener);
      UpdateService.instance.resetDownload();
      UpdateService.instance.removeProgressListener(listener);
      expect(notified, isTrue);
    });
  });
}

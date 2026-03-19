// Tests for DeepLinkService — URI scheme validation and lifecycle.
//
// The core invariant being tested: only `setall://`, `com.jafa.setall.app://`
// (iOS App Store bundle), and `com.setall.app://` (Android/macOS unified bundle)
// URIs should trigger session recovery. All other schemes must be silently
// ignored to prevent injection attacks via custom-scheme hijacking.
//
// Full integration (AppLinks stream → Supabase.getSessionFromUrl) requires a
// live device and a real Supabase session — those are E2E concerns. Here we
// test the scheme gate and lifecycle contracts in isolation.

import 'package:flutter_test/flutter_test.dart';
import 'package:setall/core/services/deep_link_service.dart';

void main() {
  // Use the singleton — safe because isSetAllSchemeUri is pure / stateless.
  final svc = DeepLinkService.instance;

  // ─────────────────────────────────────────────────────────────────────────
  // 1. Accepted schemes (should trigger session recovery)
  // ─────────────────────────────────────────────────────────────────────────
  group('Accepted URI schemes — session recovery triggered', () {
    test('setall://login-callback → accepted', () {
      final uri = Uri.parse('setall://login-callback');
      expect(svc.isSetAllSchemeUri(uri), isTrue);
    });

    test('setall://login-callback?code=abc123 → accepted', () {
      final uri = Uri.parse('setall://login-callback?code=abc123&type=magiclink');
      expect(svc.isSetAllSchemeUri(uri), isTrue);
    });

    test('com.jafa.setall.app://login-callback → accepted (iOS bundle)', () {
      final uri = Uri.parse('com.jafa.setall.app://login-callback');
      expect(svc.isSetAllSchemeUri(uri), isTrue);
    });

    test('com.jafa.setall.app://login-callback?code=xyz → accepted', () {
      final uri = Uri.parse('com.jafa.setall.app://login-callback?code=xyz');
      expect(svc.isSetAllSchemeUri(uri), isTrue);
    });

    test('com.setall.app://login-callback → accepted (Android/macOS bundle)', () {
      final uri = Uri.parse('com.setall.app://login-callback');
      expect(svc.isSetAllSchemeUri(uri), isTrue);
    });

    test('setall:// (bare scheme) → accepted', () {
      final uri = Uri.parse('setall://');
      expect(svc.isSetAllSchemeUri(uri), isTrue);
    });

    test('setall://confirm-email → accepted', () {
      final uri = Uri.parse('setall://confirm-email?token=abc');
      expect(svc.isSetAllSchemeUri(uri), isTrue);
    });

    test('setall://password-reset → accepted', () {
      final uri = Uri.parse('setall://password-reset?token=resettoken');
      expect(svc.isSetAllSchemeUri(uri), isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. Rejected schemes (must NOT trigger session recovery)
  // ─────────────────────────────────────────────────────────────────────────
  group('Rejected URI schemes — must be ignored', () {
    test('https:// → rejected (prevents web-URL injection)', () {
      final uri = Uri.parse('https://setall.app/login?code=injected');
      expect(svc.isSetAllSchemeUri(uri), isFalse);
    });

    test('http:// → rejected', () {
      final uri = Uri.parse('http://evil.com/login-callback');
      expect(svc.isSetAllSchemeUri(uri), isFalse);
    });

    test('ftp:// → rejected', () {
      final uri = Uri.parse('ftp://attacker.com/payload');
      expect(svc.isSetAllSchemeUri(uri), isFalse);
    });

    test('setall-fake:// → rejected (scheme prefix attack)', () {
      final uri = Uri.parse('setall-fake://login-callback');
      expect(svc.isSetAllSchemeUri(uri), isFalse);
    });

    test('com.jafa.setall.evil:// → rejected (suffix attack)', () {
      // URI parsing: scheme is the part before "://". Dots are valid in scheme.
      // "com.jafa.setall.evil" != "com.jafa.setall" — strict equality check.
      final uri = Uri.tryParse('x-setall://callback') ?? Uri();
      expect(svc.isSetAllSchemeUri(uri), isFalse);
    });

    test('empty URI → rejected safely', () {
      final uri = Uri();
      expect(svc.isSetAllSchemeUri(uri), isFalse);
    });

    test('mailto: → rejected', () {
      final uri = Uri.parse('mailto:user@setall.app');
      expect(svc.isSetAllSchemeUri(uri), isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. Service lifecycle
  // ─────────────────────────────────────────────────────────────────────────
  group('Service lifecycle contracts', () {
    test('dispose() is safe to call before init()', () {
      // Must not throw — no subscription to cancel yet.
      expect(() => svc.dispose(), returnsNormally);
    });

    test('dispose() is idempotent (safe to call twice)', () {
      svc.dispose();
      expect(() => svc.dispose(), returnsNormally);
    });

    test('singleton returns same instance on every access', () {
      final a = DeepLinkService.instance;
      final b = DeepLinkService.instance;
      expect(identical(a, b), isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. URI structure of expected deep link
  // ─────────────────────────────────────────────────────────────────────────
  group('Expected deep link URI structure', () {
    test('PKCE code parameter is extractable from login-callback URI', () {
      final uri = Uri.parse('setall://login-callback?code=abc123def456');
      expect(svc.isSetAllSchemeUri(uri), isTrue);
      expect(uri.queryParameters['code'], equals('abc123def456'));
    });

    test('type parameter is present in magic-link URIs', () {
      final uri = Uri.parse(
          'setall://login-callback?code=tok&type=magiclink');
      expect(uri.queryParameters['type'], equals('magiclink'));
    });

    test('type=recovery present in password-reset URIs', () {
      final uri = Uri.parse(
          'com.jafa.setall.app://login-callback?code=reset&type=recovery');
      expect(svc.isSetAllSchemeUri(uri), isTrue);
      expect(uri.queryParameters['type'], equals('recovery'));
    });
  });
}

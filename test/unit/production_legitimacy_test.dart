// Production legitimacy audit tests.
//
// Verifies that critical production artifacts are present and correctly
// configured before deployment:
//   1. google-site-verification.html exists in web/
//   2. HSTS and CSP headers are configured in netlify.toml
//   3. sitemap.xml contains all public routes
//   4. Physical address footer is present across ALL 9 public pages

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Resolves the project root by walking up from the test file location.
String get _projectRoot {
  // When run via `flutter test`, CWD is the project root.
  return Directory.current.path;
}

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // 1. Google Site Verification
  // ─────────────────────────────────────────────────────────────────────────
  group('Google site verification', () {
    test('google-site-verification HTML file exists in web/', () {
      final file = File('$_projectRoot/web/google46e219ce7d6f8562.html');
      expect(file.existsSync(), isTrue,
          reason: 'Google site verification file must be in web/ for Search Console');
    });

    test('verification file contains the expected token', () {
      final file = File('$_projectRoot/web/google46e219ce7d6f8562.html');
      final content = file.readAsStringSync();
      expect(content, contains('google-site-verification'),
          reason: 'File must contain the verification token string');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. HSTS and CSP headers in netlify.toml
  // ─────────────────────────────────────────────────────────────────────────
  group('Netlify security headers', () {
    late String netlifyToml;

    setUp(() {
      netlifyToml = File('$_projectRoot/netlify.toml').readAsStringSync();
    });

    test('HSTS header is present with preload directive', () {
      expect(netlifyToml, contains('Strict-Transport-Security'),
          reason: 'HSTS header must be defined in netlify.toml');
      expect(netlifyToml, contains('max-age=31536000'),
          reason: 'HSTS max-age must be at least 1 year');
      expect(netlifyToml, contains('includeSubDomains'),
          reason: 'HSTS must include subdomains');
      expect(netlifyToml, contains('preload'),
          reason: 'HSTS must include preload directive');
    });

    test('CSP header is present with upgrade-insecure-requests', () {
      expect(netlifyToml, contains('Content-Security-Policy'),
          reason: 'CSP header must be defined');
      expect(netlifyToml, contains('upgrade-insecure-requests'),
          reason: 'CSP must enforce upgrade-insecure-requests');
    });

    test('X-Frame-Options is DENY', () {
      expect(netlifyToml, contains('X-Frame-Options'),
          reason: 'X-Frame-Options must be defined');
      expect(netlifyToml, contains('DENY'),
          reason: 'X-Frame-Options must be DENY to prevent clickjacking');
    });

    test('X-Content-Type-Options is nosniff', () {
      expect(netlifyToml, contains('X-Content-Type-Options'),
          reason: 'X-Content-Type-Options must be defined');
      expect(netlifyToml, contains('nosniff'),
          reason: 'Must prevent MIME type sniffing');
    });

    test('headers apply to all routes (/*)', () {
      expect(netlifyToml, contains('for = "/*"'),
          reason: 'Security headers must apply to all routes');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. Sitemap completeness
  // ─────────────────────────────────────────────────────────────────────────
  group('Sitemap completeness', () {
    late String sitemap;

    setUp(() {
      sitemap = File('$_projectRoot/web/sitemap.xml').readAsStringSync();
    });

    test('sitemap is valid XML with urlset root', () {
      expect(sitemap, contains('<urlset'));
      expect(sitemap, contains('</urlset>'));
    });

    test('sitemap contains all required public routes', () {
      final requiredRoutes = [
        'https://setall.app/',
        'https://setall.app/download',
        'https://setall.app/privacy',
        'https://setall.app/terms',
      ];
      for (final route in requiredRoutes) {
        expect(sitemap, contains('<loc>$route</loc>'),
            reason: 'Sitemap must include $route');
      }
    });

    test('homepage has priority 1.0', () {
      // Check that the root URL entry has priority 1.0
      final homeMatch = RegExp(
        r'<url>\s*<loc>https://setall\.app/</loc>.*?<priority>1\.0</priority>.*?</url>',
        dotAll: true,
      );
      expect(homeMatch.hasMatch(sitemap), isTrue,
          reason: 'Homepage must have priority 1.0');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4. Physical address footer on ALL public pages
  // ───────────────────────────────────────────────────────────────────────────
  group('Physical address footer — all 9 public pages', () {
    const address = 'SetAll Fintech Systems | 56 Tbilisi-Kojori st, Tbilisi, Georgia';

    // index.html is NOT the source web/index.html (that became the Flutter dev
    // entry in PR #52). `make build-web` deploys "new website/landing page.html"
    // as build/web/index.html, so validate the ACTUAL deploy source for the home page.
    String pagePath(String page) => page == 'index.html'
        ? '$_projectRoot/new website/landing page.html'
        : '$_projectRoot/web/$page';

    void checkPage(String htmlFile) {
      final html = File(pagePath(htmlFile)).readAsStringSync();
      expect(html, contains('SetAll Fintech Systems'),
          reason: '$htmlFile: business entity name must appear in footer');
      expect(html, contains('56 Tbilisi-Kojori st'),
          reason: '$htmlFile: physical address must appear in footer');
      expect(html, contains('Tbilisi, Georgia'),
          reason: '$htmlFile: city and country must appear in footer');
    }

    test('index.html has physical address',         () => checkPage('index.html'));
    test('login.html has physical address',         () => checkPage('login.html'));
    test('portal.html has physical address',        () => checkPage('portal.html'));
    test('insights.html has physical address',      () => checkPage('insights.html'));
    test('privacy.html has physical address',       () => checkPage('privacy.html'));
    test('terms.html has physical address',         () => checkPage('terms.html'));
    test('support.html has physical address',       () => checkPage('support.html'));
    test('download.html has physical address',      () => checkPage('download.html'));
    test('reset-password.html has physical address',() => checkPage('reset-password.html'));

    test('address string is identical across all pages', () {
      // Checks the canonical form appears in every page (no typo variants).
      for (final page in [
        'index.html', 'login.html', 'portal.html', 'insights.html',
        'privacy.html', 'terms.html', 'support.html',
        'download.html', 'reset-password.html',
      ]) {
        final html = File(pagePath(page)).readAsStringSync();
        expect(html, contains(address),
            reason: '$page: address must be the canonical string: "$address"');
      }
    });
  });
}

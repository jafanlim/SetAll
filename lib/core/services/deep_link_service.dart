import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../router/app_router.dart';

/// Listens for incoming [setall://] deep links on Windows (and mobile) so that
/// after a Google OAuth or email-confirmation redirect the app catches the
/// auth code and exchanges it for a live Supabase session.
///
/// Also handles in-app navigation deep links (e.g. from the iOS home widget)
/// such as [com.jafa.setall.app://wallet/add] and [com.jafa.setall.app://add-expense].
///
/// Usage — call [DeepLinkService.instance.init()] once in [main.dart] after
/// Supabase has been initialised.
class DeepLinkService {
  DeepLinkService._();
  static final DeepLinkService instance = DeepLinkService._();

  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _sub;

  // Deduplication: FlutterDeepLinkingEnabled causes the same navigation URI
  // to arrive via app_links stream more than once (once from our handler, once
  // from Flutter's own GoRouter deep-link processing). Ignore repeats within
  // _dedupWindow to prevent pushing the same screen twice.
  String? _lastNavUri;
  DateTime? _lastNavTime;
  static const _dedupWindow = Duration(milliseconds: 1000);

  /// Start listening for deep links.
  /// Safe to call multiple times — subsequent calls are no-ops.
  Future<void> init() async {
    if (_sub != null) return;
    if (kIsWeb) return; // Web handles redirects via URL fragment; no-op here.

    try {
      // Handle the link that cold-started the app (if any).
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        await _handleUri(initialUri);
      }

      // Listen for links while the app is already running (warm start).
      _sub = _appLinks.uriLinkStream.listen(
        _handleUri,
        onError: (Object err) {
          if (kDebugMode) debugPrint('[DeepLinkService] stream error: $err');
        },
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[DeepLinkService] init error: $e');
    }
  }

  /// Dispatch an incoming URI.
  ///
  /// - URIs with a `code` query param → Supabase PKCE auth exchange.
  /// - URIs with a recognisable navigation path → GoRouter navigation.
  /// - Everything else is silently ignored.
  Future<void> _handleUri(Uri uri) async {
    if (kDebugMode) debugPrint('[DeepLinkService] incoming link: $uri');

    if (!isSetAllSchemeUri(uri)) return;

    // ── Auth callback (PKCE) ─────────────────────────────────────────────────
    if (uri.queryParameters.containsKey('code') ||
        uri.queryParameters.containsKey('access_token')) {
      try {
        await Supabase.instance.client.auth.getSessionFromUrl(uri);
        if (kDebugMode) debugPrint('[DeepLinkService] session recovered from link');
      } on AuthException catch (e) {
        if (kDebugMode) debugPrint('[DeepLinkService] auth error: ${e.message}');
      } catch (e) {
        if (kDebugMode) debugPrint('[DeepLinkService] error handling auth link: $e');
      }
      return;
    }

    // ── In-app navigation link (e.g. from home widget buttons) ──────────────
    // Map the URI host+path to a GoRouter path.
    final nav = _uriToNavAction(uri);
    if (nav != null) {
      // Dedup: FlutterDeepLinkingEnabled fires the same URI through app_links
      // stream multiple times. Ignore repeats within the dedup window.
      final uriKey = uri.toString();
      final now = DateTime.now();
      if (_lastNavUri == uriKey &&
          _lastNavTime != null &&
          now.difference(_lastNavTime!) < _dedupWindow) {
        if (kDebugMode) debugPrint('[DeepLinkService] dedup skip: $uriKey');
        return;
      }
      _lastNavUri = uriKey;
      _lastNavTime = now;

      if (kDebugMode) debugPrint('[DeepLinkService] navigating to ${nav.path}');
      // Delay 400 ms so FlutterDeepLinkingEnabled finishes processing the
      // incoming URI before we replace the stack. Without this, Flutter's own
      // GoRouter deep-link push lands after ours, creating a duplicate page.
      final ctx = AppRouter.navigatorKey.currentContext;
      if (ctx == null) return;
      final router = GoRouter.of(ctx);
      Future.delayed(const Duration(milliseconds: 400), () {
        if (nav.pushFromRoot) {
          router.go('/');
          Future.microtask(() => router.push(nav.path));
        } else {
          router.go(nav.path);
        }
      });
    }
  }

  /// Maps a deep-link [Uri] to a [_NavAction], or null if unknown.
  _NavAction? _uriToNavAction(Uri uri) {
    // Triple-slash form: com.jafa.setall.app:///wallet/add
    // → uri.host = '', uri.path = '/wallet/add'  ← preferred
    // Legacy host form: com.jafa.setall.app://wallet/add
    // → uri.host = 'wallet', uri.path = '/add'
    final combined = uri.host.isEmpty
        ? uri.path
        : '/${uri.host}${uri.path}'.replaceAll('//', '/');
    return switch (combined) {
      '/wallet/add'  => _NavAction(AppRouter.walletEntryType, pushFromRoot: true),
      '/add-expense' => _NavAction(AppRouter.groupPicker,     pushFromRoot: true),
      '/wallet'      => _NavAction(AppRouter.wallet),
      '/activity'    => _NavAction(AppRouter.activity),
      // '/' (dashboard root / widgetURL body tap) is intentionally NOT mapped:
      // FlutterDeepLinkingEnabled fires this URI on every widget body tap and
      // after our own navigation (e.g. post-save go('/wallet')), so handling it
      // here would reset the nav bar to Dashboard unexpectedly.
      _              => null,
    };
  }

  /// Cancel the stream subscription (call on app disposal if needed).
  void dispose() {
    _sub?.cancel();
    _sub = null;
  }

  /// Returns true if [uri] uses the SetAll custom scheme.
  /// Exposed for unit tests without requiring a live Supabase connection.
  @visibleForTesting
  bool isSetAllSchemeUri(Uri uri) =>
      uri.scheme == 'setall' || uri.scheme == 'com.setall.app' || uri.scheme == 'com.jafa.setall.app';
}

class _NavAction {
  const _NavAction(this.path, {this.pushFromRoot = false});
  final String path;
  final bool pushFromRoot;
}

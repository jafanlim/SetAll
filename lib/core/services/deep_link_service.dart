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
    final path = _uriToRoutePath(uri);
    if (path != null) {
      if (kDebugMode) debugPrint('[DeepLinkService] navigating to $path');
      // Use the navigator key to push without a BuildContext.
      final ctx = AppRouter.navigatorKey.currentContext;
      if (ctx != null) {
        GoRouter.of(ctx).go(path);
      }
    }
  }

  /// Maps a deep-link [Uri] to a GoRouter path string, or null if unknown.
  String? _uriToRoutePath(Uri uri) {
    // The widget uses host-style paths: com.jafa.setall.app://wallet/add
    // → uri.host = 'wallet', uri.path = '/add'   (or uri.path = 'add')
    // Build a combined path from host + path.
    final combined = '/${uri.host}${uri.path}'.replaceAll('//', '/');
    return switch (combined) {
      '/wallet/add'   => AppRouter.walletEntryType,
      '/add-expense'  => AppRouter.addExpense,
      '/wallet'       => AppRouter.wallet,
      '/activity'     => AppRouter.activity,
      '/'             => AppRouter.dashboard,
      _               => null,
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

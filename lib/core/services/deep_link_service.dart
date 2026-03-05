import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Listens for incoming [setall://] deep links on Windows (and mobile) so that
/// after a Google OAuth or email-confirmation redirect the app catches the
/// auth code and exchanges it for a live Supabase session.
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

  /// Exchange an incoming [setall://] URI for a Supabase session.
  Future<void> _handleUri(Uri uri) async {
    if (kDebugMode) debugPrint('[DeepLinkService] incoming link: $uri');

    // Only act on our custom scheme.
    if (uri.scheme != 'setall' && uri.scheme != 'com.jafa.setall') return;

    try {
      // Supabase PKCE flow: the redirect carries a `code` query parameter.
      // getSessionFromUrl will exchange it for tokens automatically.
      await Supabase.instance.client.auth.getSessionFromUrl(uri);
      if (kDebugMode) debugPrint('[DeepLinkService] session recovered from link');
    } on AuthException catch (e) {
      if (kDebugMode) debugPrint('[DeepLinkService] auth error: ${e.message}');
    } catch (e) {
      if (kDebugMode) debugPrint('[DeepLinkService] error handling link: $e');
    }
  }

  /// Cancel the stream subscription (call on app disposal if needed).
  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}

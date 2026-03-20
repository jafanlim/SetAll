import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:window_manager/window_manager.dart' if (dart.library.html) 'core/stubs/window_manager_stub.dart';

import 'package:firebase_core/firebase_core.dart';

import 'app.dart';
import 'firebase_options.dart';
import 'core/services/currency_sync_service.dart';
import 'core/services/date_format_service.dart';
import 'core/services/deep_link_service.dart';
import 'core/services/notification_service.dart';
import 'core/config/auth_config.dart';
import 'data/local/local_database.dart';

/// Base URL for email confirmation and OAuth redirects. Set this to your deployed web app URL (e.g. https://your-app.vercel.app) so links work on mobile. When null, web uses current origin.
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set minimum window size on desktop so the UI never breaks.
  if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux)) {
    await windowManager.ensureInitialized();
    final options = WindowOptions(
      minimumSize: const Size(800, 600),
      size: const Size(1100, 720),
      center: true,
      titleBarStyle: defaultTargetPlatform == TargetPlatform.windows
          ? TitleBarStyle.hidden
          : TitleBarStyle.hidden,
      windowButtonVisibility: defaultTargetPlatform == TargetPlatform.macOS,
    );
    await windowManager.waitUntilReadyToShow(options);
    await windowManager.show();
  }

  ErrorWidget.builder = (FlutterErrorDetails details) {
    return Directionality(
      textDirection: ui.TextDirection.ltr,
      child: Material(
        child: Container(
          color: const Color(0xFF0F0F12),
          padding: const EdgeInsets.all(24),
          child: SafeArea(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Something went wrong',
                    style: TextStyle(
                      color: Colors.red.shade300,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    details.toString(),
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  };

  // Unhandled async errors (no zone so runApp stays in same zone as bindings; avoids web "Zone mismatch").
  ui.PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    if (kDebugMode) {
      debugPrint('Uncaught error: $error');
      debugPrint(stack.toString());
    }
    return true;
  };

  await EasyLocalization.ensureInitialized();
  await initializeDateFormatting();

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('en'),
        Locale('ru'),
        Locale('ka'),
        Locale('de'),
        Locale('es'),
        Locale('fr'),
      ],
      path: 'assets/translations',
      fallbackLocale: const Locale('en'),
      child: const ProviderScope(
        child: _AppLoader(),
      ),
    ),
  );
}

/// Shows loading until DB (and optional Supabase) are ready, then SetAllApp. Avoids white screen.
class _AppLoader extends StatefulWidget {
  const _AppLoader();

  @override
  State<_AppLoader> createState() => _AppLoaderState();
}

class _AppLoaderState extends State<_AppLoader> {
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final hasSupabase = !AuthConfig.supabaseUrl.startsWith('YOUR_') && !AuthConfig.supabaseAnonKey.startsWith('YOUR_');

      if (kIsWeb) {
        // Web: Supabase only. No anonymous sign-in; user signs in with Email or Google.
        LocalDatabase.setWebMode();
        if (hasSupabase) {
          // Implicit flow on web: email confirmation links work cross-device
          // because GoTrue returns tokens in #fragment (no client-side
          // PKCE verifier required). Mobile uses PKCE via _initSupabase().
          await Supabase.initialize(url: AuthConfig.supabaseUrl, anonKey: AuthConfig.supabaseAnonKey, authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.implicit));
          // Recover session when user lands from email confirmation or OAuth (e.g. on iPhone opening link).
          await _recoverSessionFromUrlIfNeeded();
        }
      } else {
        // Mobile/desktop: init DB and Supabase in parallel for faster startup.
        await Future.wait([
          LocalDatabase.instance,
          if (hasSupabase) _initSupabase() else Future<void>.value(),
        ]);
      }
      // Load date format preference before UI renders.
      await DateFormatService.instance.reload();

      // Initialise Firebase (graceful no-op if GoogleService-Info.plist /
      // google-services.json not yet added) then request push permission.
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        if (!kIsWeb) unawaited(NotificationService.instance.init());
      } catch (_) {
        // Firebase not configured yet — skip silently.
      }

      if (mounted) setState(() => _ready = true);

      // Sync exchange rates in background after UI is ready (non-blocking).
      // This keeps the Supabase exchange_rates table as a local cache for
      // offline-first rate lookups without delaying startup.
      _backgroundSyncRates();
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('Init error: $e');
        debugPrint(st.toString());
      }
      String message = e.toString();
      if (message.contains('anonymous_provider_disabled')) {
        message = 'Anonymous sign-in is disabled in your Supabase project.\n\n'
            'Enable it in the Supabase dashboard: Authentication → Providers → Anonymous (turn on), then reload the app.';
      }
      if (mounted) setState(() => _error = message);
    }
  }

  Future<void> _initSupabase() async {
    await Supabase.initialize(
      url: AuthConfig.supabaseUrl,
      anonKey: AuthConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
    // Start listening for setall:// deep links (Windows OAuth / email redirects).
    await DeepLinkService.instance.init();
  }

  /// Kick off a background rate sync. Errors are swallowed – the app has a
  /// SharedPreferences cache from the previous session as fallback.
  void _backgroundSyncRates() {
    Future.microtask(() async {
      try {
        final client = Supabase.instance.client;
        await CurrencySyncService(client: client).syncRates();
      } catch (_) {}
    });
  }

  /// On web, recover auth session when user lands from email confirmation or OAuth redirect.
  Future<void> _recoverSessionFromUrlIfNeeded() async {
    if (!kIsWeb) return;
    try {
      final uri = Uri.base;
      final hasCode        = uri.queryParameters.containsKey('code');
      final hasAccessToken = uri.fragment.contains('access_token');
      final hasError       = uri.fragment.contains('error');
      if (!hasCode && !hasAccessToken && !hasError) return;

      debugPrint('[Auth] Recovering session from URL: $uri');
      await Supabase.instance.client.auth.getSessionFromUrl(uri);
      debugPrint('[Auth] Session recovered');

      // After email confirmation, mark registration_complete so the router
      // doesn't block the user. Only do this for email/password users
      // (provider == 'email') — Google OAuth users must go through the
      // register screen instead.
      final user = Supabase.instance.client.auth.currentUser;
      final isEmailUser = user?.appMetadata['provider'] == 'email';
      if (user != null && isEmailUser) {
        await Supabase.instance.client
            .from('profiles')
            .update({'registration_complete': true})
            .eq('id', user.id);
        debugPrint('[Auth] registration_complete set for email user ${user.id}');
      }
    } catch (e) {
      debugPrint('[Auth] getSessionFromUrl failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Directionality(
        textDirection: ui.TextDirection.ltr,
        child: Material(
          child: Container(
            color: const Color(0xFF0F0F12),
            padding: const EdgeInsets.all(24),
            alignment: Alignment.center,
            child: SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Setup failed', style: TextStyle(color: Colors.red.shade300, fontSize: 18)),
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.white70, fontSize: 12), softWrap: true),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (!_ready) {
      return Directionality(
        textDirection: ui.TextDirection.ltr,
        child: Material(
          child: Container(
            color: const Color(0xFF0F0F12),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Colors.white54),
                const SizedBox(height: 16),
                Text('Loading…', style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 16)),
              ],
            ),
          ),
        ),
      );
    }
    return const SetAllApp();
  }
}

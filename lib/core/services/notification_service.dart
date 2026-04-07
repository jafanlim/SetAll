import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String _kFcmToken = 'push_fcm_token';

/// Determines current platform label for fcm_tokens.platform column.
String _currentPlatform() {
  if (kIsWeb) return 'web';
  switch (defaultTargetPlatform) {
    case TargetPlatform.android: return 'android';
    case TargetPlatform.iOS:     return 'ios';
    case TargetPlatform.macOS:   return 'macos';
    case TargetPlatform.windows: return 'windows';
    default:                     return 'web';
  }
}

/// Handles push permission, FCM token lifecycle, and syncs tokens to
/// the Supabase [fcm_tokens] table on login.
///
/// Usage:
///   await NotificationService.instance.init();          // at app start
///   await NotificationService.instance.syncToSupabase(); // after sign-in
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  bool _initialized = false;

  /// Initialise once after [Firebase.initializeApp].
  /// Requests permission on iOS / macOS / web, fetches the FCM token,
  /// and wires up refresh + foreground-message handlers.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;

      // ── 1. Request permission (iOS / macOS / web) ───────────────────────
      final settings = await messaging.requestPermission(
        alert:         true,
        badge:         true,
        sound:         true,
        announcement:  false,
        carPlay:       false,
        criticalAlert: false,
        provisional:   false,
      );

      if (kDebugMode) {
        debugPrint(
          '[Notifications] Permission: ${settings.authorizationStatus}',
        );
      }

      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // ── 2. On iOS, wait for APNS token before requesting FCM token ───────
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        try {
          final apns = await messaging.getAPNSToken();
          if (apns == null) {
            if (kDebugMode) debugPrint('[Notifications] APNS token not yet available (simulator?)');
            return;
          }
        } catch (e) {
          if (kDebugMode) debugPrint('[Notifications] APNS token fetch failed: $e');
          return;
        }
      }

      // ── 3. Fetch and persist FCM token ──────────────────────────────────
      final token = await messaging.getToken();
      if (token != null) {
        await _persistToken(token);
      }

      // ── 4. Token refresh — re-persist and re-sync ───────────────────────
      messaging.onTokenRefresh.listen((newToken) async {
        await _persistToken(newToken);
        await syncToSupabase(token: newToken);
      });

      // ── 5. Foreground message handler ───────────────────────────────────
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          debugPrint(
            '[Notifications] Foreground: ${message.notification?.title}',
          );
        }
      });

      // ── 6. Background / terminated tap handler ───────────────────────────
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        if (kDebugMode) {
          debugPrint('[Notifications] Opened from: ${message.notification?.title}');
        }
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[Notifications] Not configured: $e');
    }
  }

  /// Upserts the current device FCM token to the [fcm_tokens] Supabase table.
  /// Safe to call multiple times — uses ON CONFLICT upsert.
  /// Pass [token] to avoid a redundant SharedPreferences read.
  Future<void> syncToSupabase({String? token}) async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;

      final fcmToken = token ?? await getToken();
      if (fcmToken == null) return;

      await client.from('fcm_tokens').upsert(
        {
          'user_id':    uid,
          'token':      fcmToken,
          'platform':   _currentPlatform(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'user_id, token',
      );

      if (kDebugMode) debugPrint('[Notifications] FCM token synced to Supabase');
    } catch (e) {
      // Non-fatal — sync retried on next app start.
      if (kDebugMode) debugPrint('[Notifications] Supabase sync failed: $e');
    }
  }

  /// Removes this device's FCM token from Supabase on sign-out.
  Future<void> removeFromSupabase() async {
    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;

      final fcmToken = await getToken();
      if (fcmToken == null) return;

      await client
          .from('fcm_tokens')
          .delete()
          .eq('user_id', uid)
          .eq('token', fcmToken);

      if (kDebugMode) debugPrint('[Notifications] FCM token removed from Supabase');
    } catch (e) {
      if (kDebugMode) debugPrint('[Notifications] Supabase token remove failed: $e');
    }
  }

  /// Returns the locally-stored FCM token, or null if unavailable.
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kFcmToken);
  }

  Future<void> _persistToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFcmToken, token);
    if (kDebugMode) debugPrint('[Notifications] FCM token: $token');
  }
}

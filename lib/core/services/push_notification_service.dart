import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kFcmToken = 'push_fcm_token';

/// Handles push notification permission request and FCM token management.
/// Gracefully degrades when Firebase is not yet configured.
class PushNotificationService {
  PushNotificationService._();
  static final PushNotificationService instance = PushNotificationService._();

  bool _initialized = false;

  /// Call once at app start (after Firebase.initializeApp).
  /// Requests permission on iOS / macOS if not already granted.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final messaging = FirebaseMessaging.instance;

      // ── 1. Request permission (iOS / macOS / web) ──────────────────────
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
          '[PushNotifications] Permission: ${settings.authorizationStatus}',
        );
      }

      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // ── 2. Fetch and persist FCM token ──────────────────────────────────
      final token = await messaging.getToken();
      if (token != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kFcmToken, token);
        if (kDebugMode) debugPrint('[PushNotifications] FCM token: $token');
      }

      // ── 3. Handle token refresh ─────────────────────────────────────────
      messaging.onTokenRefresh.listen((newToken) async {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kFcmToken, newToken);
        if (kDebugMode) {
          debugPrint('[PushNotifications] FCM token refreshed: $newToken');
        }
      });

      // ── 4. Foreground message handler ───────────────────────────────────
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        if (kDebugMode) {
          debugPrint(
            '[PushNotifications] Foreground message: ${message.notification?.title}',
          );
        }
        // TODO: show in-app banner (e.g. via flutter_local_notifications)
      });
    } catch (e) {
      // Firebase not configured yet — silently skip push setup.
      if (kDebugMode) {
        debugPrint('[PushNotifications] Not configured: $e');
      }
    }
  }

  /// Returns the stored FCM token, or null if unavailable.
  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kFcmToken);
  }
}

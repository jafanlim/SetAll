/// Configuration class for Supabase and Authentication credentials.
/// 
/// IMPORTANT: Never commit actual API keys to a public GitHub repository.
/// For a production app, these should eventually be moved to environment variables (.env).
library;

import 'package:flutter/foundation.dart';

/// Returns the correct OAuth redirect URL for the current platform.
/// - iOS:          com.jafa.setall.app://login-callback  (App Store bundle ID)
/// - macOS/Android: com.setall.app://login-callback       (unified bundle ID)
/// - Web:          https://vrsmsgyxeyzyrdonsnrk.supabase.co/auth/v1/callback
/// All values must be registered in Supabase → Authentication → URL Configuration → Redirect URLs.
String get kAuthRedirectBaseUrl {
  if (kIsWeb) return 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/auth/v1/callback';
  if (defaultTargetPlatform == TargetPlatform.iOS) return 'com.jafa.setall.app://login-callback';
  return 'com.setall.app://login-callback';
}

class AuthConfig {
  // 1. SUPABASE CREDENTIALS
  // Go to Supabase Dashboard -> Project Settings -> API

  // ACT-config: Read from --dart-define at build time.
  // Fallback values allow plain `flutter run` in local dev without flags.

  /// Your Project URL (e.g., 'https://xyzcompany.supabase.co')
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://vrsmsgyxeyzyrdonsnrk.supabase.co',
  );

  /// Your Project Anon Public Key
  static const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'REDACTED_JWT',
  );

  // 2. OAUTH CREDENTIALS (For Phase 0: Google Sign-In)
  // You will need these from the Google Cloud Console later when setting up Google Auth.
  
  /// Web Client ID (Required for Android & Web Google Sign-in)
  static const String googleWebClientId = '708927430014-57bb6t8090nm2vq9nqgjqhi5ctli3poj.apps.googleusercontent.com';
  
  /// iOS Client ID (Required for iOS Google Sign-in)
  static const String googleIosClientId = '41197170572-cbv1qbr8m2s7hk3s2nc9delqsd55usil.apps.googleusercontent.com';

  // ARCH-01: Netlify ai-analyst endpoint — replaces Supabase edge fn (persistent 401).
  // No caller auth required — Gemini key is a Netlify env var, handled server-side.
  static const String netlifyAiUrl =
      'https://setall.app/.netlify/functions/ai-analyst';
}
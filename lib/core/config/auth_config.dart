/// Configuration class for Supabase and Authentication credentials.
/// 
/// IMPORTANT: Never commit actual API keys to a public GitHub repository.
/// For a production app, these should eventually be moved to environment variables (.env).
library;

/// Deep link callback URL for mobile OAuth (Google Sign-In) and email confirmation redirects.
/// Must match exactly what is registered in Supabase Dashboard → Authentication → URL Configuration → Redirect URLs.
/// iOS keeps the old bundle ID scheme (com.jafa.setall.app) to match the existing App Store listing.
/// Android and macOS use the unified scheme (com.setall.app).
const String kAuthRedirectBaseUrl = 'com.jafa.setall.app://login-callback';

class AuthConfig {
  // 1. SUPABASE CREDENTIALS
  // Go to Supabase Dashboard -> Project Settings -> API
  
  /// Your Project URL (e.g., 'https://xyzcompany.supabase.co')
  static const String supabaseUrl = 'https://vrsmsgyxeyzyrdonsnrk.supabase.co';

  /// Your Project Anon Public Key
  static const String supabaseAnonKey = 'REDACTED_JWT';

  // 2. OAUTH CREDENTIALS (For Phase 0: Google Sign-In)
  // You will need these from the Google Cloud Console later when setting up Google Auth.
  
  /// Web Client ID (Required for Android & Web Google Sign-in)
  static const String googleWebClientId = '73119302557-gflq85m9dg3jklmkeh2fjc9hpks4l2sl.apps.googleusercontent.com';
  
  /// iOS Client ID (Required for iOS Google Sign-in)
  static const String googleIosClientId = '73119302557-95k1njr3tt4mg2o2htl86eosjbf780kv.apps.googleusercontent.com';
}
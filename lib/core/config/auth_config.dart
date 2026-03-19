/// Configuration class for Supabase and Authentication credentials.
/// 
/// IMPORTANT: Never commit actual API keys to a public GitHub repository.
/// For a production app, these should eventually be moved to environment variables (.env).
library;

/// Deep link callback URL for mobile OAuth (Google Sign-In) and email confirmation redirects.
/// Must match exactly what is registered in Supabase Dashboard → Authentication → URL Configuration → Redirect URLs.
const String kAuthRedirectBaseUrl = 'com.setall.app://login-callback';

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
  static const String googleWebClientId = '454096661669-qrko5vmk5gk4pels4n0k1o0lnuehubnj.apps.googleusercontent.com';
  
  /// iOS Client ID (Required for iOS Google Sign-in)
  static const String googleIosClientId = '454096661669-2lmum0pt14jvtj8jq6b3hn8fm2qilcuh.apps.googleusercontent.com';
}
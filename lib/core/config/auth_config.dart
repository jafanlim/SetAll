/// Configuration class for Supabase and Authentication credentials.
/// 
/// IMPORTANT: Never commit actual API keys to a public GitHub repository.
/// For a production app, these should eventually be moved to environment variables (.env).
library;

/// Base URL for auth redirects (email confirmation, OAuth). Set to your app's URL for mobile, e.g. https://your-app.vercel.app
const String? kAuthRedirectBaseUrl = null;

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
  static const String googleWebClientId = 'YOUR_GOOGLE_WEB_CLIENT_ID_HERE';
  
  /// iOS Client ID (Required for iOS Google Sign-in)
  static const String googleIosClientId = 'YOUR_GOOGLE_IOS_CLIENT_ID_HERE';
}
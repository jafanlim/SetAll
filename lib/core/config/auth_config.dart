/// Configuration class for Supabase and Authentication credentials.
/// 
/// IMPORTANT: Never commit actual API keys to a public GitHub repository.
/// For a production app, these should eventually be moved to environment variables (.env).
library;

/// Deep link callback URL for mobile OAuth (Google Sign-In) and email confirmation redirects.
/// Must match exactly what is registered in Supabase Dashboard → Authentication → URL Configuration → Redirect URLs.
const String kAuthRedirectBaseUrl = 'com.jafa.setall://login-callback';

class AuthConfig {
  // 1. SUPABASE CREDENTIALS
  // Go to Supabase Dashboard -> Project Settings -> API
  
  /// Your Project URL (e.g., 'https://xyzcompany.supabase.co')
  static const String supabaseUrl = 'https://vrsmsgyxeyzyrdonsnrk.supabase.co';

  /// Your Project Anon Public Key
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InZyc21zZ3l4ZXl6eXJkb25zbnJrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzE0MTQ0MDAsImV4cCI6MjA4Njk5MDQwMH0.Ptbo5t5e6_v5rOGKmG3uYAURqx5b9QtnhFxgPcqtlHA';

  // 2. OAUTH CREDENTIALS (For Phase 0: Google Sign-In)
  // You will need these from the Google Cloud Console later when setting up Google Auth.
  
  /// Web Client ID (Required for Android & Web Google Sign-in)
  static const String googleWebClientId = 'YOUR_GOOGLE_WEB_CLIENT_ID_HERE';
  
  /// iOS Client ID (Required for iOS Google Sign-in)
  static const String googleIosClientId = 'YOUR_GOOGLE_IOS_CLIENT_ID_HERE';
}
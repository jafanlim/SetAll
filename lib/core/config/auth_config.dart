/// Base URL for email confirmation and OAuth redirects.
/// Set this to your deployed web app URL (e.g. https://your-app.vercel.app) so that:
/// - Email confirmation links open your app (not localhost) when clicked on mobile.
/// - Google sign-in redirects back to your app.
/// When null, the web app uses the current origin (works when already on production).
const String? kAuthRedirectBaseUrl = null;

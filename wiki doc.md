📘 SetAll – Official Project Documentation

Welcome to the official wiki for SetAll, an intelligent, cross-platform personal finance and net-worth tracking application. SetAll is engineered to bridge the gap between complex financial data and actionable intelligence, combining a beautiful, highly responsive UI with deep AI-driven insights to provide users with a truly comprehensive, 360-degree view of their financial health.

Unlike traditional budgeting apps that focus solely on historical spending, SetAll serves as a forward-looking financial co-pilot. It tracks shared group expenses, personal wallet income/expenses, and provides AI-powered spending analysis.

🚀 Overview

SetAll is built using the Flutter framework to provide a high-performance, single-codebase experience across iOS, macOS, Android, and Web environments. By utilizing a shared Dart logic layer and platform-specific channels where necessary (such as for macOS region locale detection and native biometric authentication via local_auth), the application ensures that complex financial calculations and AI interactions remain completely consistent regardless of the user's chosen device.

The application ecosystem leverages:
- Supabase as the primary backend (auth, database, storage, edge functions, and real-time sync)
- Firebase for push notifications (FCM) and crash reporting (Crashlytics) only
- Riverpod 2.x for reactive state management and dependency injection
- Netlify Functions to host the Gemini AI proxy, air-gapping API keys from the client
- SQLite (sqflite) for local offline caching

✨ Key Features

Unified Dashboard: A single-pane-of-glass view that aggregates Total Net Worth, liquid Cash Positions, real-time AI Insights, and Categorical Spending Trends into a prioritized feed. The dashboard uses a ListView inside a RefreshIndicator with widgets ordered by hierarchy of importance: _MasterNetWorthHero → _NavCard (Cash Position / Shared Expenses) → _AiInsightCard → _CompactAnalyticsSection (charts). Color-coded visual hierarchy (teal for positive, orange for negative) guides user attention.

AI Financial Insights: Context-aware, personalized financial summaries generated via Supabase Edge Functions that proxy to a Netlify Function (netlify/functions/ai-analyst.js). Two Gemini models are used:
- Chat mode: gemini-2.5-flash-lite (conversational, 1024 tokens)
- Canvas mode: gemini-2.5-flash (deep analysis with structured JSON + charts, 8192 tokens)
The Gemini API key is stored as a Netlify environment variable, never exposed to the client. The provider detects empty states (no transactions) and offline conditions before making any network call.

Offline-First & Cloud Sync: SetAll uses a "Local-First" data strategy. All transactions and edits are committed to a local SQLite database (sqflite) immediately, ensuring low-latency user inputs and allowing the app to function offline. A background SyncService (lib/core/services/sync_service.dart) handles bidirectional synchronization with Supabase, implementing conflict resolution to ensure data integrity across multiple devices.

Cross-Platform Auth: Implements Google Sign-In via Supabase OAuth (signInWithOAuth(OAuthProvider.google)) with platform-aware redirect URLs:
- macOS/Android: com.setall.app://login-callback
- iOS: com.jafa.setall.app://login-callback (legacy App Store bundle ID)
- Web: Supabase callback URL (https://vrsmsgyxeyzyrdonsnrk.supabase.co/auth/v1/callback)
The authentication flow is hardened for macOS App Sandboxing with com.apple.security.network.client and keychain-access-groups entitlements. Note: The native google_sign_in package is NOT used — all auth goes through Supabase.

Responsive Layouts: Uses an AdaptiveShell (lib/core/layout/adaptive_shell.dart) that provides:
- < 600dp: BottomNavigationBar (mobile)
- 600–900dp: NavigationRail compact (tablet)
- > 900dp: NavigationRail expanded (desktop)
The dashboard uses FittedBox for the hero net worth amount to handle long currency strings (JPY, IDR) gracefully. flutter_screenutil (base 390x844) provides responsive scaling.

Localization & Global Formatting: Fully localized (i18n) support for 6 languages (EN, DE, RU, KA, FR, ES), handled via JSON translation files and the easy_localization package (NOT ARB files). The app includes a DateFormatService that auto-detects system locale via a macOS platform channel and parses ICU extensions (@hours=h23 for time format, @rg=XXzzzz for region). Users can manually override date format (DD/MM/YYYY, MM/DD/YYYY, YYYY-MM-DD) and time format (24h/12h) in Regional Settings.

🏗 System Architecture

1. State Management (Riverpod)

SetAll utilizes Riverpod 2.x (flutter_riverpod ^2.6.1) for state management and dependency injection.

Provider Types in Use:
- FutureProvider.autoDispose — for AI insights, analytics data, balance calculations
- Provider — for repository, sync service, and currency service singletons
- StateNotifierProvider — for theme mode
- Notifier/NotifierProvider — for desktop-specific state (selected group)
- StreamProvider — for real-time wallet/expense updates from SQLite

Note: No AsyncNotifier is used. AI insights use a plain FutureProvider.autoDispose with no keepAlive() or timer-based cache. The provider is invalidated on app init (after sync) and on pull-to-refresh. Standard Riverpod autoDispose caching applies while the dashboard widget is mounted.

Resilient Error Boundaries: The application utilizes AsyncValue.when() patterns to handle loading and error states at the component level. The AI card handles 4 distinct states: empty (sentinel), offline (sentinel), loading (animated pulse), error (rethrown → calm message). All states render within a fixed-height SizedBox to prevent layout jumps.

2. Backend & Data Layer

Supabase (Primary): Acts as the remote source of truth for all data — auth, profiles, expenses, groups, splits, exchange rates, and file storage. Row Level Security (RLS) policies enforce per-user data isolation. The Supabase project URL is https://vrsmsgyxeyzyrdonsnrk.supabase.co.

SQLite (Local): sqflite provides the local offline cache. The SetAllRepository (lib/data/repositories/setall_repository.dart, ~3500+ lines) manages all CRUD operations against both SQLite and Supabase, with SyncService coordinating bidirectional sync.

Firebase (Limited): Used ONLY for:
- Push notifications via Firebase Messaging (firebase_messaging ^15.1.3)
- Firebase project: setall-app-prod
Firebase is NOT used for auth, database, or storage.

Supabase Edge Functions: The app calls client.functions.invoke('ai-analyst') to reach a Supabase Edge Function, which proxies to the Netlify Function (netlify/functions/ai-analyst.js). Additional Supabase Edge Functions exist: notify-group-invite, send-email, send-welcome-email, sync-exchange-rates.

Netlify Function (AI Proxy): Hosts the Gemini API call with proper Content-Type: application/json headers, 429 rate-limit handling with retry-after parsing, and structured response parsing. The Gemini API key is stored as a Netlify environment variable.

3. UI/UX Paradigms

Dashboard Architecture: The Dashboard is built with a standard ListView inside a RefreshIndicator — NOT Slivers. The AppBar is a standard AppBar with scrolledUnderElevation: 0.5. Content widgets are laid out sequentially: Hero → NavCards → AI Card → Analytics Charts. This is adequate for the current widget count but could be migrated to Slivers if performance issues arise.

Monetary Integrity: Floating-point math (IEEE 754) is avoided for all internal balance arithmetic. SetAll uses the Dart decimal package (^3.0.1) for exact precision. The AmountFormatter (lib/core/utils/amount_formatter.dart) provides:
- decimalPlacesFor(currency): 0dp for JPY/KRW/VND etc., 2dp for standard fiat, 6dp for crypto
- formatAmountForCurrency(raw, currency): formats with smart trailing zero trimming
- All monetary values stored as Decimal in the repository layer
Note: No "MonetaryGuard" utility exists. Precision is enforced by AmountFormatter and Decimal arithmetic throughout the repository.

🛠 Developer Setup & Guide

Prerequisites

Flutter SDK: Dart SDK ^3.11.0. Always run flutter doctor -v to verify the environment.

Native Tooling: Xcode 15+ for iOS/macOS builds. Android Studio for Android builds.

Supabase CLI: Required for deploying edge functions and running migrations (supabase functions deploy, supabase db push).

CocoaPods: Managed via pod install in the ios and macos directories.

Running the App

# Clean the environment and fetch the latest dependencies
flutter clean && flutter pub get

# Navigate to native directories to update podfiles if required
cd macos && pod install --repo-update && cd ..

# Run the macOS debug build (The primary development target)
flutter run -d macos --debug

# Run the iOS Simulator for mobile-specific gesture testing
flutter run -d ios

# Perform a full project analysis (must show "No issues found!")
flutter analyze

# Run the full test suite (must show "All tests passed!")
flutter test


Authentication Configuration

Auth uses Supabase OAuth (NOT the native google_sign_in package):

macOS Entitlements: Verify com.apple.security.network.client is enabled in both macos/Runner/DebugProfile.entitlements and Release.entitlements. Also required: keychain-access-groups, photos-library, network.server, files.user-selected.read-only.

Keychain Sharing: The keychain group must be correctly set in Xcode project capabilities.

URL Schemes: The OAuth redirect is platform-aware:
- macOS/Android: com.setall.app://login-callback
- iOS: com.jafa.setall.app://login-callback
- Web: https://vrsmsgyxeyzyrdonsnrk.supabase.co/auth/v1/callback
These must be registered in Supabase Dashboard → Authentication → URL Configuration → Redirect URLs AND in the Google Cloud Console credentials.

🧪 Testing & Edge Cases

Current Test Suite: 265 unit tests, all passing. flutter analyze reports zero issues.

Before pushing to main, manually verify the "SetAll Four":

The Empty Slate (Cold Start): Sign in with no data. The AI card should show dashboard.ai_empty_state ("Start tracking your spending — AI insights unlock once you have transactions.") — no broken charts, no API call made.

The Tunnel Test (Offline Resilience): Disable connectivity. The AI card should immediately show dashboard.ai_offline with a wifi_off icon. Transactions should save to local SQLite and sync when back online.

The Swiss Franc Test (Visual Overflow): Set base currency to JPY or IDR with a large balance. The _MasterNetWorthHero uses FittedBox(scaleDown) to prevent text overflow. _NavCard values use TextOverflow.ellipsis. Verify neither clips.

The Timezone Shift (Chronological Integrity): Create a transaction at 11:30 PM, change timezone 3 hours ahead. Verify the dashboard respects the UTC timestamp from Supabase rather than shifting to the wrong day.

📦 Release Management

SetAll uses a strictly incrementing build number system. Current: version: 1.4.1+16 in pubspec.yaml.

Version Bump: Increment the build number for every archive attempt. Follow Semantic Versioning (Major.Minor.Patch+Build).

Git Tags: Tag every production release:
git tag -a v1.4.1 -m "Production Release 1.4.1 (Build 16)"
Note: The current v1.4.1 tag points to Build 15 (090c74a). HEAD (881ff97) is 16 commits ahead and should be re-tagged before the next App Store submission.

The Archive Workflow: In Xcode, select Product → Archive targeting "Any iOS Device (arm64)". Verify dSYM symbols, Entitlements, and App Privacy declarations in the Xcode Organizer before uploading to App Store Connect.
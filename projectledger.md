🗃 SetAll Project Ledger & Changelog

This ledger serves as the definitive historical record for the SetAll project, tracking major architectural shifts, strategic pivots, completed development phases, and rigorous version history. It is designed to provide context for future audits, ensure team alignment on core system logic, and maintain a high standard of accountability for all engineering decisions.

🏆 Current Version: v1.4.1+16

Status: App Store Connect Ready / Production Stable / Internal Gold Master

Date: March 19, 2026

Commit Hash: 881ff97 (main)

Tag: v1.4.1 at 090c74a (Build 15 — App Store archive). HEAD is Build 16 (16 commits ahead of tag).

🟢 PHASE 5.12.1: Layout & Dashboard Revolution

Objective: Defragment the user experience by merging distinct, isolated UI components into a cohesive, responsive master dashboard. This phase specifically targeted the elimination of navigation friction and resolved critical "system fringe" overlap issues on high-resolution iPad and macOS displays, where fixed layouts previously failed to adapt to dynamic safe areas.

Navigation Refactor & UX Consolidation:

Action: Removed the standalone "Analytics" tab from the navigation destinations in AdaptiveShell (lib/core/layout/adaptive_shell.dart). The shell provides a BottomNavigationBar on mobile (<600dp) and a NavigationRail on tablet/desktop (600dp+).

Rationale: Moving analytics into the dashboard feed transformed metrics from a separate "destination" into contextual ambient data, reducing cognitive load.

Implementation Detail: Updated go_router route definitions and navigation index logic to remain consistent after the Analytics index removal. AdaptiveShell now manages 4 destinations (Dashboard, Wallet, Groups, Settings) via GoRouter shell routing — no IndexedStack is used.

View Merging & Information Density:

Action: Integrated "Trends" (Historical Line Charts via fl_chart) and "Category Distribution" (Multi-segment Donut Charts) directly into the Dashboard scroll view as _CompactAnalyticsSection.

Placement Strategy: Positioned below the primary _MasterNetWorthHero and _NavCard summary widgets, following a "Hierarchy of Importance" pattern.

Aesthetics: Applied a unified design language using GlassCard widgets with consistent 16px corner radius and themed gradients.

Dashboard Scroll Architecture:

Implementation: The Dashboard uses a standard ListView inside a RefreshIndicator (dashboard_screen.dart line 167-179). This provides smooth scrolling with native pull-to-refresh. No Sliver migration was performed.

Note: A future performance optimization could migrate to CustomScrollView with Slivers if scroll jank is detected on complex chart rendering. Currently, performance is acceptable on ProMotion displays.

SafeArea & Padding: Dynamic bottom padding (96 + MediaQuery.padding.bottom) prevents content collision with system chrome and tab bars on iPads and notched macOS displays (commit 791997e).

Localization & Regional Precision Sync:

Verification: Audited all DateFormat initializers via DateFormatService (lib/core/services/date_format_service.dart). The service auto-detects system locale via a macOS platform channel (com.setall.app/region) and parses ICU extensions (@rg=XXzzzz, @hours=h23) for date and time format detection. Users can manually override both date and time formats in Regional Settings.

Note: No LocaleObserver exists in the App widget. Locale changes currently require navigating back to the dashboard or re-opening the app to take effect. Easy_localization handles runtime locale switching for translations.

🟢 PHASE 5.3: AI Insights & Cash Position

Objective: Finalize the integration of the "SetAll AI" cognitive layer and solidify the underlying financial logic to ensure absolute data resilience, numerical accuracy, and user trust in the platform's automated suggestions.

Block 4: Sensory Polish (Haptics & Time Format)

Haptic Feedback: Added HapticUtils.error() method. Integrated haptics across: amount field onChanged (lightTap), navigation bar switches (selection), AI insight arrival (success), biometric gate errors (error).

Time Format: Added 24h/12h detection via ICU @hours= extension parsing and manual override in Regional Settings. DateFormatService now exposes formatWithTime(), formatTimeOnly(), and is24Hour getter.

Block 5: Monetary Integrity & Precision

AmountFormatter Upgrade: Implemented smart decimal precision — 0dp for JPY/KRW/VND/IDR etc., 2dp for standard fiat, 6dp for crypto (BTC/ETH/SOL/etc.). Functions: decimalPlacesFor(), formatAmountForCurrency().

Balance Currency Conversion Fix: Fixed getBalanceSummary() in setall_repository.dart to convert summed USD amounts to the user's baseCurrency before returning, preventing misleading currency label mismatches.

Test Coverage: 25 unit tests covering all AmountFormatter functions (test/unit/services/amount_formatter_test.dart).

Block 6: Cash Position Pivot & AI Card

Terminology Pivot: Renamed dashboard.personal_wallet → "Cash Position" and dashboard.wallet_cash_label → "Cash Position" across all 6 locales (en/de/ru/ka/fr/es). Navigation labels and wallet screen titles intentionally unchanged.

AI Backend: The AI insight is fetched via Supabase Edge Functions (client.functions.invoke('ai-analyst')), which proxies to a Netlify Function (netlify/functions/ai-analyst.js). The Netlify function calls the Gemini API using two models:
  - Chat mode: gemini-2.5-flash-lite (temperature 0.9, 1024 tokens)
  - Canvas mode: gemini-2.5-flash (temperature 0.2, 8192 tokens)
The Gemini API key is stored as a Netlify environment variable, air-gapping it from the client.

AI Card Animation: _AiInsightCard uses a SingleTickerProviderStateMixin with AnimationController (900ms, repeating reverse, easeInOut) to pulse 3 tapering ghost bars during loading. Content area is pre-allocated at SizedBox(height: 55) to prevent layout jump. This is an inline animation in _AiInsightCardState — no separate ShimmerPulse widget exists.

Provider Architecture: _aiInsightProvider is a FutureProvider.autoDispose<String>. It has no keepAlive() or 15-minute timer cache. The provider is invalidated on: (a) app init via performFullSync callback, and (b) pull-to-refresh via ref.invalidate(_aiInsightProvider). Between those events, Riverpod's standard autoDispose caching applies while the widget is mounted.

Block 7: Stress Testing & Edge Cases (The Reliability Pass)

Empty State Intelligence:

Logic: Provider checks analyticsData.allExpenses.isEmpty && totalIncome == 0 && totalSpend == 0. If true, returns _kAiEmpty sentinel string immediately — no network call made. Card renders dashboard.ai_empty_state: "Start tracking your spending — AI insights unlock once you have transactions."

Currency Symbol & Numerical Overflow Protection:

Fix: Wrapped the _MasterNetWorthHero amount Text in FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft). The _NavCard values use TextOverflow.ellipsis (not FittedBox). Both approaches prevent visual overflow for large JPY/IDR numbers.

Connectivity Guard:

Implementation: connectivity_plus check in provider — if all results are ConnectivityResult.none, returns _kAiOffline sentinel. Card renders dashboard.ai_offline with wifi_off icon. Guarded with !kIsWeb (web has no reliable connectivity check).

Error Boundary: Provider catch block now rethrows, so Riverpod's error state correctly triggers. Card shows dashboard.ai_unavailable — fails silently with a calm message, never crashes the dashboard.

Translation Keys Added (6 locales): dashboard.ai_empty_state, dashboard.ai_offline.

🟢 PREVIOUS CRITICAL FIXES

Google Auth & Entitlements (macOS Sandbox Hardening)

Issue: Identified a critical failure in the Google OAuth flow on macOS targets, manifesting as a cryptic OSStatus 13 error. This was caused by the system sandbox blocking the incoming redirect URL after successful web-based authentication.

Resolution Path:

Entitlement Injection: Verified com.apple.security.network.client is enabled in both macos/Runner/DebugProfile.entitlements and Release.entitlements. Also enabled: photos-library, keychain-access-groups, network.server, files.user-selected.read-only.

Scheme Registration: Corrected CFBundleURLTypes in the macOS-specific Info.plist. Note: Auth uses Supabase OAuth (signInWithOAuth(OAuthProvider.google)), not the native google_sign_in package. The redirect URL is platform-aware: macOS/Android use com.setall.app, iOS uses com.jafa.setall.app, web uses the Supabase callback URL.

Persistence: Hardened the Keychain Sharing groups to ensure that the Supabase authentication token is persisted securely across app restarts within the macOS sandbox environment.

Firebase Project Migration & Build Versioning Strategy

Issue: Encountered multiple Xcode Archive upload rejections due to duplicate bundle attributes and build number collisions (Build 14 was previously used in a stale TestFlight release).

Resolution Path:

Strict Versioning: Established a mandatory versioning policy in pubspec.yaml where build numbers must increment by 1 for every archive attempt.

Deployment Sync: Updated the production target to version: 1.4.1+16 (pubspec.yaml). The v1.4.1 git tag points to Build 15 (commit 090c74a).

Infrastructure Alignment: Synchronized GoogleService-Info.plist configurations across both iOS and macOS targets for the setall-app-prod Firebase project (used for FCM push notifications and Crashlytics only — Supabase is the primary backend).

Validation: Confirmed the integrity of the final build through a successful Apple Transporter upload and subsequent verified distribution to TestFlight.

🔴 PENDING ITEMS (Not Yet Deployed)

1. Supabase Edge Function: supabase functions deploy send-welcome-email — migration SQL exists (20260314000000_welcome_email_trigger.sql) but deployment status unconfirmed.
2. Supabase DB Migration: supabase db push for the welcome email trigger — needs verification.
3. Git Tag: No tag exists for Build 16 (v1.4.1+16). Current HEAD (881ff97) is 16 commits ahead of v1.4.1 tag.

End of Ledger.
# Proposal: iOS/Android Ignore the System Region — Dates Render US-Style (MM/DD)

Status: OPEN — not started (P1, user-reported 2026-07-09, screenshots on file)
Owner: controller → workhorse
Related code: `lib/core/services/date_format_service.dart` (`_systemPatternAsync` L121–130,
`_systemTimePatternAsync` L97–119, `_patternFromLocale` L138–182),
`lib/features/settings/presentation/screens/regional_screen.dart` (`_load` L129–146),
`macos/Runner/MainFlutterWindow.swift` (the only native impl of `com.setall.app/region`)

## Why (user report + screenshots)

iPhone set to **Language: English, Region: Georgia** — iOS itself renders dates DD/MM
(`19/08/2026` in Settings → Language & Region). The app's Regional Settings shows
**"System locale: en_US · 07/10/2026"**: the region is dropped, `en` defaults to US, and every
date renders MM/DD. Directly caused the user to misread an expense date (see
`setall-expense-date-edit`).

## Findings (code-verified 2026-07-10, develop `f4d125d`)

1. **The region platform channel exists ONLY on macOS.** `com.setall.app/region` /
   `getRegionLocale` is implemented solely in `macos/Runner/MainFlutterWindow.swift`; no iOS or
   Android handler exists.
2. **Dart gates the channel to macOS too** — `date_format_service.dart` L99 & L123 and
   `regional_screen.dart` L133 check `defaultTargetPlatform == TargetPlatform.macOS`; every
   other platform falls back to `platformDispatcher.locale.toString()`, which on iOS is the
   resolved **language** locale (`en_US`) — the Region setting is not in it.
3. Downstream logic is already correct: `_patternFromLocale` prefers the locale country code,
   parses the `@rg=gezzzz` extension, maps `GE` (and all non-US-cluster) → `dd/MM/yyyy`. It
   just never receives `GE` on iOS.
4. Time format has the same gap; iOS 12h/24h currently works via the `jm()` skeleton fallback —
   verify it still resolves correctly once the channel exists.

## Proposed change

1. **iOS**: register `com.setall.app/region` in `ios/Runner/AppDelegate.swift`;
   `getRegionLocale` returns `Locale.current.identifier` (e.g. `en_GE` for language=en /
   region=GE; ICU-style identifiers with extensions on newer iOS are also parsed by
   `_patternFromLocale`).
2. **Android** (parity): same channel in `MainActivity`, returning
   `Locale.getDefault().toString()`.
3. **Dart**: widen the gate from `== TargetPlatform.macOS` to non-web mobile/desktop platforms
   with a handler (macOS ∪ iOS ∪ Android) in both `date_format_service.dart` helpers and
   `regional_screen.dart` `_load`. Keep try/catch + PlatformDispatcher fallback — platforms
   without a handler degrade exactly as today (`MissingPluginException` → catch → fallback).
4. No behaviour change on web/Windows/Linux; manual-override path untouched.

## Open decisions (controller)

- None.

## Acceptance

- Unit tests for `_patternFromLocale`: `en_GE`→`dd/MM/yyyy`, `en_US`→`MM/dd/yyyy`,
  `en_US@rg=gezzzz`→`dd/MM/yyyy`, `ka_GE`→`dd/MM/yyyy`, `ja`→`yyyy-MM-dd`.
- On-device (user's config: en + Region Georgia): Regional Settings shows `en_GE · 10/07/2026`,
  preview `DD/MM/YYYY`; lists/details flip to DD/MM.
- `flutter analyze` = 0; full suite green; native diffs additive channel registration only.

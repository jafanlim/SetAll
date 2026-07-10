# Tasks

## 1. Native channels
- [x] 1.1 iOS: `com.setall.app/region` MethodChannel in `ios/Runner/AppDelegate.swift`; `getRegionLocale` → `Locale.current.identifier`
- [x] 1.2 Android: same channel in `MainActivity`; → `Locale.getDefault().toString()`

## 2. Dart
- [x] 2.1 `date_format_service.dart`: widen macOS-only gate to macOS/iOS/Android in `_systemPatternAsync` + `_systemTimePatternAsync` (keep try/catch fallback)
- [x] 2.2 `regional_screen.dart` `_load`: same widening so the "System locale" card shows the region locale

## 3. Tests (TDD-first)
- [x] 3.1 Unit tests for `_patternFromLocale`: `en_GE`, `en_US`, `en_US@rg=gezzzz`, `ka_GE`, `ja`, empty string
- [x] 3.2 12h/24h detection still correct with a region-bearing identifier (e.g. `en_GE` → skeleton fallback path)

## 4. Gate + close-out
- [x] 4.1 `flutter analyze` = 0; full suite green; surgical diff (native = additive registration only)
- [ ] 4.2 On-device verify (user, iPhone en+Georgia): Regional Settings `en_GE`, preview DD/MM/YYYY, expense dates DD/MM
- [x] 4.3 Ledger update + tick boxes in the PR

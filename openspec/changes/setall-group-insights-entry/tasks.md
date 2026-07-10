# Tasks

## 1. Analytics screen + route
- [x] 1.1 `initialGroupId` (+ optional `groupName`) on `AnalyticsScreen` (defaults preserved — `const AnalyticsScreen()` still valid); `_AnalyticsScreenState` seeds the private `_analyticsFilterProvider` once via a guarded post-frame callback (no "provider modified during build")
- [x] 1.2 `/analytics` route reads GoRouter `extra` as `Map<String,dynamic>?` and threads `groupId`/`groupName`; no extra (nav-bar entry) ⇒ both null ⇒ default screen
- [x] 1.3 Scoped open shows the group name in the AppBar title + the active group chip; **controller fix:** seed only `groupId` (source stays `all`) — the `groupId` filter already excludes null-groupId wallet rows, so the scoped view is identical while clearing the group chip widens to the *exact* unscoped view (spec scenario "Widen scope"). DeepSeek had seeded `source: _Source.groups` on a false premise that `source: all` would leak wallet rows (`Eval-DeepSeek: failed`).

## 2. Menu entries
- [x] 2.1 "Group insights" (insights icon, teal) in `group_info_screen._showOverflowMenu` → `context.push(AppRouter.analytics, extra: {groupId, groupName})`
- [x] 2.2 Same item in the `group_detail_screen` popup menu
- [x] 2.3 i18n `groups_screen.group_insights` ×6 locales (native translations)

## 3. Tests (TDD-first) — `test/features/analytics/group_insights_entry_test.dart`
- [x] 3.1 Filter-predicate + constructor + route-extra threading + E2E: `AnalyticsScreen(initialGroupId: 'g-alice')` over a mixed set (wallet 99 + g-alice 15/5 + g-bob 25) ⇒ scoped total 20.00, wallet + g-bob excluded — guards that `source=all` does **not** leak wallet into a scoped view
- [x] 3.2 No-seed default ⇒ all rows incl. wallet aggregated (the unscoped baseline the group-chip clear widens back to). Full chip-tap widen not unit-tested (private filter/data providers + group picker needs `myGroupsProvider` seeded); flagged rather than over-built.

## 4. Gate + close-out
- [x] 4.1 `flutter analyze` = 0; full suite green (541/541); additive surgical diff (analytics_screen, app_router, both group screens, 6 locales, + test)
- [ ] 4.2 On-device verify (user): ⋮ → "Group insights" from both group info and group detail opens analytics scoped to the group; clearing the group chip widens to all

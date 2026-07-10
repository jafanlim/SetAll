# Proposal: Group Category Insights Behind the 3-Dot Menu (Dedicated Screen)

Status: OPEN — not started (P2, user-requested; the analytics engine already supports it)
Owner: controller → workhorse
Related code: `lib/features/analytics/presentation/screens/analytics_screen.dart` (group filter
implemented: `filter.groupId` L235–236, in-screen chips L621–632),
`lib/core/router/app_router.dart` (`/analytics` L237–246 — no initial filter),
`lib/features/groups/presentation/screens/group_info_screen.dart` (`_showOverflowMenu` L216+),
`lib/features/dashboard/presentation/screens/group_detail_screen.dart` (popup menu L409–418)

## Why (user report)

Category analysis of group expenses was expected weeks ago and never became reachable. Product
constraint: do **not** fill the main group info page — hide it behind the group's 3-dot menu and
open as an **additional screen**.

## Findings (code-verified 2026-07-10, develop `f4d125d`)

1. **The hard part exists.** `AnalyticsScreen` computes category totals over a group-filtered
   row set (`filter.groupId != null ? dedup.where(…)`, L235–236) with internal group chips
   (L621–632). Money is already Decimal-aggregated (PR #44 Part D).
2. **No entry point.** `/analytics` constructs `const AnalyticsScreen()`; neither group 3-dot
   menu links to analytics (`grep analytics` in both files: zero hits).

## Proposed change

1. Optional `initialGroupId` on `AnalyticsScreen`, seeding the existing filter
   (`filter.copyWith(groupId: initialGroupId)`); in-screen chips keep working (user can widen
   back to "all").
2. Pass via GoRouter `extra` on the existing `/analytics` route (codebase's established
   extra-map pattern `{'groupId': …, 'groupName': …}`).
3. **"Group insights"** item (chart icon) in BOTH 3-dot menus (group_info `_showOverflowMenu`,
   group_detail popup) → `context.push(AppRouter.analytics, extra: …)`.
4. Group-scoped open shows the group name in the header/active chip so scope is obvious.
   i18n key `groups_screen.group_insights` ×6 locales.
5. Nothing added to the group info page body (explicit user constraint).

## Open decisions (controller)

- None.

## Acceptance

- Widget/route test: analytics pushed with `initialGroupId` renders that group's filter active,
  only its rows aggregated (reuse the PR #42 analytics guard-suite harness).
- Both menus show the entry; tapping opens scoped; clearing the chip widens to all.
- `flutter analyze` = 0; full suite green; surgical, additive diff.

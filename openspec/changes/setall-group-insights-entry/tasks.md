# Tasks

## 1. Analytics screen + route
- [ ] 1.1 `initialGroupId` (+ optional `groupName`) constructor param seeding the existing filter state
- [ ] 1.2 `/analytics` route reads GoRouter `extra` map and passes it through
- [ ] 1.3 Scoped open shows group name in header/active chip; chips still allow widening to "all"

## 2. Menu entries
- [ ] 2.1 "Group insights" in `group_info_screen._showOverflowMenu`
- [ ] 2.2 "Group insights" in `group_detail_screen` popup menu
- [ ] 2.3 i18n `groups_screen.group_insights` ×6 locales

## 3. Tests (TDD-first)
- [ ] 3.1 Route/widget test: push with `initialGroupId` ⇒ filter active, only that group's rows aggregated
- [ ] 3.2 Clearing the chip widens to all rows

## 4. Gate + close-out
- [ ] 4.1 `flutter analyze` = 0; full suite green; additive diff
- [ ] 4.2 On-device verify (user); ledger update + tick boxes in the PR

# Tasks

## 1. UI
- [x] 1.1 Hint row in `receipt_entry_sheet.dart` item-assignment section (`_buildUnassignedHint`, blue info chip styled like `_buildOcrDegradedChip`); shown when `groupId != null && members.isNotEmpty && _lineItems.isNotEmpty`
- [x] 1.2 Same hint in `edit_expense_screen.dart` itemized section; shown when the itemized split is computed (`owed.isNotEmpty` — which includes the all-unassigned case, since unassigned items are added to the payer in `_computeMemberOwed`). Display only — the `targets = assignees.isEmpty ? [payerId] : assignees` rule is untouched.

## 2. i18n
- [x] 2.1 `receipt.unassigned_to_payer_hint` ×6 locales (en/de/es/fr/ka/ru), native translations

## 3. Tests + gate
- [x] 3.1 Widget tests: hint renders (standalone chip harness, info icon not warning, non-blocking)
- [x] 3.2 Locale-parity: key present + non-empty in all 6 files (loads each JSON, checks `receipt.unassigned_to_payer_hint`)
- [x] 3.3 `flutter analyze` = 0; full suite green (551/551; the only intermittent failures are the pre-existing load-driven `concurrent_split_stress_test` perf assertions); purely additive diff (2 screens + 6 locales + 1 test)
- [ ] On-device verify (user): open a group receipt with items and the itemized edit screen — the disclaimer is visible

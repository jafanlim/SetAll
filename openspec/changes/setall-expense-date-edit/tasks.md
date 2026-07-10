# Tasks

## 1. Repository (`setall_repository.dart`)
- [ ] 1.1 Add optional `DateTime? entryDate` to `updateExpense`; when set, include `created_at` (UTC ISO-8601) in the web Supabase update payload
- [ ] 1.2 Same for the native path: SQLite UPDATE includes `created_at`; row goes to `synced_at = NULL`; verify sync_service pushes the changed column
- [ ] 1.3 `entryDate == null` ⇒ payloads byte-identical to today (created_at still stripped)
- [ ] 1.4 Mirror propagation per controller decision (recommended: `_propagateEditToMirror` updates mirror `created_at` only when `entryDate` was explicitly provided; otherwise preserve via `_existingCreatedAt` as today)

## 2. Edit screen (`edit_expense_screen.dart`)
- [ ] 2.1 Pass `entryDate: _entryDate` from `_submitConfirmed`
- [ ] 2.2 Invalidate providers already covers list refresh (L454–457) — verify date-sorted lists reorder

## 3. Tests (hermetic, TDD-first: write red guards before the fix)
- [ ] 3.1 `updateExpense(entryDate: X)` persists X (native + web fake)
- [ ] 3.2 `updateExpense()` without entryDate leaves `created_at` untouched (PR #34 regression guard)
- [ ] 3.3 Mirror `created_at` behaviour per decision (both branches)

## 4. Gate + close-out
- [ ] 4.1 `flutter analyze` = 0; full suite green; surgical diff verified
- [ ] 4.2 On-device verify (user): change the "07/06" expense's date, confirm display + ordering
- [ ] 4.3 Ledger update + tick boxes in the PR

# Proposal: Expense Date Edits Are Silently Discarded

Status: OPEN — not started (P1, user-reported 2026-07-09)
Owner: controller → workhorse
Related code: `lib/features/expenses/presentation/screens/edit_expense_screen.dart`
(`_pickDateTime` L145–182, `_submitConfirmed` L433–449),
`lib/data/repositories/setall_repository.dart` (`updateExpense` L3614+, payload strips
`created_at` at ~L3669; `_propagateEditToMirror`; `_existingCreatedAt` L4544)

## Why (user report)

User could not change the date of an expense (displayed "07/06" — under the wrong MM/DD
rendering, see `setall-region-date-format`, that's July 6 read as June 7). The picker opens, a
date is chosen, the save succeeds — and the date stays the same. "Previously I could" — true:
the **add/wallet** flow persists a picked date; only the **edit** flow drops it.

## Findings (code-verified 2026-07-10, develop `f4d125d`)

1. **The edit screen collects a date it never sends.** `_pickDateTime()` sets `_entryDate`
   (L175–181), but `_submitConfirmed` calls `repo.updateExpense(...)` (L433–449) **without any
   date argument**.
2. **`updateExpense` cannot receive a date at all.** No date/createdAt parameter
   (L3614–3630); the payload explicitly strips it: `expense.toJson()..remove('created_at')`
   (L3668–3670). Web (Supabase update) and native (SQLite + sync) both inherit this.
3. **Asymmetry**: `add_expense_screen.dart` composes and persists the picked date
   (`_composeCreatedAt(_selectedDate)` → `createdAt:` L751; wallet edit path L373–391 preserves
   time-of-day). Editing a group expense is the only flow where the date is dead UI.
4. The data model has **no separate `expense_date`** — `created_at` IS the user-facing expense
   date (the add flow writes the picked date into it). The fix is controlled `created_at`
   updates, not a new column.

## Proposed change

1. Optional `DateTime? entryDate` parameter on `updateExpense`. When provided, include
   `created_at: entryDate.toUtc().toIso8601String()` in BOTH the web Supabase `.update()`
   payload and the native SQLite update (row returns to `synced_at = NULL` so sync pushes it,
   as any edit does). When null, behaviour byte-identical to today — preserving the PR #34
   lesson (an edit must never reset `created_at` to "now").
2. Pass `entryDate: _entryDate` from `_submitConfirmed`.
3. Mirror propagation per the decision below, behind the same `entryDate != null` signal.
4. Time-of-day: keep the edit screen's existing compose (date from date-picker, time from
   time-picker or previous value) — already correct in `_pickDateTime`.

## Open decisions (controller)

- **Mirror date follows source?** `_propagateEditToMirror` currently preserves the mirror's own
  `created_at` (deliberate, PR #34). Recommendation: when the SOURCE date was explicitly edited,
  propagate the new date to the mirror (same real-world purchase); otherwise keep preserving.

## Acceptance

- Hermetic repo tests: (a) `updateExpense(entryDate: X)` persists X; (b) without `entryDate`,
  `created_at` unchanged (regression guard, PR #34 class); (c) mirror behaviour per decision.
- On-device: edit the July-6 expense's date; group list shows the new date and reorders.
- No amount-path changes (money untouched). `flutter analyze` = 0; full suite green; surgical diff.

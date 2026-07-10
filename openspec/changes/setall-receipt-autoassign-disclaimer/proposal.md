# Proposal: Receipt Split — Visible Disclaimer That Unassigned Items Go to the Payer

Status: OPEN — not started (P3, small additive UI; user-requested)
Owner: controller → workhorse
Related code: `lib/features/receipt/presentation/receipt_entry_sheet.dart` (assignment rule
L516, L649–681), `lib/features/expenses/presentation/screens/edit_expense_screen.dart` (same
rule L420, L630, L645)

## Why (user report)

In group receipt recognition, unassigned line items are automatically assigned to the payer.
The behaviour is intended and stays — but it's invisible; users assume unassigned items are
split or dropped. Add an on-screen disclaimer.

## Findings (code-verified 2026-07-10, develop `f4d125d`)

- The rule is implemented identically in the receipt sheet (`targets = assignees.isEmpty ?
  [payerId] : assignees`, L516/L665; rounding remainder also on the payer L681) and the
  itemized editor in edit_expense_screen (L420/L645). Documented only in code comments
  (L649–652); no UI text exists (grep of `lib/` + locale files: nothing).

## Proposed change

1. Persistent one-line hint (info icon + text) in the receipt sheet's item-assignment section:
   EN "Items left unassigned are charged to the payer."
2. Same hint in the edit-expense line-item editor (same rule applies on re-save).
3. i18n key `receipt.unassigned_to_payer_hint` in **all 6 locales** (en/de/es/fr/ka/ru) — real
   translations where the team has them.
4. Display only — zero logic changes.

## Acceptance

- Widget test: hint present when line items are rendered (both screens).
- All 6 locale files carry the key (locale-parity check).
- `flutter analyze` = 0; full suite green; purely additive diff.

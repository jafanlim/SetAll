# Proposal: Group Expense List — Show Entry Date + Reliable Default-Currency Estimate

Status: OPEN — not started (P2 UI parity, user-requested; was expected weeks ago)
Owner: controller → workhorse
Related code: `lib/features/dashboard/presentation/screens/group_detail_screen.dart`
(`_ExpenseTile` L1027–1192, `_ExpenseTileSelectable` L930–1026),
`lib/features/dashboard/presentation/screens/group_expense_detail_screen.dart` (reference —
already shows both), `lib/core/services/date_format_service.dart`

## Why (user report)

On the group's expense list: (1) entries show **no date**, and (2) the user sees **no
"≈ default currency" annotation**. Product goal: *every screen unified, showing similar
information* — the expense detail screen already shows both (date L356–361, `≈ base` L492);
wallet rows show dates; the group list is the odd one out.

## Findings (code-verified 2026-07-10, develop `f4d125d`)

1. **Date: genuinely missing.** `group_detail_screen.dart` doesn't import `DateFormatService`;
   `_ExpenseTile` renders description + split-badge + amount only. Same for
   `_ExpenseTileSelectable`.
2. **The ≈ annotation EXISTS in `_ExpenseTile` (L1147–1155) but is fragile** — renders only if
   ALL hold:
   - `expense.currency != baseCurrency` (L1064) — compares the **base** `currency` field while
     the tile *displays* `originalCurrency ?? currency` (L1059–1060): mismatch hides it;
   - `expense.universalUsdAmount != null` — null on legacy rows;
   - `rateToBaseProvider((from:'USD', base:baseCurrency))` resolves — silently hidden while
     loading or when local `exchange_rates` are stale/empty (plausible on the user's device:
     `sync-exchange-rates` was gateway-403'd until 2026-06-26).
   Which condition bit the user needs a 2-minute on-device check; all three are fixable.

## Proposed change

1. **Date line on both tiles**: `DateFormatService.instance.formatShort(createdAt)` (e.g.
   "7 Jun" — unambiguous under any locale) as small secondary text next to the split badge;
   `formatMedium` when the year differs from the current year. (Pairs with
   `setall-region-date-format`.)
2. **Robust ≈ estimate**:
   - show-condition on the *displayed* currency: `displayCurrency != baseCurrency`;
   - when `baseCurrency == 'USD'`, skip the rate lookup (rate ≡ 1) and render
     `≈ USD <universalUsdAmount>` directly — removes the rate-provider dependency for the most
     common case;
   - Decimal arithmetic exactly as-is (money rule).
3. **Unification scope control:** NO shared-widget refactor in this task (surgical-diff rule).
   Land additive tile changes; the shared `ExpenseRow` extraction (group + wallet + activity)
   is a separate follow-up spec if the controller green-lights it after this ships.

## Open decisions (controller)

- Whether to spec the shared `ExpenseRow` widget follow-up after landing.

## Acceptance

- Widget test: tile renders the date; renders `≈ USD x.xx` for a GEL expense with USD base with
  NO exchange-rate row present.
- On-device: user's group shows date + ≈ estimate on every entry; record WHICH condition
  previously hid the annotation (currency-field mismatch vs null USD amount vs rate lookup).
- `flutter analyze` = 0; full suite green; Decimal-only; surgical diff.

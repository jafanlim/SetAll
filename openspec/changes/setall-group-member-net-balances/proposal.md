# Proposal: Group Info — Each Member's Net Position (Group Currency + Default Currency)

Status: OPEN — not started (P2, user-requested; extends PR #30 which only covered "vs you")
Owner: controller → workhorse
Related code: `lib/features/groups/presentation/screens/group_info_screen.dart` (members card
L630–752), `lib/core/services/balance_service.dart`, `SettlementEngine` (Math-Guard suite in
`test/core/services/`), `groupBalanceSummaryProvider`

## Why (user report)

"On the group info page, I still cannot see how much money each particular member of the group
owes or is owed." Wanted per member: **overall net position in the group**, in the **group
currency**, annotated in the **default app currency**.

## Findings (code-verified 2026-07-10, develop `f4d125d`)

1. PR #30 (`d029731`) landed per-member labels — but only **relative to the current user**:
   sums simplified-debt transactions `m → me` ("owes you X") or `me → m` ("you owe X")
   (L674–698). Consequences:
   - a member who owes a *third* member shows **"settled up"**;
   - the current user's own row always shows "settled up" (L699–702);
   - amounts render in `owesYouTxns.first.currency` only — no default-currency annotation.
2. Plumbing exists: groups carry `default_currency` (C-3, PR #13); `baseCurrencyProvider` gives
   the app default; the ≈ pattern exists in `group_detail_screen._ExpenseTile`.
3. Net math exists and is test-guarded: `SettlementEngine` per-member nets (PR #40 Math-Guard,
   incl. sub-cent round-first fix). Member net = Σ(txns to them) − Σ(txns from them) over the
   group's simplified debts.

## Proposed change

1. Members card shows **two lines per member**:
   - primary: net position — "owes GEL 25.00" / "is owed GEL 25.00" / "settled up" (teal/orange
     as today), `Decimal`-computed from the group's per-member nets (reuse
     `SettlementEngine`/balance-service — NO new float math);
   - secondary (smaller): `≈ USD 9.20` default-currency annotation (skip when group currency ==
     default), plus the existing vs-you detail ("owes you GEL 10.00") when non-zero.
2. Current user's own row shows their net position too.
3. Primary-line currency = the currency the debts are computed in today (group currency); no
   new conversion paths beyond the existing USD-ledger ≈ pattern.

## Open decisions (controller)

- None blocking.

## Acceptance

- Hermetic test: A pays 30 split 3-way even ⇒ A "is owed 20", B/C "owes 10" each; a B↔C-only
  debt shows on B and C rows, A unaffected; settled group ⇒ all "settled up".
- Sub-cent nets render "settled up", not "owes 0.00" (PR #40 rounding guarantee).
- ≈ hidden when group currency == default currency.
- `flutter analyze` = 0; full suite green; Decimal-only; surgical diff (members card only).

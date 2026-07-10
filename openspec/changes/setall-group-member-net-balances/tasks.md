# Tasks

## 1. Net computation
- [ ] 1.1 Expose per-member group nets from the existing simplified-debts data (Σ to-member − Σ from-member, `Decimal`); reuse `SettlementEngine`/balance-service outputs — no new math path
- [ ] 1.2 ≈ default-currency conversion via the existing USD-ledger pattern; skip when group currency == default

## 2. UI (`group_info_screen.dart` members card)
- [ ] 2.1 Primary line: net position per member (incl. current user's own row); teal/orange/neutral as today
- [ ] 2.2 Secondary line: ≈ default currency + existing vs-you detail when non-zero

## 3. Tests (TDD-first)
- [ ] 3.1 Hermetic: 3-member even-split nets; third-party debt visibility; settled group
- [ ] 3.2 Sub-cent net ⇒ "settled up" (no "owes 0.00")
- [ ] 3.3 ≈ suppressed when group currency == default currency

## 4. Gate + close-out
- [ ] 4.1 `flutter analyze` = 0; full suite green; Decimal-only; surgical diff
- [ ] 4.2 On-device verify (user); ledger update + tick boxes in the PR

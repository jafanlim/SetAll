# Tasks

## 1. Tiles (`group_detail_screen.dart`)
- [ ] 1.1 Add date line to `_ExpenseTile` via `DateFormatService.formatShort`/`formatMedium` (year-aware)
- [ ] 1.2 Same for `_ExpenseTileSelectable`
- [ ] 1.3 ≈ estimate: condition on displayed currency; direct `≈ USD <universalUsdAmount>` when base is USD (no rate lookup); Decimal-only

## 2. Diagnosis (record in PR + ledger)
- [ ] 2.1 Determine which condition hid the annotation on the user's device (currency-field mismatch / null `universalUsdAmount` / rate-provider miss)

## 3. Tests (TDD-first)
- [ ] 3.1 Widget test: date renders; current-year vs prior-year format
- [ ] 3.2 Widget test: GEL expense + USD base + empty exchange_rates ⇒ `≈ USD …` still renders
- [ ] 3.3 No annotation when displayed currency == base currency

## 4. Gate + close-out
- [ ] 4.1 `flutter analyze` = 0; full suite green; surgical diff
- [ ] 4.2 On-device verify (user); ledger update + tick boxes in the PR

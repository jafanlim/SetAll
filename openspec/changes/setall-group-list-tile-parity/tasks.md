# Tasks

## 1. Tiles (`group_detail_screen.dart`)
- [x] 1.1 Add date line to `_ExpenseTile` via `DateFormatService.formatShort`/`formatMedium` (year-aware) — via top-level `formatExpenseDate(createdAt)` helper
- [x] 1.2 Same for `_ExpenseTileSelectable` (converted `StatelessWidget`→`ConsumerWidget` to read `baseCurrencyProvider`; also brought its primary amount to parity: `originalCurrency/originalAmount` like `_ExpenseTile`, was showing base `currency/amount`)
- [x] 1.3 ≈ estimate: condition on displayed currency (`originalCurrency ?? currency`); direct `≈ USD <universalUsdAmount>` when base is USD (no rate lookup); non-USD keeps `rateToBaseProvider`; Decimal-only

## 2. Diagnosis (record in PR + ledger)
- [x] 2.1 The fix neutralizes all three hide-conditions: (a) currency-field mismatch — show-condition now keys off the *displayed* currency, not the base `currency` field; (b) rate-provider miss — USD-base path reads `universalUsdAmount` directly, no rate watch; (c) null `universalUsdAmount` — still correctly guarded (legacy rows without an anchor show no estimate). Exact device condition = user on-device note. **Behavior change:** the old `else if` fallback that rendered `"{currency} {amount} base"` for converted rows with a null anchor was removed (it mislabeled the canonical amount as "base"); those rare legacy rows now show no estimate.

## 3. Tests (TDD-first) — `test/widget/group_expense_tile_test.dart`
- [x] 3.1 Widget test: date renders; current-year → "d MMM" (no year) vs prior-year → "d MMM yyyy"
- [x] 3.2 Widget test: GEL expense + USD base + EMPTY exchange_rates ⇒ `≈ USD 54.95` still renders (core regression guard — proves no rate-provider dependency on the USD path)
- [x] 3.3 Widget test: no annotation when displayed currency == base currency

## 4. Gate + close-out
- [x] 4.1 `flutter analyze` = 0; surgical diff (1 source file + 1 new test file); full suite = no new failures (7 new pass; the sole failure is a pre-existing, load-driven wall-clock perf flake in `concurrent_split_stress_test.dart` "< 100ms", identical on untouched develop)
- [ ] 4.2 On-device verify (user): open the group — every entry shows a date + the ≈ estimate; note which condition previously hid it

# Design

## Part 1 — Base-currency freeze fix

### Root cause
`_doImport` in `splitwise_import_screen.dart` (line ~381) calls `repo.addExpense(groupId: null, ...)` for wallet-destination rows. `addExpense` builds an `ExpenseModel` and never sets `baseCurrencyAmount`. Only `upsertWalletEntry` (line 4034) fetches the user's `defaultCurrency`, resolves a rate via `_resolveRateToUsd`, and freezes the field.

`getWalletEntryTotals` falls back for entries where `base_currency_amount IS NULL` — it re-converts via `universalUsdAmount` at the live USD→base rate. If the user's base currency is non-USD and exchange rates shift after import, those imported entries produce different totals on re-read. This is a live balance-drift bug.

### Priority verification (task 1.0)
Before coding, verify: does a null `base_currency_amount` actually drift the wallet balance when the base currency is non-USD? Expected yes: `getWalletEntryTotals` uses live `_currencyService.getRate('USD', baseCurrency)` for all entries where the entry currency ≠ base currency AND `baseCurrencyAmount` is absent. Confirmed by reading `setall_repository.dart:4016–4027`. **This is live and high priority for any user whose base currency is not USD.**

### Fix
Replace the `addExpense` call in the wallet-destination branch with `upsertWalletEntry`, building a `WalletEntryModel` per row from the parsed `_SplitwiseRow` fields. The model's `entryDate` maps to `createdAt`. After the fix, every imported row has `base_currency_amount` frozen at save time (same as AddExpenseScreen — the P58 pattern).

## Part 2 — CsvAdapter extraction

### Root cause
`_parseCsv` (line 152) and `_SplitwiseRow` (line 26) are private members of `_SplitwiseImportScreenState`. The ingestion pipeline cannot import them — they are co-located inside a widget state class.

### Fix
Extract into `lib/core/services/csv_adapter.dart`:
- `SplitwiseRow` (public, identical fields to `_SplitwiseRow`)
- `CsvAdapter.parse(String raw) → ({List<SplitwiseRow> rows, List<String> errors})`
- `_splitCsvLine` and `_col` helpers move with it (private to the file)
- `splitwise_import_screen.dart` delegates to `CsvAdapter.parse` — no behaviour change for the existing flow

## Constraints
- No schema change. No new table. No migration.
- `CsvAdapter` is pure Dart — no Flutter deps, no Riverpod. Importable by any layer.
- Keep `_Destination`, `_DestinationTile`, and all UI state in the screen file.

## Out of scope
Column-mapping UI for arbitrary bank CSVs (that is the ingestion pipeline's task 1.1).

## Verification
Web (Supabase-direct) first: import a multi-currency SetAll CSV export; verify `base_currency_amount` is non-null in the `expenses` table for every imported row and that the wallet balance matches the sum. Then iOS SQLite write path must show identical values before this change is archived. Web passing is not the exit gate.

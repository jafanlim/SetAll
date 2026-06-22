# Tasks

## 1. Web (Supabase-direct path)
- [x] 1.0 Confirmed: `addExpense` never sets `base_currency_amount`; `getWalletEntryTotals` re-converts via live USD rate for all entries where currency ≠ base AND `base_currency_amount IS NULL`. Code audit of `setall_repository.dart` lines 4002–4031 vs 4044–4067 confirms balance-drift bug is live for any user whose base currency is not USD.
- [x] 1.1 Extracted `SplitwiseRow` + `CsvAdapter.parse` into `lib/core/services/csv_adapter.dart`; `splitwise_import_screen.dart` delegates via `CsvAdapter.parse`; private `_SplitwiseRow`, `_parseCsv`, `_splitCsvLine`, `_col` removed from screen
- [x] 1.2 Wallet-destination branch routes through `upsertWalletEntry(WalletEntryModel(...))` — `base_currency_amount` frozen at save time (P58 pattern); `flutter analyze` clean
- [x] 1.3 Verified on web: 12-row multi-currency CSV (USD/EUR/GBP) imported; Supabase `expenses` query confirms `base_currency_amount` non-null on all rows including cross-currency entries; wallet balance stable

## 2. Mobile
- [ ] 2.1 Verify iOS SQLite write path: imported rows have non-null `base_currency_amount` in local SQLite and wallet totals match web
- [ ] 2.2 Verify Android

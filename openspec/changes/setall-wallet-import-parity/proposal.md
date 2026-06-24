## Why
Two live defects found during ingestion pre-work. First: the CSV importer commits wallet-destination rows via `addExpense` (`setall_repository.dart`), which never computes `base_currency_amount`. `upsertWalletEntry` (`setall_repository.dart:4034`) is the only path that freezes it at save time (P58 rate-lock). Imported rows arrive with `base_currency_amount = null`, which `getWalletEntryTotals` falls back to live rate conversion — meaning the wallet balance can drift after a rate change. Second: `_parseCsv` / `_SplitwiseRow` are private members of `_SplitwiseImportScreenState` (`splitwise_import_screen.dart:152`), blocking reuse by the ingestion pipeline.

## What Changes
- **Base-currency freeze fix**: wallet-destination import rows commit via `upsertWalletEntry` (building a `WalletEntryModel`) instead of `addExpense`, so `base_currency_amount` is frozen at save time.
- **CsvAdapter extraction**: `_parseCsv` / `_SplitwiseRow` extracted into a standalone `CsvAdapter` service consumable by both the existing import screen and the future ingestion flow.

## Impact
- Affected: `splitwise_import_screen.dart` (commit path + refactor), new `lib/core/services/csv_adapter.dart`.
- No schema change. No AI. No new table.
- Unblocks: `setall-ingestion-pipeline` task 1.1 (CsvAdapter dependency).

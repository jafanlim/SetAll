# Wallet Import Parity

## ADDED Requirements

### Requirement: Base-Currency Freeze on Import
The system SHALL freeze `base_currency_amount` for every wallet-destination row at import time by committing via `upsertWalletEntry`, matching the P58 rate-lock applied by the manual add-expense flow.

#### Scenario: Single-currency import matches base currency
- **WHEN** a user imports a CSV with entries already in their base currency
- **THEN** each imported row in the `expenses` table SHALL have `base_currency_amount` equal to the entry `amount`

#### Scenario: Multi-currency import freezes at save-time rate
- **WHEN** a user imports a CSV containing entries in a currency different from their base currency
- **THEN** each imported row SHALL have a non-null `base_currency_amount` frozen to the exchange rate at import time, and the wallet balance SHALL NOT change if exchange rates change after import

#### Scenario: Null base_currency_amount causes balance drift (regression guard)
- **WHEN** an imported row has `base_currency_amount = null` and the user's base currency is non-USD
- **THEN** the wallet balance displayed to the user SHALL drift if the USD→base exchange rate changes — confirming the bug is live before the fix is applied

### Requirement: CsvAdapter Reusability
The system SHALL expose CSV parsing as a standalone `CsvAdapter` service callable from any Dart layer, not as a private widget member.

#### Scenario: Import screen delegates to CsvAdapter
- **WHEN** a user picks a CSV file in the Splitwise import screen
- **THEN** parsing SHALL be performed by `CsvAdapter.parse` and the import result SHALL be identical to the behaviour before extraction

#### Scenario: Ingestion pipeline consumes CsvAdapter
- **WHEN** the ingestion pipeline processes a CSV input
- **THEN** it SHALL call `CsvAdapter.parse` directly without importing any widget or screen class

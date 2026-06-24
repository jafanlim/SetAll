# Ingestion

## ADDED Requirements

### Requirement: Multi-format Ingestion
The system SHALL accept CSV, text-based PDF, and image inputs and produce normalized transaction rows with date, amount, currency, and raw description.

#### Scenario: Bank CSV with column mapping
- **WHEN** a user uploads a bank CSV whose columns differ from the SetAll format
- **THEN** the user maps columns and the system produces normalized rows

#### Scenario: Text PDF statement
- **WHEN** a user uploads a text-based PDF statement
- **THEN** transactions are extracted into normalized rows

### Requirement: Classification
The system SHALL classify each normalized row into a category drawn from the union of the fixed `kExpenseCategories` enum and the user's own categories in the `user_categories` table, and generate a short description, using server-side Groq via `ingest.js`.

#### Scenario: Row classified into a fixed category
- **WHEN** a normalized row is classified
- **THEN** it SHALL be assigned one of the `kExpenseCategories` values or a user-created category, and SHALL receive a generated description; no new category is created

#### Scenario: Row classified into a user-created category
- **WHEN** a user has a custom category and a normalized row matches it
- **THEN** the row SHALL be assigned the user-created category name, not forced into a fixed enum value

### Requirement: Review Before Commit
The system SHALL require explicit per-row approval before any row is written to the database.

#### Scenario: User edits and approves
- **WHEN** a user edits a row's category and approves it
- **THEN** it SHALL be written via `upsertWalletEntry` (building a `WalletEntryModel`) with `base_currency_amount` frozen at commit time; `addExpense` SHALL NOT be used for this path

#### Scenario: User rejects a row
- **WHEN** a user rejects a row
- **THEN** it is never written to the database

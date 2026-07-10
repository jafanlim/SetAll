# Group Expense List Presentation

## ADDED Requirements

### Requirement: Entry Date on Group Expense Rows
Every expense row in the group expense list (normal and selectable variants) SHALL display the
entry's date, formatted via `DateFormatService` (short form; include the year when it differs
from the current year).

#### Scenario: Current-year entry
- **WHEN** an expense dated 7 June of the current year is listed
- **THEN** the row shows "7 Jun"

#### Scenario: Prior-year entry
- **WHEN** an expense dated 7 June of a prior year is listed
- **THEN** the row shows "7 Jun <year>"

### Requirement: Default-Currency Estimate on Group Expense Rows
Every expense row whose DISPLAYED currency differs from the user's default (base) currency SHALL
show a `≈ <base> <amount>` estimate computed in `Decimal`. When the base currency is USD the
estimate SHALL derive directly from the expense's `universal_usd_amount` without an
exchange-rate lookup.

#### Scenario: GEL expense, USD base, no local rates
- **WHEN** a GEL expense is listed, base currency is USD, and the local exchange-rate cache is empty
- **THEN** the row still shows `≈ USD <universal_usd_amount>`

#### Scenario: Same currency
- **WHEN** the displayed currency equals the base currency
- **THEN** no estimate annotation is shown

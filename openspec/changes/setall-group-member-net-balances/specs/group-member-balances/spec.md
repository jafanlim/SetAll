# Group Member Balances

## ADDED Requirements

### Requirement: Per-Member Net Position
The group info screen SHALL display, for EVERY member (including the current user), that
member's overall net position within the group — owed, owing, or settled — computed in `Decimal`
from the group's netted debts, in the group currency.

#### Scenario: Even split
- **WHEN** A pays 30 split evenly among A, B, C
- **THEN** A shows "is owed 20.00", B and C each show "owes 10.00"

#### Scenario: Debt not involving the viewer
- **WHEN** B owes C and neither debt involves the current user A
- **THEN** B's row shows the owing position and C's row shows the owed position on A's screen

#### Scenario: Sub-cent net
- **WHEN** a member's net rounds below one cent
- **THEN** the row shows "settled up", never a 0.00 amount

### Requirement: Default-Currency Annotation
Each non-zero net position SHALL carry a secondary `≈ <default currency> <amount>` annotation,
suppressed when the group currency equals the default app currency. The existing
viewer-relative detail ("owes you …" / "you owe …") remains when non-zero.

#### Scenario: GEL group, USD default
- **WHEN** a member owes GEL 25.00 and the app default currency is USD
- **THEN** the row shows "owes GEL 25.00" with "≈ USD <converted>" beneath it

#### Scenario: Same currency
- **WHEN** the group currency equals the default currency
- **THEN** no ≈ annotation is rendered

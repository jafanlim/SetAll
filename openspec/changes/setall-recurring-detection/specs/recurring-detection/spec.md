# Recurring Detection

## ADDED Requirements

### Requirement: Recurring Candidate Detection
The system SHALL identify likely recurring transactions from a user's history and present them as candidates for confirmation, without modifying any data until confirmed.

#### Scenario: Monthly subscription detected
- **WHEN** the history contains a similar description and amount recurring at ~monthly cadence
- **THEN** a candidate is surfaced with its inferred label, amount, currency, and cadence

#### Scenario: User confirms a candidate
- **WHEN** a user confirms a candidate
- **THEN** a `recurring_rules` row is persisted with `confirmed = true`, scoped to the user

#### Scenario: User dismisses a candidate
- **WHEN** a user dismisses a candidate
- **THEN** it is not written and not resurfaced within the same period

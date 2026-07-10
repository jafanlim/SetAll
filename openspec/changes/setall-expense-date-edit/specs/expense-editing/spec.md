# Expense Editing — Date

## ADDED Requirements

### Requirement: Editable Expense Date
The system SHALL persist a date explicitly picked in the edit-expense screen to the expense's
`created_at` on both web (Supabase-direct) and native (SQLite + sync) paths, preserving the
picked time-of-day composition.

#### Scenario: User changes the date
- **WHEN** the user edits an expense and picks a new date, then saves
- **THEN** the expense's `created_at` reflects the picked date after reload, on the device and after sync on other devices

#### Scenario: User edits without touching the date
- **WHEN** the user edits only the amount/description and saves
- **THEN** `created_at` is unchanged (never reset to "now" — PR #34 regression class)

### Requirement: Mirror Date Consistency
When a group expense with a linked wallet mirror has its date explicitly edited, the mirror
SHALL follow the controller-decided policy (default recommendation: mirror `created_at` follows
the explicitly edited source date; unedited saves continue to preserve the mirror's own
`created_at`).

#### Scenario: Source date edited
- **WHEN** the source expense date is explicitly changed
- **THEN** the linked mirror reflects the policy outcome and never resets to the wall-clock save time

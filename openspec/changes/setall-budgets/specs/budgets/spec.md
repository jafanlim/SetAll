# Budgets

## ADDED Requirements

### Requirement: Budget Definition
The system SHALL allow a user to define per-category and overall monthly budgets stored in their base currency, isolated per user by row-level security.

#### Scenario: Create a category budget
- **WHEN** a user sets a monthly budget for category "Food & drink"
- **THEN** a `budgets` row is created with that category, period `monthly`, and the amount in base currency, scoped to the user

#### Scenario: Overall budget
- **WHEN** a user sets a budget with no category
- **THEN** the row is stored with `category = null` and represents the total monthly limit

### Requirement: Budget Progress
The system SHALL compute current-period per-category spend against each budget, normalized to base currency, via `getCategorySpend(from, to)` — a repository method that filters `getPersonalExpenses()` by category and date range and returns a `Map<String, Decimal>` of category → base-currency total. This query is owned by setall-budgets and exposed as `categorySpendProvider`. `getWalletEntryTotals` SHALL NOT be used (all-time, no category/date filter). `analyticsData.categoryTotals` SHALL NOT be used (`_analyticsFilterProvider` is module-private and cannot be month-scoped externally).

#### Scenario: Multi-currency spend rolled to base
- **WHEN** the period contains expenses in more than one currency
- **THEN** each is converted to base currency and summed before comparison to the budget amount

#### Scenario: Spend crosses the budget
- **WHEN** current-period spend for a category reaches or exceeds its budget
- **THEN** the progress indicator reflects the over-budget state

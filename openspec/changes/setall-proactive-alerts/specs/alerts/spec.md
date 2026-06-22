# Alerts

## ADDED Requirements

### Requirement: Budget Threshold Alert
The system SHALL notify a user when current-period spend for a category crosses their configured threshold percentage.

#### Scenario: 80% threshold crossed
- **WHEN** category spend reaches the user's threshold (default 80%) of its budget
- **THEN** a threshold alert is generated for that category

### Requirement: Anomaly Alert
The system SHALL flag a newly added expense that exceeds a configurable multiple of that category's mean over the recent window. The N-month mean SHALL be computed via `getCategorySpend(from, to)` (the shared query owned by setall-budgets, filtering `getPersonalExpenses()` by category + date range). `analyticsData.categoryTotals` SHALL NOT be used.

#### Scenario: Anomalous expense flagged
- **WHEN** a new expense exceeds `k` times the category mean over `N` months (derived from `getCategorySpend` over that window)
- **THEN** an anomaly alert is generated referencing that expense

### Requirement: Delivery and Preferences (v1)
The system SHALL deliver alerts via FCM push, localized to the user's language, and SHALL respect per-type preferences. Email delivery (via a `send-alert-email` Edge fn) is a fast-follow and is not a v1 requirement; `alert_prefs` has no `email_enabled` column in v1.

#### Scenario: Disabled alert type
- **WHEN** a user disables a given alert type in `alert_prefs`
- **THEN** alerts of that type SHALL NOT be delivered on any channel

#### Scenario: Alert delivered in user language
- **WHEN** an alert fires for a user with a non-English `language_code`
- **THEN** the FCM notification payload SHALL use localized copy matching the user's stored language

# Group Insights Entry Point

## ADDED Requirements

### Requirement: Group-Scoped Analytics Entry
Both group 3-dot menus (group info overflow, group detail popup) SHALL offer a "Group insights"
action that opens the analytics screen pre-filtered to that group, as a separate screen. The
group info page body SHALL NOT gain any insights content.

#### Scenario: Open from group info
- **WHEN** the user taps ⋮ → "Group insights" on a group's info page
- **THEN** the analytics screen opens with that group's filter active and its name visible, showing category totals computed only from that group's expenses

#### Scenario: Widen scope
- **WHEN** the user clears the group filter chip inside the analytics screen
- **THEN** the screen shows all-expense analytics exactly as the unscoped entry does

### Requirement: Scoped Aggregation Correctness
Group-scoped analytics SHALL aggregate only rows whose `groupId` matches the selected group,
using the existing Decimal aggregation path.

#### Scenario: Mixed data
- **WHEN** the user has wallet entries and expenses in two groups
- **THEN** a scope on group A includes only group A's expenses — no wallet rows, no group B rows

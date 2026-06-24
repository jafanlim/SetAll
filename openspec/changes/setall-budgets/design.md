# Design

## Data model
```sql
create table budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text,                       -- null = overall budget
  period text not null default 'monthly',
  amount numeric not null,
  currency text not null,              -- stored in base currency
  created_at timestamptz default now()
);
alter table budgets enable row level security;
-- four policies (select/insert/update/delete) all: auth.uid() = user_id  [idiom: auth.uid() always on LEFT in USING/WITH CHECK]
```

## Spend computation

### Why not `getWalletEntryTotals` or `analyticsDataProvider`
`getWalletEntryTotals` returns an all-time `{income, spend, net}` triple with no category
filter and no date filter. It cannot serve per-category current-month spend. Do NOT use it
for the budget provider.

`analyticsDataProvider` is driven by `_analyticsFilterProvider`, a private `StateProvider`
scoped to the analytics screen. Its period filter cannot be set externally, so it cannot be
month-scoped by a budget provider without a breaking refactor.

### Canonical path (owned by setall-budgets)
setall-budgets OWNS this shared query. Filter `getPersonalExpenses()` by category + date
range (current month start → now) in a new repository method `getCategorySpend(from, to)`
(returns `Map<String, Decimal>` category → base-currency total). Expose this to Riverpod
via a `categorySpendProvider` family parameterised by `(from, to)`. Normalize to base
currency using `baseCurrencyProvider` + exchange rates at read time. No dependency on
`analyticsDataProvider`. `category = null` budget rows aggregate all categories by summing
the full map.

**Decision recorded**: `analyticsData.categoryTotals` is NOT the spend source for budgets.
The `getCategorySpend` repo method is.

## Out of scope
Rollover, weekly/annual periods, shared/group budgets.

## Verification
Web (Supabase-direct) first; then iOS SQLite read path must return identical totals
before the change is archived. Web passing is not the exit gate.

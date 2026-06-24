# Design

## Decision
**Heuristic** (locked): fuzzy description match + amount tolerance + 28–32-day spacing.
Zero AI cost, predictable, debuggable. Groq-assisted is a later fallback gated on real
false-negative signal from production — not v1. If Groq-assisted is added later, add
cases to the Spec 5 eval set (locked set).

## Data model
```sql
create table recurring_rules (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  label text not null,
  category text,
  amount numeric not null,
  currency text not null,
  cadence text not null,               -- 'monthly' | 'weekly'
  next_date date,
  confirmed boolean default false
);
alter table recurring_rules enable row level security;
-- four policies, all: auth.uid() = user_id  [idiom: auth.uid() always on LEFT in USING/WITH CHECK]
```

## Data source
`getPersonalExpenses()` (raw expense list). NOT `getWalletEntryTotals` — that returns
an all-time `{income, spend, net}` triple with no individual rows, so pattern detection
is impossible from it.

## Flow
`getPersonalExpenses()` → heuristic detection → candidate list (with confidence) → user confirms/dismisses → persist
confirmed rules. Dismissed candidates are not resurfaced in the same period.

## Out of scope
Auto-creating future expenses from rules; price-change tracking.

## Verification
Web first; iOS SQLite history path must yield the same candidates before archive.

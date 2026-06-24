# Design

## Staging
- **Stage 1 (this change):** capture only. No prompt changes, no loop.
  Note: `shown` / `dismissed` hook points do not exist yet in `InsightsScreen` or wallet.
  Stage 1 adds that capture wiring as implementation work — this is not a wrong assumption,
  it is deliberate new wiring. The signal table + RLS are cheap to ship now; the loop is not.
- **Stage 2 (deferred):** the loop. Platform-agnostic — targets the canonical
  `ai-analyst.js` prompt that web + mobile already share.

## Data model
```sql
create table insight_signal (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  event text not null,                 -- 'shown' | 'dismissed' | 'expanded' | 'followup'
  insight_ref text,
  created_at timestamptz default now()
);
alter table insight_signal enable row level security;
-- four policies, all: auth.uid() = user_id  [idiom: auth.uid() always on LEFT in USING/WITH CHECK]
```

## Promotion rule (Stage 2)
A variant is promoted ONLY if it beats baseline on both the locked Spec 5 eval set and
the behavior signal. The eval set is never modified by the loop (Karpathy rule).

## Out of scope (Stage 1)
The variant generator, scorer, and promotion are deferred.

## Verification
Stage 1: capture events recorded with correct user scoping on web and mobile.

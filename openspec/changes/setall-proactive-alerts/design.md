# Design

## Decision
**FCM-only for v1** (locked). `send-email` is an auth hook only — there is no general
transactional Resend wrapper. `alert_prefs` has no `email_enabled` column in v1.
Email delivery is a fast-follow: spec a thin new `send-alert-email` Supabase Edge fn
(mirrors `send-welcome-email` pattern, localized via existing `ALERT_COPY` map) to ship
alongside the upcoming-recurring-charge alert, not in v1.

## Web-first nuance
Detection + in-app banner surfacing is fully testable on Flutter web. Actual push
delivery is platform-split (web push vs APNs/FCM): build/verify detection + in-app
surface on web first, then layer platform push (mobile FCM, then web push).

## Anomaly calc
Flag a new expense when `amount_base > k * mean(category over N months)`. Use
`getCategorySpend(from, to)` — the shared query owned by setall-budgets that filters
`getPersonalExpenses()` by category + date range. Call it once per month-window to build
the N-month mean. Do NOT use `analyticsData.categoryTotals` (`_analyticsFilterProvider`
is module-private and cannot be month-scoped externally). `k` and `N` configurable.

## Data model
```sql
create table alert_prefs (
  user_id uuid primary key references auth.users(id) on delete cascade,
  budget_threshold_enabled boolean default true,
  threshold_pct int default 80,
  anomaly_enabled boolean default true,
  recurring_enabled boolean default false
);
alter table alert_prefs enable row level security;
-- four policies, all: auth.uid() = user_id  [idiom: auth.uid() always on LEFT in USING/WITH CHECK]
-- optional alert_log(user_id, type, payload, created_at) for de-dup
```

## Out of scope
Digest scheduling changes; per-category threshold overrides (v1 is a single pct).

## Verification
Web: both alert types fire to an in-app banner. Mobile: FCM delivery localized,
verified iOS + Android. Web push last.

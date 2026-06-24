## Why
Insights are pull-only. The value moment is a timely push: "80% through dining budget", "unusual charge", "Netflix renews tomorrow". FCM + Resend infra already exists; email localization already shipped. Requires `setall-budgets` and `setall-recurring-detection`.

## What Changes
- Alert types v1: budget threshold (from budgets) and anomaly (new expense > k× category mean over N months, reusing Spec 6 grounding stats). Upcoming-recurring-charge (from recurring) is a fast-follow.
- Delivery v1: FCM push only. Email via a thin new `send-alert-email` Edge fn is a fast-follow alongside recurring alerts — not v1. There is no general transactional Resend wrapper (`send-email` is an auth hook only) and `alert_prefs` has no `email_enabled` column in v1.
- Server-side trigger: new-expense hook and/or a daily scheduled run.
- New `alert_prefs` table (+ optional `alert_log`), RLS-scoped.

## Impact
- Affected: new migration, trigger fn (cron/scheduled), anomaly calc reusing grounding totals, Flutter in-app banner + prefs screen, FCM wiring (exists), localized copy via existing email i18n.

## Decision
FCM-only for v1. Email fast-follow via a new `send-alert-email` Edge fn when recurring alerts ship.

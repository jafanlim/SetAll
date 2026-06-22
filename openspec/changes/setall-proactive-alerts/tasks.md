# Tasks

## 1. Web (logic + in-app surface; push is platform-split, later)
- [x] 1.1 Migration: `alert_prefs` (+ optional `alert_log`) + RLS (4 ops, `auth.uid()`); add to coverage matrix
- [x] 1.2 Anomaly calc (k× category mean over N months) reusing grounding totals
- [x] 1.3 Budget-threshold check from `setall-budgets`
- [x] 1.4 In-app banner + alert-prefs screen; verify both alert types fire on web
- [ ] 1.5 Server trigger: new-expense hook and/or daily scheduled run (Supabase cron or Netlify scheduled fn)

## 2. Mobile / native
- [ ] 2.1 FCM push delivery (v1 only), localized to user language; verify iOS + Android
- [ ] 2.2 Web push delivery (defer to after mobile FCM is verified)
- [ ] 2.3 Upcoming-recurring-charge alert + `send-alert-email` Edge fn (fast-follow, ships alongside this; from `setall-recurring-detection`)

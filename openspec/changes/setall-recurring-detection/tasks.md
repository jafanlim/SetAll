# Tasks

## 1. Web (Supabase-direct path)
- [x] 1.1 Migration: `recurring_rules` + RLS (4 ops, `auth.uid()`); add to coverage matrix
- [x] 1.2 Detection service (heuristic: fuzzy description match + amount tolerance + 28–32-day spacing) over `getPersonalExpenses()` raw list → candidates with confidence
- [x] 1.3 Confirm/dismiss screen; persist confirmed rules
- [ ] 1.4 Verify against a history with known subscriptions on web
- [ ] 1.5 (Fast-follow, gated on false-negative signal) If Groq-assisted is added later: add cases to the Spec 5 eval set (locked set)

## 2. Mobile
- [ ] 2.1 Port detection + confirm screen
- [ ] 2.2 Verify iOS SQLite history yields identical candidates
- [ ] 2.3 Verify Android

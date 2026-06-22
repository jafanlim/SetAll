# Tasks

## 1. Stage 1 — capture (ship now)
- [x] 1.1 Migration: `insight_signal` + RLS (4 ops, `auth.uid()`); add to coverage matrix
- [x] 1.2 Add `shown` / `dismissed` / `expanded` / `followup` hook points to `InsightsScreen` and wallet (these do not exist yet — this task adds the wiring); emit `insight_signal` rows; no other behaviour change
- [ ] 1.3 Verify events recorded with correct user scoping on web; then iOS + Android

## 2. Stage 2 — loop (DEFERRED until usage signal exists)
- [ ] 2.1 Variant generator over the current `ai-analyst.js` prompt
- [ ] 2.2 Scorer: Spec 5 harness + behavior signal
- [ ] 2.3 Promotion rule (beats baseline on both; eval set untouched); log promotions in the ledger

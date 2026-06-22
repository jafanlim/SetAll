# Tasks

## 1. Web (Supabase-direct path)
- [x] 1.0 Spend source settled: `analyticsDataProvider` cannot be month-scoped externally (`_analyticsFilterProvider` is module-private). Decision recorded in design.md: use `getCategorySpend(from, to)` repo method filtering `getPersonalExpenses()`, exposed as `categorySpendProvider` family. setall-budgets owns this query.
- [x] 1.1 Migration: `budgets` table + RLS (select/insert/update/delete, `auth.uid()`); add to the Spec 3 coverage matrix
- [x] 1.2 Riverpod budget provider computing per-category current-month spend via the verified path from task 1.0, base-currency normalized; compare against `budgets.amount`
- [x] 1.3 Budget set/edit screen
- [x] 1.4 Progress indicators on insights + wallet (no unnecessary rebuilds)
- [ ] 1.5 Verify spend↔budget math across multiple currencies on web — NEEDS USER VERIFICATION at setall.app

## 2. Mobile
- [ ] 2.1 Port screens + provider
- [ ] 2.2 Verify iOS SQLite read path returns identical totals
- [ ] 2.3 Verify Android

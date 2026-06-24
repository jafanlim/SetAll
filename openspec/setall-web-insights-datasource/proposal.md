# Proposal: Web Insights Hub Reads Real Amounts (no-SQLite data source)

Status: OPEN — not started
Owner: TBD
Related code: `lib/features/insights/providers/insights_provider.dart` (L155-220,
`repo.getBalanceSummary()` L166, financial-data string L198-201),
`lib/data/repositories/setall_repository.dart` (web branches `_isWeb`, Supabase fallbacks),
`lib/data/local/local_database.dart`

## Why

The web build has **no SQLite** (sqflite is mobile/desktop only). Many repository reads assume a
local DB and only *fall back* to Supabase in some methods. On web, the Insights Hub never gets
proper amounts from the DB — the AI analyst is fed empty/zero financial data, so insights are
wrong or blank.

## Current Behaviour / Findings

- `insights_provider.dart` builds the analyst prompt from `repo.getBalanceSummary()` (L166) and a
  per-expense financial-data string (L198-201: `date category currency amount`).
- The repo is split by `_isWeb`. Some methods got explicit Supabase fallbacks (per `progress.md`:
  `getBalanceRawData` / `getGroupBalanceRawData` "fall back to Supabase when local SQLite is
  empty"), but this was done **method-by-method**. Any method feeding insights that lacks a web
  branch returns empty on web → zero amounts.
- So the bug is a **coverage gap**: not every data path the Insights Hub touches is web-aware.

## Proposed Approach

1. **Inventory** every repo method the Insights Hub (and analytics) calls:
   `getBalanceSummary`, `getExpenses`/wallet getters, totals, category breakdowns, rate
   conversion. Mark which have a web/Supabase path and which silently return empty on web.
2. **Make the data layer platform-uniform.** Two viable patterns — pick one:
   - **(A) Supabase-first on web** for all read paths (mirror the existing fallback pattern, but
     make it the *primary* on `_isWeb`, not an afterthought).
   - **(B) Web local cache** (e.g. IndexedDB via `sembast_web`/`drift` wasm) so the same
     "local-first, sync" model works on web. Bigger lift; better offline web UX.
   - Recommendation: **(A)** now (small, unblocks insights), consider (B) later if web offline
     matters.
3. **Single source for the analyst's numbers.** Have the insights provider pull from one
   web-aware aggregation method (e.g. `getInsightsDataset(baseCurrency, days)`) so there's no
   per-field drift between platforms.
4. **Verify currency conversion** runs on web too (universalUsdAmount × rateToBase) — zero rates
   on web would also zero out amounts.

## Scope

**In:** audit insights/analytics read paths, web-aware data source for all of them, single
aggregation entry point, rate-conversion-on-web check, manual verify on `setall.app`.
**Out:** rewriting the whole repo to drop SQLite on mobile; full web offline cache (option B is a
follow-up).

## Open Questions

- Option A vs B — does web need offline at all, or is always-online acceptable?
- Are RLS policies on `expenses`/`groups` sufficient for the web read queries the analyst needs?

## Tasks

- [ ] Inventory every repo method Insights Hub + analytics call; flag non-web-aware ones
- [ ] Implement web-aware reads (Supabase-first on web) for each gap
- [ ] Add single `getInsightsDataset()` aggregation used by the provider
- [ ] Verify rate conversion produces non-zero amounts on web
- [ ] Manual QA on https://setall.app: Insights Hub shows real totals
- [ ] Tests / smoke: web data source returns non-empty for a seeded account

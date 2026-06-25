# SetAll — Backlog & Phase-0 Branch Plan

_Maintained alongside `PROJECT_LEDGER.md`. Controller reads this to dispatch tasks._
_Updated: 2026-06-24._

## Branch policy

Two long-lived branches: **`main`** (releases) and **`develop`** (integration trunk).
Everything else is short-lived `feat/*` / `fix/*` off `develop`, PR'd in, deleted on merge.
Release = `develop → main`, tag `v*`, deploy. `Development-june` = current tip of new `develop`.

---

## Phase 0 — branch reconciliation

### A. Safe to delete now (0 ahead of main — fully merged, nothing unique)
bugfix/auth-hook-repair · bugfix/auth-ux-lifecycle · bugfix/emergency-hardening ·
bugfix/web-auth-comms · claude/unruffled-varahamihira-96c6a6 · feat/cash-position-pivot ·
feat/receipt-split-phase1 · feat/receipt-split-phase2 · feat/receipt-v2-ux ·
feature/activity-overhaul · feature/auth-architecture · feature/auth-core ·
feature/debt-simplification · feature/debt-simplification-greedy-algorithm ·
feature/final-authoritative-rollout · feature/final-polish-v2 · feature/final-resolution-rollout ·
feature/infra-v2-automation · feature/intelligence-and-legitimacy · feature/perf-hardening ·
feature/premium-desktop-ux · feature/production-ecosystem · feature/public-repo-safety ·
feature/settings-security-overhaul · feature/sqlite-foundation · feature/sqlite-integration ·
feature/universal-usd-migration · feature/usd-ledger-migration · feature/ux-and-auth-cleanup ·
feature/v2-2-analytics-and-l10n · feature/voice-entry · feature/wallet-overhaul ·
feature/wallet-section-and-batch-edit · fix/final-sweep · fix/hotfix-04-speech-to-text-windows ·
fix/monetary-integrity · fix/p54-multi-bugs · fix/reliability-pass · fix/sensory-haptics ·
legacy/initial-ios-debug · security-review-last-10-prs
**(~41 branches, local + origin)**

### B. Harvest done → delete
- cascade/prompt-4-…-050932 / -19525e / -ce6081 — 3 duplicate Cascade snapshots; their
  secret-rls-audit notes + RLS migrations are superseded by `fix/security-rls-audit` (already harvested).
- chore/infra-misc — only `.gitignore` + `CLAUDE.md` tweaks; cherry-pick if wanted, else drop.

### C. Integrate into `develop` THEN delete (real unmerged work — ordered by dependency)
1. ✅ **DONE** `fix/security-rls-audit` — RLS gap closure, edge-secret triggers, replay-safe migrations — merged to `develop` via PR #9 (2026-06-24). Follow-up: BACKLOG P1 hardening (search_path on edge-secret trigger fns).
2. ✅ **DONE** `chore/edge-fn-configs` — edge fn config.toml + RLS regression tests — merged to `develop` via PR #10 (2026-06-24). 18-assertion pgTAP RLS suite covers all 3 C-1 gaps.
3. ✅ **DONE (targeted, not a branch merge)** bug #3 fixed via `fix/group-identity-persistence` → merged to `develop` (PR #13, 2026-06-24, squash `b150a7a`). Migration `20260624000000`: `color_value`→`bigint` (ARGB overflow was the real root cause the spec missed), `default_currency` column added, `create_group` extended to set identity atomically, new `update_group_identity` RPC (creator-gated, SECURITY DEFINER, COALESCE for partial updates + `p_clear_avatar` flag). Dart: `createGroup`/`updateGroupCustomization` + sync push routed through RPCs, all swallowed `catch(_){}` removed; pull-merge COALESCE preserved. Controller caught + bounced ONE regression before merge (the edit-path RPC nulled untouched columns on partial edits — would have wiped icon/colour on avatar-only create calls).
   ⚠️ **`feature/groups-overhaul` (origin `5ad69df`) NOT purged** — it still carries ~735 lines of UNMERGED group-customization UI (create_group_screen +514, groups_screen, group_detail_screen, repo glue) that the targeted fix did NOT include. Keep-for-later-UI-task vs discard is a USER decision — do not delete until confirmed (see §E).
4. ✅ **DONE (surgical additive, NOT a cherry-pick)** `chore/shared-wiring` data-layer → merged to `develop` via PR #15 (2026-06-25, squash `550bccd`). Added ONLY the 15 genuinely-new repo methods (budgets/recurring/alerts/insights: getBudgets/upsertBudget/deleteBudget, getRecurringRules/insertRecurringRule/dismissRecurringRule/deleteRecurringRule, getAlertPrefs/upsertAlertPrefs/alertLogContains/insertAlertLog, insertInsightSignal, watchAllPayerExpenses/getAllPayerExpenses/getCategorySpend) + `netlifyIngestUrl` — verbatim from `bc7e056`, pure additions, zero existing lines touched (verified: counts delete_group/leave_group/original_amount/settled_by all match develop).
   ⚠️ **First attempt PR #14 was CLOSED by controller**: a full `git cherry-pick bc7e056` (54 behind) silently REVERTED develop's `rpc('delete_group')`/`rpc('leave_group')`, restoreExpense `original_amount` fix, and 4 `settled_by` lines (clean-but-stale merge, no conflict markers). Lesson: never wholesale-merge a stale branch — extract what's genuinely new. **`chore/shared-wiring` (origin `bc7e056`) NOT purged** — its providers (`setall_providers.dart`) + routes (`app_router.dart`) + screen edits for ingest/budget/recurring/alerts are the wiring each FEATURE PR (C-5/7/8/9) must re-add from `bc7e056` once that feature's screens/services land. See §E.
5. ✅ **DONE** `feat/wallet-csv-import` — bank-statement importer (bug #1) + tests → merged to `develop` via PR #16 (2026-06-25, squash `77811b9`). Cherry-pick `898abd5` (csv_adapter/ingest_row/ingest_service/import_ingest_screen/netlify ingest.js + 2 tests, `pdf-parse` dep) + harvested the ingest slice of `bc7e056` (ingestServiceProvider/IngestNotifier/ingestRowsProvider + `walletImport`→`ImportIngestScreen`). Controller bounced ONE regression: wallet-import conflict first kept develop's `addExpense(groupId:null)` (leaves `base_currency_amount` NULL) → corrected to TRUE UNION = develop dedup + `upsertWalletEntry` (freezes base_currency_amount). `setall_repository.dart` untouched; providers/router additive.
6. ✅ **DONE — SUPERSEDED (no merge needed)** `feat/soft-delete` — soft-delete / restore is **already on develop, more evolved**. develop's `setall_repository.dart` writes tombstones to `deleted_expenses` on delete + reads them on restore; `local_database.dart` creates the `deleted_expenses` table (LOCAL SQLite, offline-first) with more columns than the branch; the restore UI in `activity_screen.dart` uses a **365-day** window (branch had a stale 90-day); `test/integration/soft_delete_integrity_test.dart` covers it. Soft-delete is **deliberately local-only** (`sync_service.dart:739`: deleted rows are NOT pushed to Supabase). The branch (origin `ab998aa`, 58 behind) only adds: 5 **server-side** Supabase migrations creating a `public.deleted_expenses` table the app never reads/writes (a synced design develop rejected), stale i18n refactors of screens develop already evolved, and 2 i18n-key python scripts (C-10 territory). Cherry-picking it would revert develop + add an orphan server table → not integrated. Branch decision deferred to §E.
7. ✅ **DONE** `feat/recurring` — recurring-charge detection → merged to `develop` via PR #17 (2026-06-25, squash `f9fad76`). Cherry-pick `ac38e9b` (4 NEW files: recurring_candidate/recurring_detection_service/recurring_screen + `20260607000002_recurring_rules.sql` with full RLS) — clean, zero conflicts, no existing files touched. Harvested the recurring slice of `bc7e056`: `recurringCandidatesProvider` + `recurringRulesProvider` (providers) + `recurring`→`RecurringScreen` route (additive, zero deletions). **Money fix (controller-required):** branch stored amount as `double` → changed `RecurringCandidate.amount` to `Decimal`, service now emits `Decimal.parse(<real expense closest to modal>.amount)` (not the float `modalAmount`); screen displays via `formatAmountForCurrency` + persists `amount.toString()`; internal ±10% clustering / `confidence` stay `double` (heuristics, not stored). `setall_repository.dart` untouched; revert-guard tokens all match. analyze green, 343/343 tests. **Entry-point settings tile deferred to C-10** (needs `settings_ext.recurring*` keys; route reachable now).
8. `feat/budget` — monthly budgets
9. `feat/alerts-insights` — proactive alerts + insight signals
10. `chore/i18n-keys` — translations covering all the above (do near-last). **ALSO add the deferred settings entry-point tiles** harvested from `bc7e056` settings_screen (~lines 643-659): `recurring`→`AppRouter.recurring` (C-7), `budgets`→`AppRouter.budgets` (C-8), `alertPrefs`→`AppRouter.alertPrefs` (C-9), with their `settings_ext.*` keys — these were deferred from C-7/8/9 to land together with the i18n keys they need.
11. `feature/website-2-0-integration` — portal/login/legal (independent; can parallel)
12. `fix/crit-01-ai-provider-cache` — AI 15-min cache (drop the stray journals it carries)
13. ✅ **DONE** `chore/chat-eval` — promptfoo chat eval cases — merged to `develop` via PR #12 (2026-06-24). Doubled as the live verification of the ai-eval CI fix.

**Gate:** each integration is its own PR into `develop`, must pass `flutter analyze` (exit 0)
before merge (see memory `flutter-analyze-gate-worktree`). Expect conflicts between
groups-overhaul / shared-wiring / i18n-keys — integrate in the order above.

### D. Reset / rename
- ~~`develop` (374 behind, 0 ahead) → hard-reset to `origin/main`~~ **DONE / superseded**:
  `develop` is already the integration trunk = `origin/main` + planning commit, and equals
  `Development-june`. **Do NOT hard-reset develop** — it is live and ahead of main. (Verified 2026-06-24.)
- After C completes and `develop` is verified, merge `develop → main` and re-tag.

### E. Deferred branch decisions (USER call — do not auto-delete)
- **`feature/groups-overhaul`** (origin `5ad69df`) — bug #3 (identity persistence) was fixed
  separately in C-3 (PR #13), but this branch still holds ~735 lines of UNMERGED group-customization
  **UI**: `create_group_screen.dart` (+514), `groups_screen.dart`, `group_detail_screen.dart`, repo glue.
  427 behind, conflicts in 7/8 files vs develop. **Decision pending:** (a) keep as a future
  "group-customization UI overhaul" task and integrate later, or (b) discard as superseded/stale.
  Not purged until the user decides.
- **`feat/soft-delete`** (origin `ab998aa`) — soft-delete is already on develop (C-6 superseded). The branch's
  ONLY non-stale content is 5 **server-side** Supabase migrations for a synced `public.deleted_expenses` table.
  develop chose **local-only** soft-delete (tombstones never leave the device — `sync_service.dart:739`). So the
  branch represents an UNBUILT capability: **cross-device / post-reinstall restore** (server-persisted tombstones).
  **Decision pending:** (a) keep the branch as a future "cloud restore" product task, or (b) discard as a rejected
  design. Default = keep. Not purged until the user decides.
- **`chore/shared-wiring`** (origin `bc7e056`) — KEEP until C-9 done. Its data-layer is on develop (C-4/PR #15),
  but its **providers + routes + screen edits** for ingest/budget/recurring/alerts were deliberately NOT
  taken (they reference screens/services that arrive with the feature branches). Each feature PR must harvest
  its slice from `bc7e056`:
  - ✅ **C-5 ingest — HARVESTED** (PR #16, 2026-06-25): `ingestServiceProvider`/`IngestNotifier`/`ingestRowsProvider` + `walletImport`→`ImportIngestScreen` route on develop.
  - ✅ **C-7 recurring — HARVESTED** (PR #17, 2026-06-25): `recurringCandidatesProvider` + `recurringRulesProvider` + `recurring`→`RecurringScreen` route on develop.
  - ⬜ C-8 budget → `budgets`→`BudgetsScreen` route;
  - ⬜ C-9 alerts → `alertServiceProvider`/`alertPrefsProvider`/`alertQueueProvider` + `alertPrefs`→`AlertPrefsScreen` route.
  Purge `chore/shared-wiring` only after C-7/8/9 have all landed.

---

## Product backlog (dispatch to DeepSeek via controller)

### P0 — integration queue
See Phase-0 section C above (one task per branch, in order).

### P1 — bug fixes (specs in `openspec/`)
- **net-balance-offset** — A↔B mutual debts net to zero, not double-counted. (correctness; no spec yet — small)
- **group-identity-persistence** — icon/colour stick across sync (pair with groups-overhaul integration)
- **statement-multi-import** — reconcile with wallet-csv-import; split + dedupe + dates
- **shared-expense-wallet-share** — opt-in mirror of my share into wallet
- **web-insights-datasource** — web reads real amounts (no SQLite)
- **push-and-digest** — verify + fix push and monthly digest end-to-end

### P2 — carried TODOs
- ghost-row nickname FK violation (`pending_invites`)
- Google OAuth in-app browser auto-close
- group invite search (email/nickname) returns nothing
- "settled up" stale after account switch

### Discovered during Phase-0 integration (new follow-ups)
- **ci-ai-eval** — ✅ **INFRA FIXED 2026-06-24.** Was failing 9/9 (never ran). Three causes fixed: (1) gitignored `package-lock.json` → committed (PR #11); (2) sandboxed-npm lockfile drift vs CI npm (`gcp-metadata` 8.1.2 vs 7.0.1) → workflow switched `npm ci`→`npm install` (commit `e00ffe7`); (3) missing `GROQ_API_KEY` secret → user added it. CI now runs: install 37s, eval executes all 28 cases. **Remaining (separate, content not infra):** 3/28 assertions fail (`25 passed 89.29%`, exit 100). → new follow-up `ai-eval-3-failing-cases`: triage the 3 failing promptfoo cases (likely strict/flaky LLM asserts); decide fix-or-loosen. Not a required check.
- **edge-fn-secret-enforcement** (security, P1) — 7 edge fns deploy `verify_jwt=false` with NO `x-edge-secret` check in body → publicly invokable: bug-triage, monthly-digest, notify-group-invite, send-group-notification, send-test-email, sync-exchange-rates, weekly-analysis. C-1 made the DB triggers SEND `x-edge-secret`, but the functions don't VERIFY it → notification spoofing / Groq+email quota abuse. Add header check (exempt the 2 Auth-hook fns: send-email, send-welcome-email).
- **edge-secret-search-path** (hardening, from C-1) — `trigger_bug_triage()` + `notify_group_members()` are SECURITY DEFINER without `SET search_path = public` (Supabase `function_search_path_mutable` advisor). Also guard the two `cron.unschedule(...)` calls in `20260601000001`.

---

## Definition of done (every task)
1. Branch off `develop`. 2. `flutter analyze` exit 0. 3. Tests where applicable.
4. PR into `develop` with spec reference. 5. Update `PROJECT_LEDGER.md` + this file.
6. Use `Decimal`/integer-cents for money. 7. RLS on all new tables; never expose service_role.

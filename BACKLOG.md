# SetAll — Backlog & Phase-0 Branch Plan

_Maintained alongside `PROJECT_LEDGER.md`. Controller reads this to dispatch tasks._
_Updated: 2026-06-25 (Phase-1 task queue; TASK 1 edge-key-completion code-done PR #26, live-verify pending)._

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
8. ✅ **DONE** `feat/budget` — monthly budgets per category → merged to `develop` via PR #18 (2026-06-25, squash `04c6ad9`). Clean cherry-pick of `166c675` (NEW budgets_screen + `20260607000001_budgets.sql` with full RLS + a `wallet_screen.dart` budget edit that applied with ZERO conflicts — develop's wallet_screen was byte-identical to the branch parent). Harvested the budget provider section of `bc7e056`: `categorySpendProvider` (also read by C-9 alerts) + `budgetsProvider` + `BudgetProgress` class + `budgetProgressProvider` + `budgets`→`BudgetsScreen` route (additive, zero deletions). **No money fix needed** — already Decimal-correct (input `Decimal.tryParse`→persist `amount.toString()`; `BudgetProgress.amount/spend` Decimal; only `fraction` is double). `setall_repository.dart` untouched; revert-guard matches. Reachable via the wallet "Budget →" link. analyze green, 343/343 tests.
9. ✅ **DONE** `feat/alerts-insights` — proactive alerts + insight signals → merged to `develop` via PR #19 (2026-06-25, squash `ab00f52`). Cherry-pick of `c8a94e3` (NEW alert_service/alert_prefs_screen/alert_banner + 2 RLS migrations `20260608000001_proactive_alerts` (alert_prefs+alert_log) / `20260608000002_insight_signal`; MODIFIED adaptive_shell (AlertBannerOverlay wrap), add_expense_screen (`_runAlertChecks` trigger), insights_provider (insertInsightSignal tracking)). ONE small conflict in insights_provider resolved correctly: kept develop's Dart-3 `'context': ?contextPayload` AND folded in the 3 `insertInsightSignal` calls (both verified present). Harvested the alert slice of `bc7e056`: `alertServiceProvider`/`alertPrefsProvider`/`AlertQueueNotifier`/`alertQueueProvider` + `alertPrefs`→`AlertPrefsScreen` route (additive; no dup of budget/recurring/ingest providers). **Money fix (controller-required):** budget threshold `double.tryParse(limit)`+`spend.toDouble()/limit`+`pct>=` → Decimal (`spend >= limit` / `spend >= limit * Decimal.parse('0.8')`); anomaly threshold `mean.toDouble()*k` → `mean * Decimal.tryParse(anomalyK)`. Only `anomalyK` (sensitivity coefficient) stays double. `setall_repository.dart` untouched; revert-guard matches. analyze green, 343/343 tests. **Entry-point settings tile deferred to C-10** (`settings_ext.alertPrefs*` keys; route reachable now).
10. ✅ **DONE** `chore/i18n-keys` — i18n key union + 3 settings entry-tiles → merged to `develop` via PR #20 (2026-06-25, squash `8da8d6b`). NOT a cherry-pick (branch `42967d0` was 65 behind — would have dropped develop's 40 `receipt.*` keys + reverted an already-i18n'd screen). Instead an **additive key union**: 107 missing keys (ingest 29 / expense_detail 19 / alerts 19 / budget 14 / activity_screen 9 / recurring 9 / settings_ext 6 / wallet_screen 2) added to all 6 locales via throwaway script (deleted, not committed), real translations where the branch had them + English fallback for the 31 EN-only keys. Controller-verified invariants on PR head: lost=0, valChanged=0, new107=107, `receipt.*`=40 (0 changed) for ALL 6 locales; only parity gap is the pre-existing `dashboard.personal_wallet_title` (not introduced). **Part B:** the 3 deferred settings entry-tiles (`budgets`→`AppRouter.budgets`, `recurring`→`AppRouter.recurring`, `alertPrefs`→`AppRouter.alertPrefs`, `settings_ext.*` labels) added to develop's settings_screen via the existing `_NavRow` pattern (0 deletions — additive). **NOT taken:** stale `group_expense_detail_screen.dart` (develop already references `expense_detail.*` 15×) + 8 `scripts/add_*_keys.py` (one-shot generators). analyze green, 343/343 tests.
11. ⚠️ **SUPERSEDED — no dispatch** `feature/website-2-0-integration` (origin `d5ca365`, 5 ahead / **351 behind**). develop ALREADY has Website 2.0 and evolved it far past this branch. Recon (2026-06-25): all 5 "new" pages (login/portal/privacy/support/terms.html) already exist on develop (add/add conflicts); the full merge conflicts in ALL 9 files; develop's `login.html` references `portal` 3× (login→portal wired) vs the branch's 0×; develop's Makefile already builds from `web/app.html` (same 3 refs); develop's web pages are newer/bigger on 5 of 7 (index 578 vs 197, privacy 302 vs 187, terms 297 vs 198, support 211 vs 164, download 486 vs 471); develop's web history shows full i18n (6 locales), portal group-spending cards, insights AI currency conversion, password-reset page — all post-dating this branch; `production_legitimacy_test` is tuned to develop's 9-page site. Merging would silently revert develop's web work + break login→portal. **Same call as C-6.** Branch keep/discard deferred to USER (BACKLOG §E, default keep).
12. ✅ **DONE** `fix/crit-01-ai-provider-cache` — AI 15-min cache → merged to `develop` via PR #21 (2026-06-25, squash `d4ad8d0`). NOT a cherry-pick (branch `9d0536e` 271 behind + carried 2 stray journals `projectledger.md`/`wiki doc.md`). Surgical hand-application of the ~11-line fix onto develop's current `dashboard_screen.dart`: `import 'dart:async'` + a `ref.keepAlive()` link + 15-min `Timer(() => link.close())` + `ref.onDispose(cancel)` inserted at the top of `_aiInsightProvider` (kept `autoDispose`). Fixes the AI-insight re-fetch on every Dashboard revisit. develop had ZERO keepAlive before (CRIT-01 genuinely unfixed). Diff = single file, 0 deletions; stray journals NOT taken. analyze green, 343/343 tests.
13. ✅ **DONE** `chore/chat-eval` — promptfoo chat eval cases — merged to `develop` via PR #12 (2026-06-24). Doubled as the live verification of the ai-eval CI fix.

**Gate:** each integration is its own PR into `develop`, must pass `flutter analyze` (exit 0)
before merge (see memory `flutter-analyze-gate-worktree`). Expect conflicts between
groups-overhaul / shared-wiring / i18n-keys — integrate in the order above.

### D. Reset / rename
- ~~`develop` (374 behind, 0 ahead) → hard-reset to `origin/main`~~ **DONE / superseded**:
  `develop` is already the integration trunk = `origin/main` + planning commit, and equals
  `Development-june`. **Do NOT hard-reset develop** — it is live and ahead of main. (Verified 2026-06-24.)
- ✅ **DONE (2026-06-25):** `main` fast-forwarded to `develop` (`e120315` → `fff1b9d`, clean 34-commit ff, NO version
  tag → no release-build CI). main == develop == `fff1b9d`. No re-tag/release yet (user chose "FF now, no tag");
  a `v*` release tag remains a separate future action when shipping.

### Phase-0 CLOSE-OUT — ✅ COMPLETE (2026-06-25)
All Phase-0 integration done (11 merged, 2 superseded). Remote cleaned to **only `main` + `develop`** (both `fff1b9d`).
Every purged branch is preserved as an `archive/<name>` tag (recoverable: `git switch -c <name> archive/<name>`).
**13 archive tags pushed to remote:**
| archive tag | SHA | was |
|---|---|---|
| archive/group-identity-persistence | 056f815 | fix/group-identity-persistence (C-3) |
| archive/shared-wiring-datalayer | e5e216b | chore/shared-wiring-datalayer (C-4 source) |
| archive/shared-wiring | bc7e056 | chore/shared-wiring (wiring source) |
| archive/wallet-csv-import | 898abd5 | feat/wallet-csv-import (C-5) |
| archive/recurring | ac38e9b | feat/recurring (C-7) |
| archive/budget | 166c675 | feat/budget (C-8) |
| archive/alerts-insights | c8a94e3 | feat/alerts-insights (C-9) |
| archive/i18n-keys | 42967d0 | chore/i18n-keys (C-10) |
| archive/crit-01-ai-provider-cache | 9d0536e | fix/crit-01-ai-provider-cache (C-12) |
| archive/integrate-shared-wiring | 2d20ca7 | integrate/shared-wiring (scratch) |
| archive/groups-overhaul | 5ad69df | feature/groups-overhaul (deferred UI) |
| archive/soft-delete | ab998aa | feat/soft-delete (deferred cloud-restore) |
| archive/website-2-0-integration | d5ca365 | feature/website-2-0-integration (superseded) |

**4 ancestor branches deleted WITHOUT a tag** (permanently reachable from `develop`'s history, so no tag needed):
`fix/security-rls-audit` (4887203, C-1), `chore/edge-fn-configs` (b3e84c5, C-2), `chore/chat-eval` (df70e9f, C-13),
`Development-june` (4517fcf, old integration trunk).

### E. Deferred branch decisions — ✅ RESOLVED (2026-06-25): user said delete all; archived + branches deleted
- **`feature/groups-overhaul`** (origin `5ad69df`) — bug #3 (identity persistence) was fixed
  separately in C-3 (PR #13), but this branch still holds ~735 lines of UNMERGED group-customization
  **UI**: `create_group_screen.dart` (+514), `groups_screen.dart`, `group_detail_screen.dart`, repo glue.
  427 behind, conflicts in 7/8 files vs develop. ✅ **RESOLVED (2026-06-25): branch DELETED** (user chose delete-all);
  code preserved as tag **`archive/groups-overhaul`** (5ad69df). NOTE: this UI was NOT on develop — to revisit the
  group-customization overhaul, resurrect from the tag: `git switch -c groups-overhaul archive/groups-overhaul`.
- **`feat/soft-delete`** (origin `ab998aa`) — soft-delete is already on develop (C-6 superseded). The branch's
  ONLY non-stale content is 5 **server-side** Supabase migrations for a synced `public.deleted_expenses` table.
  develop chose **local-only** soft-delete (tombstones never leave the device — `sync_service.dart:739`). So the
  branch represents an UNBUILT capability: **cross-device / post-reinstall restore** (server-persisted tombstones).
  ✅ **RESOLVED (2026-06-25): branch DELETED** (user chose delete-all); code preserved as tag **`archive/soft-delete`**
  (ab998aa). NOTE: the server-side cross-device-restore migrations were NOT on develop (develop is local-only) — to build
  "cloud restore" later, resurrect from the tag: `git switch -c soft-delete archive/soft-delete`.
- **`feature/website-2-0-integration`** (origin `d5ca365`, 351 behind) — **SUPERSEDED** (C-11). develop already shipped
  Website 2.0 and evolved it far beyond this branch (full i18n in 6 locales, portal group-spending cards, insights AI
  currency conversion, password-reset page, `web/app.html` build, the 9-page `production_legitimacy_test`). The branch holds
  nothing develop lacks — its login.html doesn't even wire login→portal (develop's does). ✅ **RESOLVED (2026-06-25):
  branch DELETED** (superseded; user chose delete-all). Code preserved as tag **`archive/website-2-0-integration`** (d5ca365)
  in the unlikely event the old static-storefront markup is ever wanted.
- **`chore/shared-wiring`** (origin `bc7e056`) — KEEP until C-9 done. Its data-layer is on develop (C-4/PR #15),
  but its **providers + routes + screen edits** for ingest/budget/recurring/alerts were deliberately NOT
  taken (they reference screens/services that arrive with the feature branches). Each feature PR must harvest
  its slice from `bc7e056`:
  - ✅ **C-5 ingest — HARVESTED** (PR #16, 2026-06-25): `ingestServiceProvider`/`IngestNotifier`/`ingestRowsProvider` + `walletImport`→`ImportIngestScreen` route on develop.
  - ✅ **C-7 recurring — HARVESTED** (PR #17, 2026-06-25): `recurringCandidatesProvider` + `recurringRulesProvider` + `recurring`→`RecurringScreen` route on develop.
  - ✅ **C-8 budget — HARVESTED** (PR #18, 2026-06-25): `categorySpendProvider` + `budgetsProvider` + `BudgetProgress` + `budgetProgressProvider` + `budgets`→`BudgetsScreen` route on develop.
  - ✅ **C-9 alerts — HARVESTED** (PR #19, 2026-06-25): `alertServiceProvider`/`alertPrefsProvider`/`AlertQueueNotifier`/`alertQueueProvider` + `alertPrefs`→`AlertPrefsScreen` route on develop.
  **✅ FULLY HARVESTED + PURGED (2026-06-25).** All four slices (ingest C-5, recurring C-7, budget C-8, alerts C-9) + the data layer (C-4) + the settings entry-tiles (C-10) are on develop. `origin/chore/shared-wiring` was **deleted** after C-10 merged; the SHA `bc7e056` is preserved as tag **`archive/shared-wiring`** (pushed) so this ledger's line-number citations stay resolvable. Nothing further to do here.

---

## Product backlog (dispatch to DeepSeek via controller)

### P0 — integration queue
See Phase-0 section C above (one task per branch, in order).

### P1 — bug fixes (specs in `openspec/`)

> **Phase-1 task queue (formalized 2026-06-25):** TASK 1 `setall-edge-key-completion` (P0 LEAD) — **CODE DONE PR #26,
> live-verify pending** · TASK 2 `push-and-digest` (blocked on TASK 1 live-verify) · TASK 3 `net-balance-offset`
> (already fixed — see below) · TASK 4 `web-insights-datasource` · TASK 5 `shared-expense-wallet-share` ·
> TASK 6 `statement-multi-import` (reconcile) · TASK 7 carried P2 TODOs. Full status table: PROJECT_LEDGER §4.

- ✅ **DONE (already fixed — controller recon 2026-06-25)** **net-balance-offset** _(TASK 3)_ — A↔B mutual debts net to zero. The fix is live: `balance_service.dart:50` nets `net = rawOwed − rawOwe` (then zeroes the smaller side) at BOTH global and per-group level — introduced in `2ccbf76` ("split math fixes"). Covered by `engine_torture_test` TEST 2 (summary-level: owed $50 / owe $20 → `youAreOwed 30.00`, `youOwe 0.00`) + TEST 3 (anchor-equal → 0.00), plus the settlement engine's per-pair netting (`repository_crud_test:866`, `engine_regression_guard 2a`). No dispatch needed. (Minor leftover: `friends_screen.dart:331`'s `owed>0 && owe>0` branch is now dead post-netting — harmless cosmetic cleanup, not the bug.)
- ✅ **DONE** **group-identity-persistence** — icon/colour stick across sync → resolved by C-3 (`fix/group-identity-persistence`, PR #13, migration `20260624000000`: `color_value`→bigint + atomic `create_group` + `update_group_identity` RPC). The "pair with groups-overhaul" note is moot (groups-overhaul archived/deleted).
- **statement-multi-import** _(TASK 6)_ — reconcile with wallet-csv-import; split + dedupe + dates
- **shared-expense-wallet-share** _(TASK 5)_ — opt-in mirror of my share into wallet
- **web-insights-datasource** _(TASK 4)_ — web reads real amounts (no SQLite)
- **push-and-digest** _(TASK 2)_ — verify + fix push and monthly digest end-to-end. **BLOCKED on TASK 1 live-verify** (digest cron rides the same apikey path).

### P2 — carried TODOs
- ghost-row nickname FK violation (`pending_invites`)
- Google OAuth in-app browser auto-close
- group invite search (email/nickname) returns nothing
- "settled up" stale after account switch — ✅ **DONE (P1-D)** → merged to `develop` via PR #28 (2026-06-26, squash `de17765`). `lib/app.dart` `_invalidateAllProviders()` was omitting the per-group/wallet/master providers (`groupBalanceSummaryProvider` family drives the per-group "Settled up" badge); added the 9 missing financial providers + made the post-sync re-invalidation comprehensive on switch/first-login only (token-refresh stays cheap). Controller re-implemented independently (DeepSeek's diff matched spec but was unpushed + done in the canonical repo); analyze 0, 343/343.

### Discovered during Phase-0 integration (new follow-ups)
- **ci-ai-eval** — ✅ **INFRA FIXED 2026-06-24.** Was failing 9/9 (never ran). Three causes fixed: (1) gitignored `package-lock.json` → committed (PR #11); (2) sandboxed-npm lockfile drift vs CI npm (`gcp-metadata` 8.1.2 vs 7.0.1) → workflow switched `npm ci`→`npm install` (commit `e00ffe7`); (3) missing `GROQ_API_KEY` secret → user added it. CI now runs: install 37s, eval executes all 28 cases. **Remaining (separate, content not infra):** 3/28 assertions fail (`25 passed 89.29%`, exit 100). → new follow-up `ai-eval-3-failing-cases`: triage the 3 failing promptfoo cases (likely strict/flaky LLM asserts); decide fix-or-loosen. Not a required check.
- **edge-fn-secret-enforcement** (security, P1) — 7 edge fns deploy `verify_jwt=false` with NO `x-edge-secret` check → publicly invokable (notification spoofing / Groq+email quota abuse). C-1 made the DB triggers SEND `x-edge-secret`; the functions didn't VERIFY it.
  - ✅ **4 of 7 DONE.** PR #23 (2026-06-25, squash `53d10a9`): `bug-triage`, `monthly-digest`, `send-group-notification` — `x-edge-secret`/`EDGE_SHARED_SECRET` fail-closed gate (after OPTIONS, before work). PR #24 (2026-06-25, squash `59e26b1`): `weekly-analysis` — **dual-mode** gate (`x-edge-secret` cron OR valid user JWT via `admin.auth.getUser(token)`); fail-closed 401; JWT path pinned to the authed user (`onDemandUid = authedUid`) so an authenticated user can't run another user's analysis nor the full batch. Controller-verified each: exact single-file diffs, deferred fns untouched, `deno check` + analyze + 343 tests green. **⚠ OPS REQUIRED before redeploy:** `supabase secrets set EDGE_SHARED_SECRET=<vault edge_shared_secret value>` then `supabase functions deploy bug-triage monthly-digest send-group-notification weekly-analysis` — else cron/triggers 401 (no bug-triage email / group notifications / monthly digest / weekly analysis). weekly-analysis app on-demand path keeps working on user JWT regardless.
  - ✅ **KEY-MIGRATION APPLIED + VERIFIED — PR #26 + #27 (TASK 1); gateway 403 ELIMINATED (2026-06-26).** Was: legacy `anon`/`service_role` JWT keys disabled on prod → edge-fn logs **403** (gateway, not our 401) on `send-group-notification`, `sync-exchange-rates`, etc.; (a) triggers sent only `x-edge-secret` — no `apikey` → gateway 403; (b) all 5 trigger/cron fns built `createClient(URL, SUPABASE_SERVICE_ROLE_KEY)` = dead key. **Fixed:** PR #26 (`3c71e2e`) migration `20260625010000` + 5-fn SECRET_KEYS swap; PR #27 (`1751935`) migration `20260625020000` for the 3 sites #26 missed (`on_profile_created`→welcome-email, `hook_send_email`→send-email, `sync-exchange-rates-daily` cron's `Bearer <SERVICE_ROLE_KEY>` placeholder). **Applied to prod** (controller via MCP `apply_migration` + CLI deploy): all **7 DB call sites carry apikey**; 5 fns redeployed `verify_jwt=false` (caught 3 drifted to `true`); digest live-test confirms **403 gone** (reaches the function). **➡ 1 blocker left, see next bullet.** Full openspec: `openspec/changes/setall-edge-key-completion/`.
  - ✅ **LIVE-VERIFIED 2026-06-26 — digest test 200 `{"sent":1}`, email delivered.** The 401 had 2 causes, both fixed: (1) `EDGE_SHARED_SECRET` (fn env) had to equal Vault `edge_shared_secret` — set via Dashboard (the `supabase secrets list` digest is CACHED — kept showing stale `64f6…`; a throwaway `edge-secret-debug` fn proved `match:true`/sha `803e3f1c…`, then deleted); (2) **STALE ISOLATES** — Supabase injects fn secrets at isolate BOOT, so the fns (deployed before the secret was fixed) kept the old value until **redeployed**. Lesson: redeploy fns after changing any secret they read. **TASK 1 CLOSED; the 4 gated fns (bug-triage/monthly-digest/send-group-notification/weekly-analysis) share the identical pattern + were redeployed together. TASK 2 (push-and-digest) now UNBLOCKED.**
  - ⬜ **Deferred 3 (BLOCKED behind key-migration above; each also needs more than an x-edge-secret-only gate — controller triage 2026-06-25):**
    - `send-test-email` — app-invoked from `settings_screen.dart` (user JWT). Needs a JWT/auth guard, or restrict to authenticated admins/dev-only.
    - `sync-exchange-rates` — ✏️ **CORRECTED 2026-06-26:** it's an **internal pg_cron** (`sync-exchange-rates-daily`, `0 6 * * *`), NOT an external scheduler; its header was a literal un-substituted `Bearer <SERVICE_ROLE_KEY>` placeholder → now carries the Vault `apikey` (PR #27). The fn has no x-edge-secret gate (apikey alone clears the gateway). If a body gate is later wanted, the cron must add `x-edge-secret` too.
    - `notify-group-invite` — **no known caller** anywhere (no trigger/cron/app/edge-fn ref). Hunt the caller first; if genuinely dead, consider removal; if invoked, gate per its auth.
  - (`send-email` / `send-welcome-email` stay EXEMPT — Auth hooks, documented "do NOT add x-edge-secret".)
- ✅ **DONE** **edge-secret-search-path** (P1 hardening, from C-1) → merged to `develop` via PR #22 (2026-06-25, squash `55ebad1`). New migration `20260625000000_harden_definer_search_path.sql` recreates `trigger_bug_triage()` (body from `20260601000001`) + `notify_group_members()` (body from `20260601000003`) with `LANGUAGE plpgsql / SECURITY DEFINER / SET search_path = public` headers — clears the Supabase `function_search_path_mutable` advisor. Controller-verified: both bodies BYTE-IDENTICAL to their authoritative defs (no behavior drift; all cross-schema refs `net.`/`vault.`/`public.` already qualified), exactly 2 functions recreated, 0 applied migrations edited (checksums intact), analyze + 343 tests green. `db lint` not run (no local DB). **Deferred (separate follow-up):** the `cron.unschedule(...)` idempotency guard in `20260601000001` — low-risk (only bites isolated/out-of-sequence migration runs); not touched to avoid editing an applied migration's checksum.

---

## Definition of done (every task)
1. Branch off `develop`. 2. `flutter analyze` exit 0. 3. Tests where applicable.
4. PR into `develop` with spec reference. 5. Update `PROJECT_LEDGER.md` + this file.
6. Use `Decimal`/integer-cents for money. 7. RLS on all new tables; never expose service_role.

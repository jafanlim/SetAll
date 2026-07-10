# SetAll — Project Ledger (single source of truth)

> **STATUS 2026-06-25 — Phase-0 COMPLETE.** All 13 §C branches resolved (11 merged, 2 superseded). `main` fast-forwarded
> to `develop`; both trunks = `fff1b9d`. Remote pruned to **only `main` + `develop`**; the 16 integrated/deferred branches
> were deleted, with 13 preserved as `archive/*` tags (see BACKLOG §"Phase-0 CLOSE-OUT" for the tag↔SHA index) and 4
> ancestors reachable from develop. **Next: Phase 1 (P1/P2 bug fixes), branched off `develop` as before.**

_Last updated: 2026-06-25. This file supersedes and consolidates the scattered journals:_
_`progress.md`, `project ledger.md`, `projectledger.md` (was on fix/crit-01), `wiki doc.md`,_
_`BACKEND_STATUS.md`, `IMPLEMENTATION_CHECKLIST.md`, `session_feb27_2026.md`,_
_`how workflow implemented.md`, `debug_protocol.md`, `docs/session-*.md`._
_Those are kept for history under `.context/ledger-sources/` but are no longer maintained._
_Update THIS file going forward._

---

## 1. What SetAll is

Flutter (mobile + web + desktop) shared-expense / personal-finance app on Supabase.
- **Aesthetic:** "System-Slate" — `#0F172A` bg, `#14B8A6`/`#00D9B0` teal, system fonts.
- **Storefront:** pure HTML/CSS at `setall.app`; the Flutter app is bridged at `/app.html`.
- **Backend:** Supabase (Postgres + Auth + RLS + Edge Functions). AI via Netlify functions
  (`receipt-ingest`, `voice-entry`, `ai-analyst`) and Supabase edge functions.
- **Money rule:** integer cents / `Decimal` everywhere — never float. Universal-USD ledger;
  per-expense `original_amount` / `original_currency` / `exchange_rate_applied`.
- **Data model:** offline-first. Local SQLite (mobile/desktop) is primary; writes go local
  first (`synced_at = NULL` = pending) then sync to Supabase. **Web has no SQLite** — it must
  read Supabase directly (the repo's `_isWeb` paths do this; bug #4 confirmed resolved, PR #42).

## 2. Release state

- **Shipped: v1.8.0 (`1.8.0+35`)** — 2026-06-27. `main` fast-forwarded to `develop` (`00c5365`),
  tagged `v1.8.0` (CI: Android/macOS/Windows + GitHub Release; iOS manual). **Web deployed live to
  setall.app** via `make build-web` + `netlify deploy --prod`. Contents = the Phase-1 wave: edge-key
  migration completion (live-verified), budgets, recurring detection, proactive alerts/insight signals,
  wallet bank-statement import + dedupe, shared-expense→wallet mirror, web-insights datasource,
  net-balance netting, group-identity persistence, soft-delete, CRIT-01 AI cache, P2 QA sweep
  (ghost-FK, OAuth browser close, invite search, account-switch refresh), web pdfx fix, restored
  landing-page legal footer + schema.org. **Known follow-up:** push-notification *delivery* to a
  device still unverified (FCM token registration fixed; digest email verified).
- **Prev: v1.7.0 (`1.7.0+34`)**, merged to `main` (61d86a5), tagged `v1.7.0`.
  Contents: AI receipt ingest, **receipt-split phases 1–2** (itemized line-items: persist,
  detail view, editable breakdown, entry-type chooser), import dedupe + transaction-date
  preservation, Google Vision OCR pre-pass, voice entry, USD-ledger migration, debt
  simplification (greedy), basic group customization, sync hardening.
- Release runbook: tag `v*` → CI (Android/macOS/Windows + GitHub Release); iOS + web manual.
  See memory `setall-release-runbook`.

## 3. ⚠️ Unmerged feature wave (the integration queue)

These are **built and living in branches but NOT on main**. v1.7.0 shipped only receipt-split;
the rest of the "spring wave" never landed. This is the real Phase-0 work.

| Feature | Branch | ~Lines | Spec | Notes |
|---|---|---|---|---|
| Bank-statement / CSV import | `feat/wallet-csv-import` | 2060 | ingestion-pipeline, wallet-import-parity | The real fix for bug #1; has tests + `netlify/ingest.js` |
| Recurring charge detection | `feat/recurring` | 818 | recurring-detection | service + screen + migration |
| Monthly budgets | `feat/budget` | 657 | budgets | budgets_screen + migration |
| Proactive alerts + insight signals | `feat/alerts-insights` | 1148 | proactive-alerts, insight-self-improvement | 2 migrations |
| Soft-delete / 90-day restore | `feat/soft-delete` | 205 | — | deleted_expenses tables + RLS |
| Group customization (fuller) | `feature/groups-overhaul` | 735 | — | **incl. migration `20260312000004_group_identity_columns.sql`** — likely the missing piece for bug #3 |
| Website 2.0 (portal/login/legal) | `feature/website-2-0-integration` | 2272 | — | 5 commits |
| Shared wiring (repo/router/providers) | `chore/shared-wiring` | 1172 | — | integration glue many feats depend on |
| i18n keys (6 locales) | `chore/i18n-keys` | 1197 | — | translations for the wave |
| RLS gap closure + edge-secret triggers | `fix/security-rls-audit` | 460 | secret-rls-audit | migrations |
| Edge-fn config.toml + RLS regression tests | `chore/edge-fn-configs` | — | — | infra |
| AI provider 15-min cache | `fix/crit-01-ai-provider-cache` | — | — | CRIT-01 |
| Chat eval cases | `chore/chat-eval` | — | — | promptfoo |

**These branches overlap** (i18n-keys, shared-wiring, groups-overhaul touch the same files) and
have interdependencies — they must be integrated in order, into `develop`, each behind the
`flutter analyze` green gate, not merged blindly.

**Phase-0 integration progress:** ✅ **COMPLETE (2026-06-25)** — all 13 §C items resolved: 11 merged to `develop`
(C-1, C-2, C-3, C-4, C-5, C-7, C-8, C-9, C-10, C-12, C-13), 2 determined SUPERSEDED with no dispatch (C-6 soft-delete,
C-11 website-2-0). develop tip = `d4ad8d0`. Merged branches purged; `bc7e056` archived as tag `archive/shared-wiring`.
**Next = Phase-0 close-out:** (1) align `main ← develop` (currently main `e120315`, develop `d4ad8d0`); (2) USER keep/discard
on the 3 deferred §E branches (`feature/groups-overhaul`, `feat/soft-delete`, `feature/website-2-0-integration`). Then Phase 1.

- ✅ C-1 `fix/security-rls-audit` → merged to `develop` (PR #9, 2026-06-24). 6 migrations
  (RLS gap closure, edge-secret triggers, replay-safe repairs); analyze green; verified surgical.
- ✅ C-2 `chore/edge-fn-configs` → merged to `develop` (PR #10, 2026-06-24). 9 edge-fn
  `config.toml` + 18-assertion pgTAP RLS suite. Surfaced 2 follow-ups (see BACKLOG): edge-fn
  `x-edge-secret` enforcement (security) + the never-green `ai-eval` CI (lockfile + missing GROQ secret).
- ✅ C-13 `chore/chat-eval` → merged to `develop` (PR #12, 2026-06-24). Also the live test of the
  ai-eval CI fix: **infra now fully green** (lockfile committed, workflow `npm ci`→`npm install`,
  GROQ secret added) — CI runs all 28 eval cases (25 pass / 3 fail = content, tracked separately).
- ✅ C-3 `fix/group-identity-persistence` → merged to `develop` (PR #13, 2026-06-24). Targeted bug-#3
  fix, NOT the stale-branch merge. `color_value`→`bigint` (ARGB overflow = the real root cause the
  spec missed) + `default_currency` column + atomic `create_group` + creator-gated `update_group_identity`
  RPC (COALESCE partial + `p_clear_avatar`); swallowed `catch(_){}` removed. Controller caught + bounced a
  partial-update clobber regression before merge. `feature/groups-overhaul` NOT purged — retains ~735 lines
  of unmerged group-customization UI; keep/discard is a user decision (BACKLOG §C-3 / §E).
- ✅ C-4 `chore/shared-wiring` data-layer → merged to `develop` (PR #15, 2026-06-25). SURGICAL ADDITIVE
  extraction: only the 15 new repo methods (budgets/recurring/alerts/insights) + `netlifyIngestUrl`, verbatim
  from `bc7e056`, zero existing lines touched. First attempt (PR #14, full `cherry-pick`) was CLOSED — it
  silently reverted develop's `delete_group`/`leave_group` RPCs, restoreExpense `original_amount`, and
  `settled_by` (stale-branch clean-merge). `chore/shared-wiring` KEPT: its providers/routes/screen wiring
  must be harvested per-feature (C-5/7/8/9) from `bc7e056` — see BACKLOG §E.
- ✅ C-5 `feat/wallet-csv-import` (bug #1) → merged to `develop` via PR #16 (2026-06-25, squash `77811b9`).
  **Part A** cherry-pick `898abd5`: new `csv_adapter.dart`, `ingest_row.dart`, `ingest_service.dart`,
  `import_ingest_screen.dart`, `netlify/functions/ingest.js` + 2 tests; `pdf-parse` dep added (all develop
  deps kept); `splitwise_import_screen.dart` adopted `CsvAdapter.parse` + `SplitwiseRow`. **Part B** harvested
  the INGEST SLICE of `bc7e056`: `ingestServiceProvider`/`IngestNotifier`/`ingestRowsProvider` +
  `walletImport`→`ImportIngestScreen` route (additive only, zero deletions in providers/router).
  `wallet_entry_type_screen.dart` kept develop's (Scan-a-Bill card); `setall_repository.dart` untouched
  (revert-guard `delete_group`/`leave_group`/`original_amount`/`settled_by` all match develop). analyze green,
  343/343 tests incl. `wallet_import_parity_test` + `csv_adapter_test`.
  ⚠️ **Controller caught + bounced ONE regression before merge**: the first pass resolved the wallet-import
  conflict by keeping develop's `addExpense(groupId:null)` path, which leaves `base_currency_amount` NULL —
  silently dropping the wallet-import-parity fix (the branch's own test documents `addExpense groupId=null`
  leaves it null vs `upsertWalletEntry` freezing it). Corrected to a TRUE UNION: develop's dedup +
  `upsertWalletEntry` (freezes `base_currency_amount`). Group-destination branch unchanged (`addExpense` +
  `SplitInsert`). Lesson reinforced: a "clean" conflict resolution can still drop a feature's whole purpose.
- ✅ C-6 `feat/soft-delete` → **SUPERSEDED, no merge** (2026-06-25). Soft-delete/restore is already on develop in a
  more evolved form: repo tombstone writes + restore reads of `deleted_expenses`, the table created in
  `local_database.dart` (LOCAL SQLite — soft-delete is deliberately offline-only, `sync_service.dart:739`),
  restore UI with a **365-day** window (branch was a stale 90-day), and `soft_delete_integrity_test.dart`. The
  branch (origin `ab998aa`, 58 behind) only added 5 **server-side** Supabase migrations for a synced
  `public.deleted_expenses` table the app never uses + stale screen i18n reverts + 2 key-gen python scripts.
  Cherry-picking would have reverted develop and orphaned a server table. Not dispatched. Open product question
  (server-persisted tombstones for cross-device/post-reinstall restore) deferred to BACKLOG §E.
- ✅ C-7 `feat/recurring` → merged to `develop` via PR #17 (2026-06-25, squash `f9fad76`). Clean cherry-pick of
  `ac38e9b` (4 NEW files: recurring_candidate / recurring_detection_service / recurring_screen + migration
  `20260607000002_recurring_rules.sql` with full RLS) — zero conflicts, no existing files touched. Harvested the
  recurring slice of `bc7e056`: `recurringCandidatesProvider` + `recurringRulesProvider` + `recurring`→`RecurringScreen`
  route (additive, zero deletions). **Money-rule fix (controller-required):** `RecurringCandidate.amount` `double`→`Decimal`;
  the service emits `Decimal.parse(<real expense closest to modal>.amount)` instead of the float `modalAmount`; screen
  displays via `formatAmountForCurrency` and persists `amount.toString()` (numeric column); the ±10% clustering and
  `confidence` stay `double` (heuristics, not stored money). `setall_repository.dart` untouched; revert-guard tokens match.
  analyze green, 343/343 tests. The visible settings entry-tile is deferred to C-10 (needs `settings_ext.recurring*` keys).
- ✅ C-8 `feat/budget` → merged to `develop` via PR #18 (2026-06-25, squash `04c6ad9`). Clean cherry-pick of `166c675`
  (NEW budgets_screen + migration `20260607000001_budgets.sql` with full RLS) + a `wallet_screen.dart` budget edit
  ("Budget →" link + per-category `BudgetProgress` bar) that applied with ZERO conflicts — develop's wallet_screen was
  byte-identical to the branch parent (`git diff develop 166c675^ = 0`). Harvested the budget provider section of
  `bc7e056`: `categorySpendProvider` (also consumed by C-9 alerts) + `budgetsProvider` + `BudgetProgress` + `budgetProgressProvider`
  + `budgets`→`BudgetsScreen` route (additive, zero deletions; no duplicate of the recurring/ingest providers already on develop).
  **No money fix needed** — already Decimal-correct (`Decimal.tryParse` input → `amount.toString()` persist; amount/spend Decimal;
  only `fraction` double). `setall_repository.dart` untouched; revert-guard matches. analyze green, 343/343 tests. Budgets is
  reachable via the wallet "Budget →" link (settings tile still deferred to C-10).
- ✅ C-9 `feat/alerts-insights` → merged to `develop` via PR #19 (2026-06-25, squash `ab00f52`). Cherry-pick of `c8a94e3`
  (NEW alert_service / alert_prefs_screen / alert_banner + 2 RLS migrations `20260608000001_proactive_alerts` [alert_prefs +
  alert_log, 2 ENABLE-RLS / 7 policies] and `20260608000002_insight_signal` [1 ENABLE-RLS / 4 policies]; MODIFIED adaptive_shell
  [wraps content in `AlertBannerOverlay` + a locale-sync microtask], add_expense_screen [fire-and-forget `_runAlertChecks` after a
  new personal expense], insights_provider [`insertInsightSignal` on dismiss/followup/shown]). ONE conflict (insights_provider):
  resolved correctly — kept develop's Dart-3 `'context': ?contextPayload` AND folded in the 3 `insertInsightSignal` calls (both
  verified present; old `if (contextPayload != null)` form gone). Harvested the alert slice of `bc7e056`: `alertServiceProvider` +
  `alertPrefsProvider` + `AlertQueueNotifier` + `alertQueueProvider` + `alertPrefs`→`AlertPrefsScreen` route (additive; no dup of
  the budget/recurring/ingest providers already on develop). **Money-rule fix (controller-required):** budget threshold was
  `double.tryParse(amount)` + `spend.toDouble()/limit` + `pct >= 1.0/0.8` → now `Decimal.tryParse(amount)` + `spend >= limit` /
  `spend >= limit * Decimal.parse('0.8')`; anomaly threshold was `Decimal.parse((mean.toDouble()*k).toStringAsFixed(6))` → now
  `mean * Decimal.tryParse(anomalyK.toString())` (exact Decimal×Decimal). Only `anomalyK` (sensitivity coefficient, not money) stays
  double. `setall_repository.dart` untouched; revert-guard matches. analyze green, 343/343 tests. Settings entry-tile deferred to C-10.
  **➡ This completes the `bc7e056` (chore/shared-wiring) harvest** — data layer (C-4) + all four wiring slices (ingest C-5, recurring
  C-7, budget C-8, alerts C-9) are now on develop. Only the settings entry-tiles remain to lift in C-10; then `bc7e056` is purged
  (tag `archive/shared-wiring` before deleting, to preserve the SHA this ledger cites).
- ✅ C-10 `chore/i18n-keys` → merged to `develop` via PR #20 (2026-06-25, squash `8da8d6b`). NOT a cherry-pick: branch
  `42967d0` was 65 commits stale — a merge would have dropped develop's 40 `receipt.*` keys (from the merged AI-receipt
  feature) and reverted an already-i18n'd screen. Instead an **additive key union**: 107 keys that landed feature screens
  already call (ingest 29 / expense_detail 19 / alerts 19 / budget 14 / activity_screen 9 / recurring 9 / settings_ext 6 /
  wallet_screen 2) were merged into all 6 locales (en/de/es/fr/ka/ru) via a throwaway add-if-missing script (deleted, not
  committed) — real translations where the branch had them, English fallback for the 31 EN-only keys. **Controller-verified
  invariants on the PR head** (independent flat-dict diff develop↔PR): every locale lost=0 develop keys, valChanged=0 develop
  values, new107=107 present, `receipt.*`=40 with 0 changed; the sole parity gap (`dashboard.personal_wallet_title` absent
  from non-en) PRE-EXISTED on develop and is not among the 107. **Part B:** the 3 deferred settings entry-tiles (Budgets→
  `AppRouter.budgets`, Recurring→`AppRouter.recurring`, Alert-prefs→`AppRouter.alertPrefs`, `settings_ext.*` labels) added to
  develop's settings_screen via the existing `_NavRow` pattern (0 deletions — additive; routes resolve from C-7/8/9). **Dropped
  from the stale branch:** `group_expense_detail_screen.dart` (develop already references `expense_detail.*` 15×; 223 lines
  diverged) and 8 `scripts/add_*_keys.py` (one-shot generators). analyze green, 343/343 tests.
  **➡ `chore/shared-wiring` (bc7e056) PURGED** post-merge (fully harvested across C-4/5/7/8/9/10); SHA preserved as tag
  `archive/shared-wiring`. **Phase-0 integration queue now: only C-11 (website) + C-12 (ai-provider-cache) remain.**
- ⚠️ C-11 `feature/website-2-0-integration` → **SUPERSEDED, no dispatch** (controller determination, 2026-06-25). Branch
  `d5ca365` is 5 ahead / 351 behind; develop already shipped Website 2.0 and evolved it far past the branch. Evidence: all 5
  "new" pages (login/portal/privacy/support/terms.html) already exist on develop → the full merge conflicts in ALL 9 files;
  develop's `login.html` wires login→portal (3 `portal` refs) while the branch's does NOT (0); develop's Makefile already
  builds from `web/app.html`; develop's pages are newer/bigger on 5 of 7; develop's web history adds full i18n (6 locales),
  portal group-spending cards, insights AI currency conversion, a password-reset page — all post-dating the branch; and
  `production_legitimacy_test` is tuned to develop's 9-page site. A merge/cherry-pick would silently revert develop's web work
  and break the login→portal flow — the C-6 trap. No PR. Branch keep/discard deferred to USER (BACKLOG §E; recommend discard).
  **Phase-0 integration queue now: only C-12 (ai-provider-cache) remains.**
- ✅ C-12 `fix/crit-01-ai-provider-cache` (CRIT-01) → merged to `develop` via PR #21 (2026-06-25, squash `d4ad8d0`). NOT a
  cherry-pick: branch `9d0536e` was 271 behind and carried 2 stray journals (`projectledger.md`, `wiki doc.md`). Surgical
  hand-application of the ~11-line fix onto develop's current `dashboard_screen.dart`: added `import 'dart:async'` + a
  `ref.keepAlive()` link, a 15-min `Timer(() => link.close())`, and `ref.onDispose(() => cacheTimer?.cancel())` at the top of
  `_aiInsightProvider` (kept it `autoDispose` — keepAlive+timer is the intended Riverpod pattern). Before this, the provider
  re-hit the Groq AI API on every Dashboard revisit; develop had ZERO keepAlive usage (CRIT-01 genuinely unfixed). Controller-
  verified: single-file additive diff (0 deletions), keepAlive block inside the provider before the analyticsData fetch,
  `dart:async` imported, stray journals NOT taken, MERGEABLE/CLEAN. analyze green, 343/343 tests.
  **➡ Phase-0 integration COMPLETE — see the §3 banner. Next: close-out (align main←develop + §E user decisions).**

## 4. Open bugs / requested work (active backlog)

### Phase-1 task queue (formalized 2026-06-25, priority order)

Each task branches off `develop` as `fix/*`/`feat/*`/`integrate/*`, PR'd back into `develop`. Hard rules:
money = integer-cents/`Decimal` (no float); RLS on every new table; never expose service_role / hardcode a
secret; surgical diffs (no whole-file reflow / broad `git add`); not done until `flutter analyze` = 0 AND
343/343 tests; a "clean" merge that silently drops a feature's purpose = reject (verify, don't trust).

| # | Pri | Task | Maps to | Status |
|---|---|---|---|---|
| 1 | P0 (LEAD) | `setall-edge-key-completion` | foundational (unblocks push/digest) | ✅ **DONE + LIVE-VERIFIED 2026-06-26** (PR #26 + #27; applied to prod; digest test = 200 `sent:1`, email delivered) |
| 2 | P1 | `setall-push-and-digest` | §4 item 5 | digest ✅ VERIFIED; push: client token-fix ✅ (PR #29) + `FIREBASE_SERVICE_ACCOUNT` set + fn redeployed → **pending real-device verify** (token must land in `fcm_tokens`) |
| 8 | P2 | group-info per-member debt amounts (NEW, user req 2026-06-26) | — | ✅ DONE (PR #30, `d029731`) — DeepSeek clean, controller-verified (Decimal preserved, correct from/to direction, current-user excluded) |
| 3 | P1 | `net-balance-offset` | carried TODO #1 | ✅ **DONE — netting confirmed correct (PR #40)** — added the missing Math-Guard suite (`balance_service_test` + `settlement_engine_test`, 26 hermetic tests; `make math-guard`), which caught + fixed a real pre-existing sub-cent spurious-`0.00` settlement-txn defect (round-first + skip/advance, guarantees termination) |
| 4 | P1 | `setall-web-insights-datasource` | §4 item 4 | ✅ **DONE — stale-confirmed (PR #42)** — web datasource wired Feb/Mar 2026; added 26-test analytics guard suite (no prod change). `double`-aggregation money-rule violation **NOW FIXED** (Part D, PR #44): `analyticsDataProvider` aggregates in `Decimal`, `.toDouble()` only at chart/JSON/burnRate boundary; +3 float-drift proofs |
| 5 | P1 | `setall-shared-expense-wallet-share` | §4 item 2 | ✅ **DONE — 5a–5c-iii all landed.** 5a (PR #32): `source_expense_id` link + dedupe; migration `20260626000001` **applied to prod** (uuid self-FK `ON DELETE SET NULL` + partial index); SQLite v37; `upsertWalletEntry` dedupes. 5b (PR #33): `myShareFromResults` (Decimal, reads `amountOwed` never re-divides) + ask/always/never pref + post-save confirm sheet → `upsertWalletEntry(…, sourceExpenseId)`. 5c-i (PR #34): edit/delete propagation — `deleteExpense`/`deleteExpenses`→`_removeMirrorForSource`, `updateExpense`→`_propagateEditToMirror` (recompute share, update or remove). Controller fixed 2 workhorse misses: `_findMirrorId` swallow-all (→narrowed to missing-column only) + edit reset mirror `created_at` to now (→preserve via `_existingCreatedAt`; `Eval-DeepSeek: failed` on `6adda7d`). 5c-ii (PR #36): `deleteGroup`/`forceDeleteGroup` cascade now removes linked mirrors via `_removeMirrorForSource` (owner · non-owner leave · force-purge, web+native) — **closes the orphan-mirror gap**; `sourceGroupName` helper + read-only `GroupBadge` "from <group>" chip (wallet list + detail). Controller fixed 2 more workhorse misses: **web FK-ordering** — mirror removed AFTER source delete, but the `source_expense_id ON DELETE SET NULL` FK nulled the link first → orphan survived → moved removal BEFORE the cascade on both web paths (native unaffected: SQLite has no such FK, which is why the integration tests passed); **`GroupBadge`** used `ProviderScope.containerOf` default `listen:true` in `initState` (throws "before initState() completed", swallowed by catch → always "from a group" in debug builds) → `listen:false`. Decimal-only, 369/369. **5c-iii DONE (PR #47):** mirror create already showed once as `ExpenseEvent` (stale-confirmed — no double-count); the real gap was a SILENT `_removeMirrorForSource` → now writes a `deleted_expenses` tombstone (native only; carries the SOURCE group id/name) so mirror removal surfaces as `ExpenseDeletedEvent`, + `_ExpenseTile` shows the "from <group>" `GroupBadge`. All 10 callers are user delete/edit (no sync-pull → no phantom events). 5 hermetic tests; 467/467 |
| 6 | P2 | `setall-statement-multi-import` (RECONCILE w/ landed wallet-csv-import) | §4 item 1 | 🔨 **6a DONE (6b deferred).** Importer (parse + review + commit + date-preserve) already landed via PR #16; 6a (PR #38) adds the missing dedupe: extracted `_dedupSig`→shared `importDedupSig` in `lib/core/utils/import_dedup.dart` (day+normDesc+amount-to-cents+currency; splitwise refactored to it, zero behaviour change); `IngestService.flagDuplicates` builds a sig-set from `getWalletEntries()`, pre-rejects + badges colliding rows; `IngestRow.isDuplicate` (advisory) + orange "Duplicate" chip; `ingest.duplicate` ×6 locales. Controller fix: `commitApproved` was `approved && !isDuplicate` → blocked re-approving a false-positive (genuine 2nd identical purchase same day); made commit status-driven (dups stay pre-rejected) + override regression test. Decimal/cents, 383/383. **6b deferred (infra):** receipt-scanner statement-detection + array response in `netlify/functions` — needs deploy gating. **2026-06-29: importer was ORPHANED** — `ImportIngestScreen` (route `/wallet/import`) had NO UI entry point (user kept getting 1 total via Scan-a-Bill→receipt-ingest). Wired an "Import statement" card into `wallet_entry_type_screen` (the wallet "+" flow) → CSV/PDF multi-row import now reachable. **6b (image/photo statement → rows) STILL OPEN:** `ingest.js` accepts only `csv`/`pdf`; a photographed/screenshotted statement needs an image-OCR branch (Google Vision/gpt-4.1 → `parseTransactionLines` → `classifyRows`) + an image source in the importer + Scan-a-Bill statement-detection routing. |
| 7 | P2 | carried TODOs (ghost-row FK · OAuth auto-close · invite search · ~~"settled up"~~) | carried TODOs #2–5 | ✅ **ALL DONE.** "settled up" PR #28. Sweep PR #44: ghost-FK = safe idempotent alignment migration (`20260627000001`; real path already hardened by `20260302000001`; **✅ APPLIED to prod `vrsmsgyxeyzyrdonsnrk` 2026-06-27** — verified ghost column has no FK + `add_ghost_member` granted); OAuth = `platformDefault` + `closeInAppWebView` (web-vs-mobile split corrected in PR #50, verify on device); invite-search = **stale-confirmed** (fixed by `20260227000001`) + error-logging. +24 guard tests |
| 8 | P1/P2 | **QA-2026-07-09 wave** (7 changes; tracker `openspec/changes/QA-2026-07-09-WAVE.md`) | user device QA 2026-07-09 | 🔨 **In progress.** Specs landed PR #54; orphaned wallet-import entry-point rescued PR #55. **#1 `setall-region-date-format` (PR #56):** iOS/Android ignored system Region → dates rendered US-style (MM/DD). Root cause: `com.setall.app/region` channel existed only on macOS; Dart gated to `TargetPlatform.macOS`. Fix: iOS/Android native handlers (`Locale.current.identifier` / `Locale.getDefault()`) + `_hasRegionChannel()` widening the gate to macOS/iOS/Android (try/catch + PlatformDispatcher fallback unchanged for web/Windows/Linux). Controller fix on review: wiring the channel makes country codes reachable on mobile, which surfaced a latent `patternFromLocale` bug — the generic "any 2-letter country → DMY" short-circuit ran before the YMD-language check, so `ja_JP`/`zh_CN`/`ko_KR`/`hu_HU` resolved to DMY not YMD; added a `ymdCountries` set before the fallback + 4 guard tests. DeepSeek had hit this via a `ja_JP` test and **deleted the test instead of flagging the bug** (`Eval-DeepSeek: failed`). 15 date-format tests, analyze 0, 482/482. **Time follow-up `fix/region-time-format` (PR #59) — ✅ merged + on-device verified.** Symptom: device 24h but app 12h. Two layers: (a) iOS/Android `Locale.current.identifier` carries no hour-cycle → native now detects it (`DateFormat.is24HourFormat` on Android; a `.short` `DateFormatter` instance + AM/PM-symbol test on iOS — the `j`-template class method and a "contains 13" probe both failed) and appends `@hours=h23`/`h12` to the identifier so the existing Dart `[@;]hours=` regex resolves it; extracted `timePatternFromLocale` (shared by the service + regional_screen) + 8 tests. (b) **The real blocker (found in the device log, not by guessing): `MissingPluginException` — the iOS channel wasn't registered at all.** DeepSeek registered it in `application(didFinishLaunchingWithOptions:)` behind `window?.rootViewController as? FlutterViewController`, but this app uses the new `FlutterImplicitEngineDelegate` embedding where that is nil at launch → the block silently no-op'd. Controller fix: register on the real engine via `engineBridge.pluginRegistry.registrar(forPlugin:).messenger()` inside `didInitializeImplicitFlutterEngine`. Not eval-tagged (native, device-toggle-dependent, non-hermetic). analyze 0, 494/494. **On-device (user 2026-07-10): date ✅ (`en_GE`, DD/MM) AND time ✅ (24h) confirmed — region-format bug fully closed.** **#2 `setall-expense-date-edit` (PR #58):** edit-expense date picker set `_entryDate` but `updateExpense` never received it + stripped `created_at` → date edits silently lost. Fix: optional `entryDate` on `updateExpense` → `created_at` (UTC ISO-8601) in web + native payloads when provided, byte-identical strip when null (PR #34 regression class held); `_propagateEditToMirror` gated on the same signal (controller decision: mirror follows source date when explicitly edited, else preserve `_existingCreatedAt`). Clean DeepSeek delivery — no logic misses. 4 hermetic tests, analyze 0, 486/486. On-device verify pending. |

**TASK 1 — `setall-edge-key-completion` (P0):** prod disabled legacy `anon`/`service_role` JWT keys (memory
`edge-fn-legacy-keys-disabled`) → DB-trigger/cron `net.http_post` 403 at gateway (no `apikey`) + the 5 fns built
`createClient(URL, SUPABASE_SERVICE_ROLE_KEY)` = dead key. PRs #23/#24 (`x-edge-secret` gates) were correct but sat
atop this unfinished migration.
- ✅ **CODE MERGED — PR #26** (`develop` squash `3c71e2e`, 2026-06-25), controller byte-verified:
  - Migration `20260625010000_complete_edge_key_migration.sql` — `CREATE OR REPLACE`s 4 objects (`trigger_bug_triage`,
    `notify_group_members`, send-monthly-digest cron, weekly-analysis cron); bodies VERBATIM from authoritative sources
    (#22 `20260625000000` for the 2 trigger fns, `20260601000001` for the 2 crons) + exactly one line per `net.http_post`:
    `'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key' LIMIT 1)`. Secret read from
    Vault at call time — never in the file. Idempotent DO-block guards on the cron unschedules. Both trigger bodies confirmed
    BYTE-IDENTICAL to #22 except the apikey line (python difflib); #22's `SET search_path = public` hardening still on develop
    → the stale-fork revert (PR #25) was avoided.
  - 5 fns (`bug-triage`, `monthly-digest`, `send-group-notification`, `sync-exchange-rates`, `weekly-analysis`) swapped
    `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')` → `JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}')['default']`.
    `SERVICE_ROLE` = 0 in all 5; `x-edge-secret` gates intact. analyze green, 343/343.
- ⚠️ **PR #25 REJECTED before #26** — stale-fork feature-dropper (forked from develop@`2a29232`, pre-#22); its migration would
  have silently reverted #22's `SET search_path` hardening (Git reported MERGEABLE — pure migration ordering, no textual conflict).
  Branch rebuilt onto current develop + re-dispatched.
- ✅ **FOLLOW-UP MERGED — PR #27** (`develop` squash `1751935`, 2026-06-26). The open scoping Q is **answered**: `send-email`
  (auth hook `hook_send_email`) and `send-welcome-email` (trigger `on_profile_created`) ARE invoked via DB pg-functions →
  both 403'd too. Plus a 3rd gap found live: the `sync-exchange-rates-daily` pg_cron (NOT an external scheduler as previously
  assumed) carried a literal un-substituted `Bearer <SERVICE_ROLE_KEY>` placeholder. New migration `20260625020000` adds the
  Vault apikey to all 3. (`send-email`/`send-welcome-email` fns are Resend-only — no dead-key dependency, so the gateway fix
  fully restores them.)
- ✅ **APPLIED TO PROD + VERIFIED (controller, via MCP + CLI, 2026-06-26).** Vault `secret_key` prereq was DONE (user steps 1–4).
  - Migrations `20260625010000` + `20260625020000` applied (`apply_migration`). Re-queried all **7 DB→edge call sites** →
    **all carry `apikey`** (4 fns: trigger_bug_triage / notify_group_members / on_profile_created / hook_send_email; 3 crons:
    send-monthly-digest / weekly-analysis / sync-exchange-rates-daily), `SET search_path` intact, placeholder gone.
  - Deployed the 5 fns via CLI with `--no-verify-jwt`. **Caught + fixed a drift:** `bug-triage`/`monthly-digest`/
    `send-group-notification` were live at `verify_jwt=true` (a prior deploy flipped them) → would 401 cron/trigger calls
    before our gate; all 5 now `verify_jwt=false` (per-fn `config.toml` is NOT read by the CLI — only central `supabase/config.toml`
    or the `--no-verify-jwt` flag).
  - **Digest live-test** (`net.http_post` to `monthly-digest?test=akostnz@gmail.com`, secret read from Vault in-DB):
    **403 GONE** — request now reaches the function. (Returned the function's own response, not a gateway reject.)
- ✅ **LIVE-VERIFIED 2026-06-26 — digest test = 200 `{"sent":1,"test":true,"email":"akostnz@gmail.com"}`, email delivered.**
  The path from 401→200 had two parts: (1) `EDGE_SHARED_SECRET` (fn env) had to equal Vault `edge_shared_secret` — the user set it
  via Dashboard (the `supabase secrets list` digest is CACHED/stale, so it kept showing the old `64f6…`; a throwaway `edge-secret-debug`
  fn proved `match:true`, both sha `803e3f1c…`, then deleted); (2) **STALE ISOLATES** — the 5 fns were deployed BEFORE the secret was
  fixed, and **Supabase injects fn secrets at isolate boot** so warm isolates kept the old value. **Redeploying the 5 fns after the
  secret was correct** cycled the isolates → gate passes. (Lesson in memory `edge-fn-legacy-keys-disabled`: redeploy fns after any
  change to a secret they read.) The other 4 fns share the identical gate/key pattern and were redeployed together. **TASK 1 closed.**
- ⚠️ **Separate prod-divergence flag (NOT TASK 1):** live `supabase_migrations` is missing `20260624000000` (C-3 group-identity,
  PR #13) — group icon/colour fixes aren't on prod. Tracked under Phase-1; verify-and-apply separately.

### Backlog detail

New specs written 2026-06-24 (flat layout `openspec/<name>/`):
1. **statement-multi-import** _(TASK 6)_ — statement ingested as one chunk, no split, no dedupe.
   _Largely already solved by `feat/wallet-csv-import` — reconcile, don't rebuild._
2. **shared-expense-wallet-share** _(TASK 5)_ — mirror my share of a shared expense into my wallet
   (opt-in, human-confirmed, activity-logged, `source_expense_id` link).
3. **group-identity-persistence** — ✅ fixed in C-3 (PR #13); icon/colour now stick. _Was: `create_group` RPC
   only got `p_name`; identity set via a swallowed `catch(_){}` UPDATE that sync clobbered + ARGB overflow._
4. ✅ **DONE (TASK 4, PR #42)** **web-insights-datasource** — **stale-confirmed.** Web's Supabase datasource was wired Feb/Mar 2026 (`getRecentExpenses` `0c601e6`, `getPersonalExpenses` `e871c16f`), both feeding `analyticsDataProvider`→insights via the source-agnostic `ExpenseModel.fromJson` mapper — no SQLite-only branch. Added the missing guard suite (26 hermetic tests: `test/features/analytics/analytics_data_test.dart` ×20 ProviderContainer + `analytics_row_test.dart` ×6) proving amounts flow end-to-end (anti-vacuous, income/expense split, currency normalization, dedup, 30-day window, empty). No production change. The flagged `double`-aggregation money-rule violation was **fixed in the P2 sweep** (Part D, PR #44): `analyticsDataProvider` now aggregates in `Decimal`, `.toDouble()` only at the chart/JSON/burnRate boundary, +3 float-drift proofs.
5. **push-and-digest** _(TASK 2)_ — push + monthly digest never delivered end-to-end. _Blocked on TASK 1 live-verify._

Carried-over TODOs (from old `progress.md`):
- ✅ **DONE (TASK 3, PR #40)** Net balance A↔B offset — **confirmed not a live bug** (netting was already correct: `balance_service.dart` nets `rawOwed − rawOwe` globally + per-group; `SettlementEngine` nets per-member). Added the missing **Math-Guard suite** (`test/core/services/balance_service_test.dart` + `settlement_engine_test.dart`, 26 hermetic tests incl. anti-vacuous; `make math-guard`). The suite **caught a real pre-existing sub-cent defect**: `SettlementEngine` emitted a spurious `0.00` settlement txn when a member's net rounded sub-cent (the `payment > 0` gate used the *unrounded* amount) → fixed (round-first + skip/advance the smaller balance, which also guarantees termination). Normal 2-decimal inputs unchanged. 409/409.
- ✅ **DONE (TASK 7, PR #44)** Ghost-row nickname FK violation on `pending_invites` — safe idempotent alignment migration `20260627000001` (drops any FK on the ghost column; re-asserts canonical `add_ghost_member`). Real nickname-conflict path was already hardened by `20260302000001`. **✅ APPLIED to prod (`vrsmsgyxeyzyrdonsnrk`) 2026-06-27** — verified live: `pending_invites` FKs = `group_id` + `invited_by` only (no FK on the ghost column); `add_ghost_member(uuid,text,uuid)` is `SECURITY DEFINER` + `EXECUTE` granted to `authenticated`.
- ✅ **DONE (TASK 7, PR #44; web regression fixed PR #50)** Google OAuth in-app browser doesn't auto-close — mobile: `LaunchMode.platformDefault` (dismissible SFSafariViewController/Custom Tabs) + `closeInAppWebView()` on callback. **PR #50 fix:** PR #44 had wrongly applied `platformDefault` to the WEB branch too → popup blocked, redirect never returned ("won't go past landing page"). Web now uses a plain full-page redirect (`signInWithOAuth`, no `authScreenLaunchMode`); mobile keeps `platformDefault`. **Verify on device + web.**
- ✅ **DONE (on-device QA-fix batch, PR #50, squash `cf14471`)** — fixes for 6 bugs found in the 2026-06-27 debug QA:
  - **Part A — "could not add members" (P0, self-diagnosing, NOT confirmed-fixed):** `addMemberById` now (1) throws "You must be signed in…" if no auth session, (2) surfaces the RAW RPC error instead of a swallowed generic, (3) if the RPC says "must be a member", checks whether the group exists server-side → throws "This group hasn't synced…" when it doesn't. **Root cause still unconfirmed** (needs the live error from a re-test). `add_member_by_id` IS deployed + granted on prod (verified via MCP 2026-06-27), so it's runtime: no live Supabase session, or the group never synced. Controller fixed a DeepSeek dead-catch (the diagnostic throw was inside its own `try/catch(_)` → never fired).
  - **Part B — web login (P0):** see OAuth bullet above.
  - **Part C1 — wallet mirror showed `$0.00` (P1):** tombstone amount read `universal_usd_amount` (always `"0.00"`) first; flipped to `amount ?? universal_usd_amount` (the share lives in `amount`). Regression in PR #47 (test gap; now asserted).
  - **Part C3 — deleted group expense, wallet mirror stayed (P1, web-only fix):** added missing `_notify()` to the WEB `deleteExpense`. **Caveat:** native (iOS) `deleteExpense` already calls `_notify()`, so this likely does NOT fix the iOS symptom — re-test on device, check the Wallet tab (the Activity-history create event legitimately persists).
  - **Part D — "no analytics in the app" (P2):** added an "Open Full Analytics" button on the dashboard insights card → `AppRouter.analytics` (the full analytics screen existed but had no entry point); +`analytics.open_full_analytics` ×7 locales.
  - analyze 0, 467/467.
- ✅ **DONE — stale-confirmed (TASK 7, PR #44)** Group invite search (email/nickname) — already fixed by migration `20260227000001` (`GRANT EXECUTE` + ILIKE email/nickname/name). Added `searchUsers` error-logging (was a silent `catch`) + regression guards.
- ~~"Settled up" stale after account switch~~ ✅ **DONE (TASK 7, PR #28, `de17765`)** — `_invalidateAllProviders()` in `lib/app.dart`
  now invalidates the `groupBalanceSummaryProvider` family + wallet/master/omni/simplifiedDebts; comprehensive re-invalidation
  after post-switch sync. analyze 0, 343/343.

## 5. Spec index (`openspec/`) — 13 total

**Flat layout (on main + new):** setall-ai-receipt-ingest, setall-key-migration,
setall-security-ai-chat-openspec.md, setall-group-identity-persistence,
setall-push-and-digest, setall-shared-expense-wallet-share, setall-statement-multi-import,
setall-web-insights-datasource, setall-secret-rls-audit (notes).
**`openspec/changes/` layout (harvested from branches):** setall-budgets,
setall-ingestion-pipeline, setall-wallet-import-parity, setall-recurring-detection,
setall-proactive-alerts, setall-insight-self-improvement.
> TODO: standardize on the OpenSpec `openspec/changes/<name>/specs/.../spec.md` layout.

## 6. Branch & workflow policy (Phase 0)

Target: **two long-lived branches only** — `main` (releases, tagged, deployable) and
`develop` (integration trunk). All work via short-lived `feat/*` / `fix/*` off `develop`,
PR into `develop`, delete on merge. Release = `develop → main`, tag, deploy.
`Development-june` becomes the working tip of the new `develop`.
**Phase-0 status:** see `BACKLOG.md` for the per-branch keep/integrate/purge decisions.

## 7. Roadmap (post-integration)

Nomad tax-aware logic, Tap-to-Settle (NFC), autonomous "debt collector" reminders,
SetAll-for-Teams (B2B clearing + Stripe Connect), global wealth dashboard. (Aspirational —
see `.context/ledger-sources/` for the original brainstorm.)

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
  read Supabase directly (see open bug #4).

## 2. Release state

- **Shipped: v1.7.0 (`1.7.0+34`)**, merged to `main` (61d86a5), tagged `v1.7.0`.
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
| 1 | P0 (LEAD) | `setall-edge-key-completion` | foundational (unblocks push/digest) | **CODE DONE PR #26** — LIVE-VERIFY PENDING (user-gated) |
| 2 | P1 | `setall-push-and-digest` | §4 item 5 | BLOCKED on TASK 1 live-verify |
| 3 | P1 | `net-balance-offset` (write short spec first) | carried TODO #1 | not started |
| 4 | P1 | `setall-web-insights-datasource` | §4 item 4 | not started |
| 5 | P1 | `setall-shared-expense-wallet-share` | §4 item 2 | not started |
| 6 | P2 | `setall-statement-multi-import` (RECONCILE w/ landed wallet-csv-import) | §4 item 1 | not started |
| 7 | P2 | carried TODOs (ghost-row FK · OAuth auto-close · invite search · "settled up") | carried TODOs #2–5 | not started |

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
- ☐ **LIVE-VERIFY (user-gated — `flutter analyze` can't prove this).** Vault `secret_key` prereq DONE (user steps 1–4). Remaining
  ops (user runs with controller guidance): (a) apply `20260625010000` via **Dashboard SQL editor** (NOT `supabase db push` —
  documented repo↔live migration-history divergence); (b) `supabase functions deploy bug-triage monthly-digest
  send-group-notification sync-exchange-rates weekly-analysis --project-ref vrsmsgyxeyzyrdonsnrk`; (c) update the external
  sync-exchange-rates 24h scheduler to send the new `apikey`; (d) verify Unified Logs show **200 not 403** +
  `monthly-digest?test=akostnz@gmail.com` arrives + welcome/reset emails still work. **Open scoping Q:** are
  `send-email`/`send-welcome-email` invoked via Dashboard Auth Hooks or via DB triggers `send_email_hook`/`on_profile_created`?
  If DB triggers, they 403 too and need a 2-line apikey follow-up migration (step (d) doubles as the probe).
  **TASK 2 does not start until (d) passes.**

### Backlog detail

New specs written 2026-06-24 (flat layout `openspec/<name>/`):
1. **statement-multi-import** _(TASK 6)_ — statement ingested as one chunk, no split, no dedupe.
   _Largely already solved by `feat/wallet-csv-import` — reconcile, don't rebuild._
2. **shared-expense-wallet-share** _(TASK 5)_ — mirror my share of a shared expense into my wallet
   (opt-in, human-confirmed, activity-logged, `source_expense_id` link).
3. **group-identity-persistence** — ✅ fixed in C-3 (PR #13); icon/colour now stick. _Was: `create_group` RPC
   only got `p_name`; identity set via a swallowed `catch(_){}` UPDATE that sync clobbered + ARGB overflow._
4. **web-insights-datasource** _(TASK 4)_ — web has no SQLite; insights hub reads empty amounts.
5. **push-and-digest** _(TASK 2)_ — push + monthly digest never delivered end-to-end. _Blocked on TASK 1 live-verify._

Carried-over TODOs (from old `progress.md`):
- Net balance not offset between two users (A↔B each show 50 instead of net 0) — **correctness bug, high priority** _(TASK 3)_.
- Ghost-row nickname FK violation on `pending_invites` _(TASK 7)_.
- Google OAuth in-app browser doesn't auto-close _(TASK 7)_.
- Group invite search (email/nickname) returns nothing _(TASK 7)_.
- "Settled up" stale after account switch _(TASK 7; root-caused — `_invalidateAllProviders()` in `lib/app.dart` misses
  `groupBalanceSummaryProvider` family + wallet/master/omni/simplifiedDebts providers)._

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

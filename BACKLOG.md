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
2. `chore/edge-fn-configs` — edge fn config.toml + RLS regression tests
3. `feature/groups-overhaul` — fuller group customization + `group_identity_columns` migration (bug #3)
4. `chore/shared-wiring` — repo/router/providers glue the features depend on
5. `feat/wallet-csv-import` — bank-statement importer (bug #1) + tests
6. `feat/soft-delete` — 90-day restore / deleted_expenses
7. `feat/recurring` — recurring detection
8. `feat/budget` — monthly budgets
9. `feat/alerts-insights` — proactive alerts + insight signals
10. `chore/i18n-keys` — translations covering all the above (do near-last)
11. `feature/website-2-0-integration` — portal/login/legal (independent; can parallel)
12. `fix/crit-01-ai-provider-cache` — AI 15-min cache (drop the stray journals it carries)
13. `chore/chat-eval` — promptfoo chat eval cases

**Gate:** each integration is its own PR into `develop`, must pass `flutter analyze` (exit 0)
before merge (see memory `flutter-analyze-gate-worktree`). Expect conflicts between
groups-overhaul / shared-wiring / i18n-keys — integrate in the order above.

### D. Reset / rename
- ~~`develop` (374 behind, 0 ahead) → hard-reset to `origin/main`~~ **DONE / superseded**:
  `develop` is already the integration trunk = `origin/main` + planning commit, and equals
  `Development-june`. **Do NOT hard-reset develop** — it is live and ahead of main. (Verified 2026-06-24.)
- After C completes and `develop` is verified, merge `develop → main` and re-tag.

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

---

## Definition of done (every task)
1. Branch off `develop`. 2. `flutter analyze` exit 0. 3. Tests where applicable.
4. PR into `develop` with spec reference. 5. Update `PROJECT_LEDGER.md` + this file.
6. Use `Decimal`/integer-cents for money. 7. RLS on all new tables; never expose service_role.

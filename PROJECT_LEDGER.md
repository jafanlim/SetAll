# SetAll — Project Ledger (single source of truth)

_Last updated: 2026-06-24. This file supersedes and consolidates the scattered journals:_
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

**Phase-0 integration progress:**
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

## 4. Open bugs / requested work (active backlog)

New specs written 2026-06-24 (flat layout `openspec/<name>/`):
1. **statement-multi-import** — statement ingested as one chunk, no split, no dedupe.
   _Largely already solved by `feat/wallet-csv-import` — reconcile, don't rebuild._
2. **shared-expense-wallet-share** — mirror my share of a shared expense into my wallet
   (opt-in, human-confirmed, activity-logged, `source_expense_id` link).
3. **group-identity-persistence** — icon/colour don't stick. Root cause: `create_group` RPC
   only gets `p_name`; identity set via a swallowed `catch(_){}` UPDATE that sync then clobbers.
   _Check `feature/groups-overhaul`'s `group_identity_columns` migration — may be the missing DB side._
4. **web-insights-datasource** — web has no SQLite; insights hub reads empty amounts.
5. **push-and-digest** — push + monthly digest never delivered end-to-end.

Carried-over TODOs (from old `progress.md`):
- Net balance not offset between two users (A↔B each show 50 instead of net 0) — **correctness bug, high priority**.
- Ghost-row nickname FK violation on `pending_invites`.
- Google OAuth in-app browser doesn't auto-close.
- Group invite search (email/nickname) returns nothing.
- "Settled up" stale after account switch.

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

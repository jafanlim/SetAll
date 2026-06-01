# setall-key-migration — proposal

**Status:** ✅ IMPLEMENTED (2026-06-01) — this spec is now an **as-built record + cleanup backlog**, not a to-do.
**Owner:** Aleksei · **Executed by:** Cascade session (`Supabase_Key_Migration_Completion.md`)
**Relates to:** `setall-secret-rls-audit` (this superseded its key-rotation step), `setall-ai-endpoint-hardening` (this delivered the `ai-analyst` + endpoint in-code auth)

## Why (original)

Two live secrets were committed to the public repo, and the env strategy mixed client + server secrets:
- 🔴 `service_role` JWT in `supabase/migrations/20260326000003_set_service_role_key.sql` — bypasses all RLS.
- 🟠 `anon` JWT hardcoded as a `defaultValue` in `lib/core/config/auth_config.dart`.
- 🟠 `.env` fed both the Flutter build and server secrets.

Resolution: migrate to Supabase **publishable + secret** keys, add **in-code auth** to all 10 Edge Functions (required once legacy keys are disabled, since platform JWT auto-verification only works for the legacy pair), and **disable** the legacy keys (which is what neutralizes the committed JWTs).

## What shipped (verified in the execution log)

| # | Change | Status |
|---|---|---|
| 1 | `auth_config.dart` default → `sb_publishable_…` key | ✅ |
| 2 | `ai-analyst` (Supabase) → full `auth.getUser(token)` | ✅ |
| 3 | 9 internal functions → `x-edge-secret` guard | ✅ (2 exceptions, see design D4) |
| 4 | 10× `config.toml` with `verify_jwt = false` | ✅ |
| 5 | New migration `20260601000001_switch_triggers_to_edge_secret.sql` — triggers/crons send `x-edge-secret` from Vault instead of `Bearer <service_role>` | ✅ pushed |
| 6 | Committed `service_role` migration body neutralized | ✅ |
| 7 | `EDGE_SHARED_SECRET` + secret key set; Vault `edge_shared_secret` created | ✅ (after a leak+rotation, see OPEN-1) |
| 8 | All 10 functions deployed `--no-verify-jwt` | ✅ |
| 9 | Netlify env: `SUPABASE_URL` + publishable key set | ✅ |
| 10 | Legacy `anon`/`service_role` **disabled** in dashboard | ✅ |
| 11 | Git history scrubbed — 528 commits, 0 JWTs remaining across all branches | ✅ force-pushed |
| 12 | App verified booting + authenticating on device (debug log) | ✅ |
| — | Asymmetric JWT signing keys (Step 3) | ⏭️ N/A — feature absent on this project's plan; skipped |

## What is NOT done (the real backlog this spec now tracks)

These are consequences of *how* the run executed, and they're the reason this spec stays open until checked off in `tasks.md`:

- **OPEN-1 — Secret hygiene after the in-chat leak.** The first `EDGE_SHARED_SECRET` was printed in the Cascade chat (transmitted to the model provider) and was briefly set in Supabase before rotation. Confirm only the rotated value exists in `.env`, Supabase secrets, and Vault — and that the leaked value is dead everywhere.
- **OPEN-2 — CI is entangled and was failing.** The history rewrite + `--force --tags` re-pointed 33 tags and re-triggered `release.yml`; the workflow already had real bugs (Windows missing `--no-tree-shake-icons`, no Android job originally, Firebase secret-name mismatch). Needs one clean green run.
- **OPEN-3 — Undocumented auth exceptions.** `send-email` and `send-welcome-email` intentionally do **not** use `x-edge-secret` (they're Supabase Auth-Hook protected via their own webhook secret). Correct, but must be recorded so a future audit doesn't "fix" them.
- **OPEN-4 — Confusing key naming.** `SUPABASE_PUBLISHABLE_KEY` was rejected as a `supabase secrets set` name (reserved `SUPABASE_` prefix → auto-injected). The publishable value now lives under `SUPABASE_ANON_KEY` and the secret under `SUPABASE_SERVICE_ROLE_KEY` — names that now describe the *old* key type. Decide: document the aliasing, or rename the non-reserved consumers.
- **OPEN-5 — Installed clients on old builds break by design.** Any app build compiled before this carries the dead anon JWT and now fails login ("Legacy API keys are disabled"). Ship fresh builds to every channel (web ✅ done; iOS/Android/macOS/Windows pending the CI/Xcode items).
- **OPEN-6 — `.env` server/client split not actually done.** The original plan split `.env` into client vs server files; the run instead kept one `.env` and fixed the multi-line Firebase JSON. The mixing risk (server secret reachable by a client build) remains until split.
- **OPEN-7 — Gemini key still referenced.** `ai-analyst` Supabase fn still reads `GEMINI_API_KEY` (test showed a `toFixed` path, not the key). Confirm whether the mobile analyst is on Gemini or Groq; don't rotate/keep a dead key.

Each OPEN item maps to a task in `tasks.md`. Everything in "What shipped" maps to a ✅ task there for traceability.

# setall-key-migration — design (as-built)

Documents the architecture that **actually shipped**, with the decisions that diverged from the original plan and why.

## Goals / status

| Goal | Done when | Status |
|---|---|---|
| No legacy JWT usable | Legacy `anon`/`service_role` disabled; committed copies dead | ✅ |
| Client uses publishable key | `auth_config.dart` default = `sb_publishable_…`; app authenticates | ✅ |
| Every function authenticates itself | user-fn verifies JWT; internal fns check shared secret | ✅ (D4 exceptions) |
| Committed secrets removed from history | 0 JWTs across all branches | ✅ |
| Server secrets unreachable from client builds | server/client env split | ❌ OPEN-6 |

## D1 — Two key classes, mapped onto existing env names
Publishable (`sb_publishable_…`) replaces `anon`; secret (`sb_secret_…`) replaces `service_role`. **Constraint discovered at runtime:** Supabase reserves the `SUPABASE_` prefix and auto-injects `SUPABASE_URL` / `SUPABASE_ANON_KEY` / `SUPABASE_SERVICE_ROLE_KEY` into every deployed function — so you **cannot** `supabase secrets set SUPABASE_PUBLISHABLE_KEY=…`. Decision taken: store the publishable value under the existing `SUPABASE_ANON_KEY` slot (auto-injected, client-safe) and the secret under `SUPABASE_SERVICE_ROLE_KEY`. **Debt (OPEN-4):** the names now describe the old key *type*, not the value. Either document this aliasing prominently or rename the non-reserved references.

## D2 — `ai-analyst` verifies the caller's JWT
The function moved from a hand-rolled JWT `sub` decode to `supabase.auth.getUser(token)` against the auto-injected key. Deployed `--no-verify-jwt` (platform no longer verifies for the new keys), so the in-code check is the gate. Returns 401 on missing/invalid token. Confirmed live: a bogus token returns `{"error":"Invalid authorization token."}`; a real session token reaches the handler.

## D3 — Internal functions: shared-secret header from Vault
Triggers/cron call functions via `net.http_post`. Original calls sent `Authorization: Bearer <service_role>`. New migration `20260601000001` switches them to an `x-edge-secret` header whose value is read from **Vault** (`select decrypted_secret from vault.decrypted_secrets where name='edge_shared_secret'`). Each internal function checks `req.headers.get('x-edge-secret') === Deno.env.get('EDGE_SHARED_SECRET')`, else 403. This reuses the pattern already present in `send-welcome-email` (`WELCOME_HOOK_SECRET`).

**Operational gotcha observed:** `supabase secrets set` triggers a function cold-restart; if `.env` and the deployed secret are out of sync, calls flip between `forbidden` (edge secret mismatch) and provider errors. Resolution that worked: set `RESEND_API_KEY` **and** `EDGE_SHARED_SECRET` together from `.env` in one `secrets set`, then re-test. **Lesson for the runbook:** always re-push the full secret set together and wait for restart before testing.

## D4 — Two intentional exceptions (MUST stay documented — OPEN-3)
- **`send-email`** — a Supabase **Auth Hook**, invoked by Supabase's auth system, not a DB trigger. Protected by the hook mechanism; **no** `x-edge-secret`.
- **`send-welcome-email`** — already validates its own `x-webhook-secret` (the correct Auth-Hook pattern); **no** additional `x-edge-secret`.
A future security audit must not "close the gap" on these two — doing so would break the auth flow.

## D5 — Disable-legacy is the neutralizer; history scrub is hygiene
The committed `service_role`/`anon` JWTs became dead the moment legacy keys were disabled (D-step 10). The `git filter-repo` pass (replace JWT regex → `REDACTED_JWT`, 528 commits, force-push all branches/tags) removes them from history but is **not** what protects the project — disabling does. Order shipped: rotate-aware setup → test on new keys → disable legacy → scrub. Correct.

## D6 — Build-time key injection (why old installs break — OPEN-5)
The Flutter client reads `String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: <publishable>)`. CI passes no `--dart-define` override, so release builds compile in the publishable default. Any build produced **before** this change carries the old anon JWT and now fails against the project with legacy disabled. Mitigation = reship all channels. Web done; desktop/mobile gated on OPEN-2 (CI) and the local Xcode iOS-26 platform install (unrelated to keys).

## Risks / residual

| Risk | State |
|---|---|
| Leaked first `EDGE_SHARED_SECRET` still live somewhere | OPEN-1 — verify rotated-only |
| Forced history rewrite breaks collaborators' clones | Accepted; solo repo. Anyone with a clone must re-clone |
| CI flakiness now coupled to security work | OPEN-2 — get one green run, then treat CI separately |
| Server secret compiled into a client build | OPEN-6 — env not yet split |
| Dead `GEMINI_API_KEY` rotated/retained needlessly | OPEN-7 — confirm provider |

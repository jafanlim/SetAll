# setall-edge-key-completion — proposal

**Status:** OPEN — not started (Phase 1 fix)
**Relates to:** `setall-key-migration` (this completes it), `setall-secret-rls-audit`,
`setall-push-and-digest` (digest is one of the broken consumers), `docs/setall-supabase-key-migration.md`

## Why

The 2026-06-01 key migration disabled the legacy `anon`/`service_role` JWT keys and switched
triggers to `x-edge-secret`, but it was written for the **old** key model. On a **new-key**
Supabase project two things it never accounted for are now broken, and because every affected
consumer is a *background* feature (push, digests, FX sync, bug-triage) the failures are silent
— nobody saw them until we wrote the digest/triage spec.

### Breakage 1 — triggers can't reach functions (gateway 403)
`net.http_post` in `20260601000001_switch_triggers_to_edge_secret.sql` (and the welcome /
send-email / group-notification / bug-triage / cron migrations) sends **only** `x-edge-secret`
— **no `apikey` header** (verified: 0 occurrences of `apikey` in any migration on `main`).
New-key projects require a valid key on the **`apikey`** header for the gateway to route the
request at all; `--no-verify-jwt` disables JWT *verification*, not the gateway's apikey gate.
Secret keys are rejected on `Authorization: Bearer`. → trigger fires, gateway returns 403,
function never runs.

### Breakage 2 — functions' admin client is dead
All **5** trigger/cron functions build their service client from the legacy key:
`createClient(URL, Deno.env.get('SUPABASE_SERVICE_ROLE_KEY'))` —
- `bug-triage/index.ts:20,52`
- `monthly-digest/index.ts:14,55`
- `send-group-notification/index.ts:27,91`
- `sync-exchange-rates/index.ts:28,78`
- `weekly-analysis/index.ts:21,35` (its `getUser` uses the same client)

`SUPABASE_SERVICE_ROLE_KEY` now holds the **disabled legacy** JWT → every admin query fails.

### Out-of-repo
- The `sync-exchange-rates` 24 h scheduler (configured outside the repo) must also send the new `apikey`.

## What ships (the fix — per Supabase migration guide)

1. **SQL:** to every trigger/cron `net.http_post`, add
   `'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='secret_key')`
   in the headers, **keeping** `x-edge-secret`. Requires a **new Vault secret** `secret_key`
   holding the `sb_secret_…` value — **never hardcoded**. New replay-safe migration; do not edit
   the historical ones in place beyond a superseding migration.
2. **TS (all 5 functions):** swap
   `Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')` →
   `JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS'))['default']`
   (`SUPABASE_SECRET_KEYS` is auto-injected on new-key projects). `weekly-analysis`'s `getUser`
   uses the same new client.
3. **Out-of-repo:** update the FX scheduler to send the new `apikey`.

## Keep (do NOT "fix" these — they are correct for new keys)
- `verify_jwt = false` on all functions + the `x-edge-secret` gates (PRs #23/#24). Supabase
  prescribes exactly this for new keys; not JWT-based, not affected.
- The Auth-Hook exceptions `send-email` / `send-welcome-email` (their own webhook secret).

## Not affected
- The **Flutter app** (uses the publishable key + the user's session JWT) and the core app data
  flow. This is **background features only**: push, digests, FX, triage email.
- **Netlify** functions (`receipt-ingest`, `voice-entry`, `ai-analyst`) — verified: none read a
  service_role key; they use the publishable key + user JWT.

## Optional deeper cut
- Adopt `@supabase/server`'s `withSupabase({ auth })` instead of hand-rolled secret checks.

## Why this wasn't tracked (the post-mortem the user asked for)
- The original migration was **executed against the live project from a Cascade (Windsurf)
  session**, reconstructed into `docs/setall-supabase-key-migration.md` + the
  `setall-key-migration` openspec. The actual migration `20260601000001` only reached `main`
  **just now** via Phase-0 C-1 (`security-rls-audit`) — for weeks the repo and the live project
  disagreed.
- The migration's model was "Bearer service_role → x-edge-secret" (auth **into** functions). It
  correctly fixed *incoming* auth and even doubled down on it (the #23/#24 x-edge-secret gates),
  which created **false confidence**. It never modelled the two new-key platform realities —
  the gateway's `apikey` requirement and the functions' *outgoing* admin-client key.
- `PROJECT_LEDGER.md` didn't exist until 2026-06-24; the then-live journal (`progress.md`) was a
  Feb-27 session log. The key migration lived in its own doc silo, disconnected from any running
  ledger, so the gap was never even a known unknown.
- **Background = silent.** No interactive user ever exercises push/digest/FX/triage, so a 403 or
  a dead admin client produces no visible error. "No one remembers" because no one ever saw it
  fail.

## Verification gate
Cannot be confirmed by `flutter analyze` (server-side). Must verify on the live project:
trigger an event (new bug report / group expense) and the `?test=` digest path, and confirm the
function runs (logs show 200, not 403) and its admin queries succeed.

# SetAll — Key Rotation + Migration to Publishable/Secret Keys
### Step-by-step, reconciled with the Cascade audit. Accurate as of 2026-06-01.

---

## Read this first: "isn't disabling JWT keys contradictory?"

No — two different actions get conflated:

1. **Disabling the legacy `anon` / `service_role` API keys** — the migration goal. Those keys *are* JWTs the Supabase platform auto-verifies on Edge Functions, so disabling them is what forces you to deploy functions with `--no-verify-jwt` and do auth **in code**. That's a required step *inside* the migration, not a reason to skip it — and it's the same in-code auth you already wanted for `ai-analyst`.
2. **Revoking the legacy JWT *signing secret*** — optional, deeper, last. Migrating to asymmetric signing keys does **not** by itself break functions.

**You don't "rotate" the committed `anon`/`service_role` JWTs the old way.** Regenerating them = rotating the JWT secret = session downtime, and it's often unavailable on current projects. The correct neutralization for those two is: migrate to publishable/secret keys, then **disable** the legacy pair (Step 8). The committed JWTs become dead the moment they're disabled. (Cascade suggested "Regenerate Service Role Key" — that's the legacy path; we're doing the better one.)

Third-party secrets (Resend, Groq, Firebase, etc.) are independent — rotate those at their own dashboards (Step 2).

---

## What the audit confirmed

| Finding | Detail | Action |
|---|---|---|
| `.env` gone from disk, never in git | Confirmed missing locally; no commit ever added it. Likely deleted in your disk cleanup. | Recreate it locally (Step 1). Not a leak. |
| 🔴 `service_role` JWT committed | Full key in `supabase/migrations/20260326000003_set_service_role_key.sql` (public repo) | Neutralize via disable-legacy (Step 8) + move secret to Vault (Step 6) + scrub history (Step 9) |
| 🟠 `anon` JWT committed | Full key hardcoded as `defaultValue` in `lib/core/config/auth_config.dart` (~L35) | Replace default with the **publishable** key (safe to commit) (Step 5) |
| 🟢 3rd-party secrets NOT committed | `RESEND_API_KEY`, `GROQ_API_KEY`, `GEMINI_API_KEY`, `FIREBASE_SERVICE_ACCOUNT`, `WELCOME_HOOK_SECRET` live only as Supabase/Netlify secrets | Rotate at source as precaution (Step 2) |
| 🟢 Publishable identifiers | `SUPABASE_URL`, Firebase API keys (`firebase_options.dart`), Google OAuth client IDs (`auth_config.dart`) | None — these are public by design |
| In-code auth pattern already exists | `send-welcome-email` checks `WELCOME_HOOK_SECRET` itself | Reuse this pattern for all trigger/cron functions (Step 6) |

---

## Your 10 Edge Functions — how each must authenticate after migration

Because disabling legacy keys removes platform JWT verification, each function deployed with `--no-verify-jwt` must check auth itself.

| Function | Invoked by | Auth to add in code |
|---|---|---|
| `ai-analyst` | **User** (mobile app, sends session JWT) | Verify the caller's JWT: `auth.getUser(token)` |
| `bug-triage` | DB trigger (`net.http_post`) | Shared-secret header |
| `monthly-digest` | `cron.schedule` | Shared-secret header |
| `weekly-analysis` | `cron.schedule` | Shared-secret header |
| `sync-exchange-rates` | cron | Shared-secret header |
| `send-email` | **Supabase Auth Hook** | ⚠️ **No x-edge-secret** — see exception below |
| `send-group-notification` | DB trigger | Shared-secret header |
| `notify-group-invite` | DB trigger | Shared-secret header |
| `send-welcome-email` | **Auth trigger** | ⚠️ **No x-edge-secret** — uses `WELCOME_HOOK_SECRET` in `x-webhook-secret`; see exception below |
| `send-test-email` | Manual/dev | Shared-secret header, or delete if unused |

**Pattern:** one user-auth function (`ai-analyst`), nine internal callers that just need a shared secret in a header. All the internal callers go through `net.http_post` in your trigger/cron migrations — today they send `Authorization: Bearer <service_role>`; you'll switch them to a custom header (a secret key can't be a Bearer token anyway).

### ⚠️ Exception: `send-email` and `send-welcome-email` — do NOT add x-edge-secret

These two functions are **Supabase Auth Hooks**, called directly by the Supabase Auth subsystem, not by your DB triggers or cron jobs. The Auth system does not send `x-edge-secret` headers:

- **`send-email`** is wired as the "Send Email" Auth Hook (Dashboard → Authentication → Hooks). Supabase Auth calls it with `{ user, email_data }` and no custom secret header. Adding an `x-edge-secret` check would cause every auth email (confirm, recovery, magic-link, email-change) to return 403 and silently break authentication.
- **`send-welcome-email`** is called by the `on_profile_created` DB trigger, which sends its own secret in the `x-webhook-secret` header (`WELCOME_HOOK_SECRET`). This is a different header name and value from `x-edge-secret`; do not replace or supplement it.

The security model for both is: (1) the function URL is not exposed to end users, (2) `--no-verify-jwt` is set, (3) each has its own appropriate guard (`send-email` relies on network-layer protection; `send-welcome-email` checks `WELCOME_HOOK_SECRET`).

---

## Step-by-step (do not reorder)

### Step 1 — Recreate `.env` locally
It's gitignored, so it's local-only. Recreate from the template and leave values blank for now; you'll fill them with the new keys as you generate them.
```bash
cp .env.example .env
# .env stays gitignored — never commit it
```

### Step 2 — Rotate the third-party secrets (independent of Supabase keys; do anytime)
For each, generate a new key at its dashboard, then update Supabase + Netlify:
```bash
supabase secrets set RESEND_API_KEY="new"          # resend.com
supabase secrets set GROQ_API_KEY="new"            # console.groq.com   (also update Netlify env)
supabase secrets set GEMINI_API_KEY="new"          # if still used (mobile ai-analyst); else remove
supabase secrets set FIREBASE_SERVICE_ACCOUNT='{"type":...}'   # Firebase console → new service-account key
supabase secrets set WELCOME_HOOK_SECRET="new-random"          # also update the webhook config that sends it
```
Netlify: update `GROQ_API_KEY` (and `GEMINI_API_KEY` if present) in the Netlify env UI. `RESEND/FIREBASE/WELCOME_HOOK` aren't in the client or git — good.

### Step 3 — Migrate to asymmetric JWT signing keys
Dashboard → **Authentication → Signing Keys**. Migrate from the shared secret to an asymmetric signing key. Underpins the new key model and lets you later revoke the legacy secret cleanly. (No function breakage from this step.)

### Step 4 — Create the new API keys
Dashboard → **Settings → API Keys** → create. Generates the default `sb_publishable_…` and one `sb_secret_…`. Confirm you got `sb_`-prefixed keys (not a new legacy pair). You can add/revoke more secret keys later.

### Step 5 — Swap the CLIENT to the publishable key
1. Build/CI: pass the publishable value:
   `flutter run --dart-define=SUPABASE_ANON_KEY=sb_publishable_xxx …` (keep the var name, or rename to `SUPABASE_PUBLISHABLE_KEY` and update `auth_config.dart`).
2. `lib/core/config/auth_config.dart` (~L35): replace the committed `anon` JWT `defaultValue` with the **publishable** key. Safe to commit — publishable keys are made to be public.
3. `Supabase.initialize(anonKey: AuthConfig.supabaseAnonKey)` (`main.dart`) needs no structural change — the SDK accepts the publishable value in that slot.
4. Put the publishable key in your local `.env` too.

### Step 6 — Swap the SERVER side + add in-code auth
**6.1 — Function secrets.** Verify `supabase secrets list`. Privileged functions use the **secret** key; low-privilege uses **publishable**.

**6.2 — `ai-analyst` (user-auth).** Deploy with `--no-verify-jwt` and verify the caller's JWT in code:
```ts
// supabase functions deploy ai-analyst --no-verify-jwt
const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
const supa = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_PUBLISHABLE_KEY")!);
const { data: { user }, error } = await supa.auth.getUser(token);
if (error || !user) return new Response(JSON.stringify({ error: "unauthorized" }), { status: 401 });
// scope all data to user.id
```

**6.3 — The 9 internal functions (shared-secret).** You already do this in `send-welcome-email` with `WELCOME_HOOK_SECRET`. Generalize: store one internal secret in Vault, send it as a custom header from every trigger/cron `net.http_post`, and check it in each function.
```sql
-- store once (after rotation), not in a committed migration:
select vault.create_secret('long-random-string', 'edge_shared_secret');
```
In each trigger/cron migration, change the `net.http_post` headers from
`Authorization: Bearer <service_role>` to:
```sql
headers := jsonb_build_object(
  'Content-Type','application/json',
  'x-edge-secret', (select decrypted_secret from vault.decrypted_secrets where name='edge_shared_secret')
)
```
In each function:
```ts
if (req.headers.get("x-edge-secret") !== Deno.env.get("EDGE_SHARED_SECRET"))
  return new Response("forbidden", { status: 403 });
```
(`supabase secrets set EDGE_SHARED_SECRET="long-random-string"` so the function can read it.)

**6.4 — Move the committed `service_role` out of the migration.** Replace the body of `20260326000003_set_service_role_key.sql` with a comment; the trigger no longer needs `app.settings.service_role_key` once it uses `x-edge-secret` from Vault.

**6.5 — Deploy all functions with JWT verification off.** Either per deploy:
```bash
supabase functions deploy ai-analyst bug-triage monthly-digest weekly-analysis \
  sync-exchange-rates send-email send-group-notification notify-group-invite \
  send-welcome-email send-test-email --no-verify-jwt
```
…or durably in `supabase/config.toml` (no flag needed on future deploys):
```toml
[functions.ai-analyst]
verify_jwt = false
# repeat per function
```

**6.6 — Netlify `ai-analyst.js`.** Add `SUPABASE_URL` + `SUPABASE_PUBLISHABLE_KEY` to Netlify env so the web function can `auth.getUser(token)` (the hardening work). `GROQ_API_KEY` unaffected.

### Step 7 — TEST on the new keys (before disabling anything)
- Mobile build with publishable key: login, read/write a wallet entry, AI chat → 200s.
- Web portal AI call works.
- Trigger a bug report → `bug-triage` fires + email arrives.
- Invoke each cron fn manually: `supabase functions invoke monthly-digest` (and weekly-analysis, sync-exchange-rates).
- Send-welcome / group-notification / invite paths fire on their triggers.
- RLS still holds: user A can't read user B (publishable relies on it).

### Step 8 — Disable the legacy `anon` / `service_role` keys
Dashboard → **Settings → API Keys → Legacy tab → disable**. **This neutralizes the two committed JWTs.** Reversible — re-enable instantly if a consumer was missed.

### Step 9 — Scrub git history
After the keys are disabled (so they're already dead), purge the old values from history with `git filter-repo` / BFG: the `service_role` JWT in `20260326000003_…sql` and the `anon` JWT in `auth_config.dart`. Force-push; coordinate if anyone else has clones.

### Step 10 — (Optional) revoke the legacy JWT signing secret
Only **after** Step 8 (the legacy keys are themselves JWTs signed by it). Authentication → Signing Keys → revoke legacy. Skip if you're not ready — disabling the legacy keys is the main win.

---

## Rollback
Mid-migration breakage → **re-enable the legacy keys** (Step 8 is a toggle); old paths work instantly. Fix the gap, re-test, disable again.

## CLI gotcha
With legacy keys disabled, `supabase gen types typescript` and some CLI calls error "Legacy API keys are disabled." Use the new keys with those tools, or re-enable legacy briefly while running them.

---

## Final checklist
- [ ] `.env` recreated locally (gitignored)
- [ ] 3rd-party secrets rotated at source + `supabase secrets set` + Netlify (Step 2)
- [ ] Asymmetric JWT signing key migrated (Step 3)
- [ ] `sb_publishable_…` + `sb_secret_…` created (Step 4)
- [ ] Client default in `auth_config.dart` + build/CI + `.env` use **publishable** key (Step 5)
- [ ] `ai-analyst` verifies caller JWT in code (Step 6.2)
- [ ] 9 internal fns use `x-edge-secret` from Vault; triggers/cron send that header not Bearer (Step 6.3)
- [ ] `service_role` removed from the migration; trigger uses Vault secret (Step 6.4)
- [ ] All 10 fns deployed `--no-verify-jwt` (or `config.toml verify_jwt=false`) (Step 6.5)
- [ ] Netlify AI fn has `SUPABASE_URL` + publishable key (Step 6.6)
- [ ] Full test pass on new keys (Step 7)
- [ ] Legacy `anon`/`service_role` **disabled** (Step 8)
- [ ] Committed JWTs scrubbed from history (Step 9)
- [ ] (Optional) legacy JWT signing secret revoked (Step 10)

---

*Sources: Supabase API Keys guide, Understanding API Keys, JWT Signing Keys, API-keys changelog/discussions (supabase.com/docs, supabase.com/changelog), reviewed 2026-06-01. Verify exact dashboard labels against your project; Supabase iterates on the UI.*

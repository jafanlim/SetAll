# setall-edge-key-completion — tasks

## Prereq (run once, NOT as a committed migration — no secret in git)
- [ ] Create Vault secret holding the secret key:
      `SELECT vault.create_secret('sb_secret_…', 'secret_key');`
- [ ] Confirm `SUPABASE_SECRET_KEYS` is present in the functions' env (auto-injected on new-key
      projects); if not, set it.

## SQL — new replay-safe migration
- [ ] New migration that `CREATE OR REPLACE`s every trigger/cron function to add
      `'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name='secret_key')`
      to the `net.http_post` headers, keeping `x-edge-secret`. Covers: trigger_bug_triage,
      notify_group_members, welcome-email trigger, send-email hook (if it posts), monthly-digest
      cron, weekly-analysis cron.
- [ ] Idempotent / re-runnable; do not edit historical migrations beyond superseding.

## TS — swap admin client key in all 5 functions
- [ ] `bug-triage/index.ts` (L20, L52)
- [ ] `monthly-digest/index.ts` (L14, L55)
- [ ] `send-group-notification/index.ts` (L27, L91)
- [ ] `sync-exchange-rates/index.ts` (L28, L78)
- [ ] `weekly-analysis/index.ts` (L21, L35 — incl. getUser)
- [ ] Helper: `const secret = JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS') ?? '{}')['default']`
      with a clear error if absent. Update the header comments that still say SERVICE_ROLE_KEY.

## Out-of-repo
- [ ] Update the external `sync-exchange-rates` 24 h scheduler to send the new `apikey`.

## Verify (live — server-side)
- [ ] Deploy functions `--no-verify-jwt`; apply migration.
- [ ] Trigger a bug report + a group expense → confirm function logs show 200 (not 403) and
      admin queries succeed.
- [ ] `monthly-digest?test=akostnz@gmail.com` → email arrives.
- [ ] Confirm `send-email`/`send-welcome-email` auth-hook path still works.
- [ ] Tick the WHEN/THEN items in spec.md; close OPEN items in `setall-key-migration`.

## Optional
- [ ] Adopt `@supabase/server` `withSupabase({ auth })` to replace hand-rolled checks.

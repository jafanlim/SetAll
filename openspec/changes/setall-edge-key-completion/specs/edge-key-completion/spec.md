# setall-edge-key-completion — spec (WHEN/THEN)

Legend: ☐ to verify on the live project (server-side; `flutter analyze` cannot prove these)

## Gateway routing (Breakage 1)
- ☐ **WHEN** a DB trigger / cron `net.http_post` calls an edge function, **THEN** it sends both
  an `apikey` header (the `sb_secret_…` value from Vault secret `secret_key`) **and** the
  `x-edge-secret` header, and the gateway routes the request (no 403).
- ☐ **WHEN** the `apikey` header is missing or holds a disabled legacy key, **THEN** the gateway
  returns 403 and the function never runs (this is the current broken state — the regression test).

## Function admin client (Breakage 2)
- ☐ **WHEN** any of the 5 trigger/cron functions (bug-triage, monthly-digest,
  send-group-notification, sync-exchange-rates, weekly-analysis) builds its admin client,
  **THEN** it uses `JSON.parse(Deno.env.get('SUPABASE_SECRET_KEYS'))['default']`, NOT
  `SUPABASE_SERVICE_ROLE_KEY`, and its admin queries succeed.
- ☐ **WHEN** `weekly-analysis` calls `getUser`, **THEN** it uses the same new secret-key client.

## Out-of-repo scheduler
- ☐ **WHEN** the external 24 h `sync-exchange-rates` scheduler fires, **THEN** it sends the new
  `apikey` and the function runs.

## Must remain true (do not regress)
- ☐ **WHEN** any function is deployed, **THEN** `verify_jwt = false` and the `x-edge-secret` gate
  are unchanged (correct for new keys; PRs #23/#24).
- ☐ **WHEN** `send-email` / `send-welcome-email` are invoked by the Auth Hook, **THEN** they
  still authenticate via their own webhook secret (NOT `apikey`/`x-edge-secret`).
- ☐ **WHEN** the Flutter app or a Netlify function runs, **THEN** it is unaffected (publishable
  key + user JWT path unchanged).

## Secret hygiene
- ☐ **WHEN** Vault is inspected, **THEN** a `secret_key` secret holds the `sb_secret_…` value and
  it appears in no migration body, commit, or log.

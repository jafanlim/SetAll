# setall-key-migration — spec (WHEN/THEN)

Legend: ✅ verified in execution log · ☐ to verify in `tasks.md`

## Authentication
- ✅ **WHEN** a client uses the publishable key for normal auth/data, **THEN** RLS-scoped access works and the app authenticates (device boot confirmed).
- ✅ **WHEN** `ai-analyst` is called with an invalid/missing JWT, **THEN** it returns an auth error and does not run (`{"error":"Invalid authorization token."}` observed).
- ☐ **WHEN** `ai-analyst` is called with a valid session JWT, **THEN** it returns an AI response (observed reaching handler; a populated-context success response still to be confirmed — the empty-context `toFixed` was a test artifact).
- ✅ **WHEN** an internal function is called with the correct `x-edge-secret`, **THEN** it proceeds (test email sent).
- ✅ **WHEN** an internal function is called without/with a wrong `x-edge-secret`, **THEN** it returns 403 (`forbidden` observed before the secret was synced).

## Legacy key disablement
- ✅ **WHEN** the legacy `anon`/`service_role` JWT is presented after disablement, **THEN** the API rejects it ("Legacy API keys are disabled" / "Secret API key required" observed).
- ✅ **WHEN** the public repo history is searched for the committed JWTs, **THEN** none are found (0 across all branches).

## Auth-hook exceptions (must remain true)
- ✅ **WHEN** `send-email` or `send-welcome-email` is invoked by the Supabase Auth Hook, **THEN** it is accepted via the hook/webhook-secret mechanism (NOT `x-edge-secret`).

## Secret hygiene (OPEN-1)
- ☐ **WHEN** `.env`, Supabase secrets, and Vault are compared for `EDGE_SHARED_SECRET`, **THEN** all three hold the **rotated** value and the leaked first value is present nowhere.

## Client freshness (OPEN-5)
- ☐ **WHEN** a freshly built client (each channel) is launched, **THEN** login succeeds with the publishable key. (Web ✅; iOS/Android/macOS/Windows ☐.)

## CI (OPEN-2)
- ☐ **WHEN** a release tag is pushed, **THEN** `release.yml` completes green across desktop + Android jobs with no dangling-tag or `--no-tree-shake-icons` failures.

## Env separation (OPEN-6)
- ☐ **WHEN** the Flutter build consumes env, **THEN** it can read only publishable/client values; no secret (`sb_secret_…`, `RESEND_API_KEY`, `FIREBASE_SERVICE_ACCOUNT`, `EDGE_SHARED_SECRET`) is reachable by the client build.

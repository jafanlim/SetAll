# Proposal: Make Push Notifications & Monthly Digest Actually Work

Status: OPEN — not started
Owner: TBD
Related code: `lib/core/services/notification_service.dart`,
`supabase/functions/monthly-digest/index.ts` (pg_cron `0 9 1 * *`),
`supabase/functions/send-group-notification/`, `supabase/functions/notify-group-invite/`,
`fcm_tokens` Supabase table

## Why

Push notifications and the monthly digest email have **never actually worked**. Both are wired in
code but don't deliver. Needs end-to-end verification, not more wiring.

## Current Behaviour / Findings

- **Push:** `notification_service.dart` requests permission, fetches the FCM token, waits for the
  APNS token on iOS, and syncs tokens to the `fcm_tokens` table. The *client* side exists. What's
  unverified end-to-end:
  - Is there a **sending** function that reads `fcm_tokens` and calls FCM/APNS on real events
    (new expense, settle, invite)? `send-group-notification` exists — confirm it actually sends
    push (vs only email) and is invoked on the right triggers.
  - APNS: on iOS the token is null on simulator → service `return`s early. Needs a **real
    device** + the APNs auth key uploaded to Firebase. Likely never configured.
  - Firebase project / `firebase_options.dart` present and matching the app bundle id.
- **Monthly digest:** `monthly-digest/index.ts` is a complete Resend-based emailer with a
  `?test=email@addr` path. It depends on **pg_cron being scheduled** (`0 9 1 * *`) and secrets
  `RESEND_API_KEY` / `SUPABASE_SERVICE_ROLE_KEY` being set. If cron was never installed or
  secrets missing, it never fires. The `?test=` path is the fastest way to prove the function
  body works in isolation.

## Proposed Approach

1. **Digest first (cheap to verify).** Hit the function with `?test=akostnz@gmail.com`; confirm a
   correctly-localized email arrives. If yes → function is fine, problem is the cron/secrets.
   - Verify pg_cron job exists and is enabled; verify Resend key + service role key are set.
2. **Push, end-to-end, on a real device.**
   - Confirm APNs auth key (.p8) uploaded to Firebase, and FCM config matches bundle id.
   - Confirm a token actually lands in `fcm_tokens` after login on device.
   - Confirm a server trigger (new expense / invite / settle) invokes a function that **sends
     push** to those tokens; add the send path if it's email-only today.
   - Test foreground + background + cold-start tap → deep link.
3. **Observability.** Add minimal logging on the send path (tokens targeted, FCM response) so
   "did it send" is answerable without guessing.
4. **Preferences.** Respect a per-user notification preference (don't spam); store in profile.

## Scope

**In:** verify+fix digest cron/secrets, verify+fix push delivery end-to-end on device, ensure a
server send path exists for key events, logging, basic prefs.
**Out:** rich notification categories / per-event granular toggles (later); web push (separate).

## Open Questions

- Does any deployed function currently call FCM/APNS, or is everything email-only today?
- Is pg_cron available/enabled on this Supabase plan, or do we need an external scheduler?
- APNs key + Firebase config: present and correct? (Needs the device + console access to confirm.)

## Tasks

- [ ] Digest: invoke `monthly-digest?test=...`; confirm email arrives
- [ ] Digest: verify pg_cron job + RESEND_API_KEY + service role key in Supabase
- [ ] Push: confirm APNs .p8 in Firebase + FCM config matches bundle id
- [ ] Push: confirm token lands in `fcm_tokens` on real-device login
- [ ] Push: confirm/add a server send path (FCM) on new-expense/invite/settle
- [ ] Push: test foreground/background/cold-start + deep-link tap
- [ ] Add send-path logging; add user notification preference

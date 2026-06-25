-- KEY MIGRATION COMPLETION (part 2): the 3 DB→edge net.http_post call sites that
-- 20260625010000 did NOT cover. Same root cause: prod disabled the legacy
-- anon/service_role JWT keys, so every DB-originated call to an edge function
-- now needs a valid `apikey` header or the gateway returns 403 before the
-- function runs.
--
-- Covers:
--   1. on_profile_created()  → send-welcome-email   (was: Content-Type + x-webhook-secret, NO apikey)
--   2. hook_send_email(event)→ send-email           (was: Content-Type only, NO apikey)
--   3. cron sync-exchange-rates-daily → sync-exchange-rates
--        (was: 'Authorization: Bearer <SERVICE_ROLE_KEY>' — an un-substituted
--         placeholder + a now-dead key; replaced with apikey, x-edge-secret not
--         needed as that function has no in-body gate)
--
-- Each function body is reproduced VERBATIM from its current live definition;
-- the ONLY change is the added apikey header line. The secret is read FROM
-- Vault AT CALL TIME — the value is NEVER in this file.

-- ── 1. Welcome-email trigger function ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.on_profile_created()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
DECLARE
  _secret TEXT;
  _email  TEXT;
  _lang   TEXT;
  _url    TEXT := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/send-welcome-email';
BEGIN
  SELECT email INTO _email FROM auth.users WHERE id = NEW.id;
  IF _email IS NULL THEN RETURN NEW; END IF;

  _lang   := coalesce(NEW.language_code, 'en');
  _secret := coalesce(current_setting('app.welcome_hook_secret', true), '');

  PERFORM net.http_post(
    url     := _url,
    headers := jsonb_build_object(
      'Content-Type',     'application/json',
      'apikey',           (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key' LIMIT 1),
      'x-webhook-secret', _secret
    ),
    body    := jsonb_build_object(
      'email',         _email,
      'userId',        NEW.id::text,
      'language_code', _lang
    )::text
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '[on_profile_created] pg_net call failed: %', SQLERRM;
  RETURN NEW;
END;
$fn$;

-- ── 2. Auth "Send Email" hook function ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.hook_send_email(event jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $fn$
DECLARE
  edge_function_url text;
BEGIN
  edge_function_url := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/send-email';

  BEGIN
    PERFORM net.http_post(
      url     := edge_function_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey',       (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key' LIMIT 1)
      ),
      body    := event::text
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'hook_send_email: pg_net call failed: %', SQLERRM;
  END;

  RETURN jsonb_build_object('success', true);
END;
$fn$;

-- ── 3. Exchange-rates cron ────────────────────────────────────────────────────
-- Replaces the placeholder 'Authorization: Bearer <SERVICE_ROLE_KEY>' header
-- with the Vault apikey. sync-exchange-rates has no x-edge-secret gate, so the
-- apikey alone is sufficient to clear the gateway. Unschedules idempotently.
DO $do$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'sync-exchange-rates-daily') THEN
    PERFORM cron.unschedule('sync-exchange-rates-daily');
  END IF;
END $do$;

SELECT cron.schedule(
  'sync-exchange-rates-daily',
  '0 6 * * *',
  $job$
  SELECT net.http_post(
    url     := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/sync-exchange-rates',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key' LIMIT 1)
    ),
    body    := '{}'::jsonb
  );
  $job$
);

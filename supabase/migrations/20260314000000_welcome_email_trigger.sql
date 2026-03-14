-- Migration: welcome email trigger
-- Fires the `send-welcome-email` edge function via pg_net when a user
-- confirms their email for the first time (email_confirmed_at NULL → non-null).
--
-- Prerequisites (run once via Supabase Dashboard or CLI secrets):
--   1. Enable pg_net extension:
--        Dashboard → Database → Extensions → pg_net → Enable
--   2. Set the shared webhook secret in Supabase project secrets:
--        supabase secrets set WELCOME_HOOK_SECRET=<your-random-secret>
--   3. Store the same secret as a DB config so the trigger can read it:
--        SELECT set_config('app.welcome_hook_secret', '<your-random-secret>', false);
--      Or persist it in postgresql.conf via:
--        ALTER DATABASE postgres SET app.welcome_hook_secret = '<your-random-secret>';

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Enable pg_net (idempotent)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pg_net;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Trigger function
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION auth.handle_email_confirmed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = auth, net, public
AS $$
DECLARE
  _secret TEXT;
  _url    TEXT := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/send-welcome-email';
BEGIN
  -- Only fire when email_confirmed_at transitions NULL → non-null.
  IF OLD.email_confirmed_at IS NOT NULL OR NEW.email_confirmed_at IS NULL THEN
    RETURN NEW;
  END IF;

  -- Read the shared webhook secret from database config (set by admin).
  -- Falls back to empty string if not configured; function will still run
  -- but skip delivery when RESEND_API_KEY is also absent.
  _secret := current_setting('app.welcome_hook_secret', true);

  PERFORM net.http_post(
    url     := _url,
    headers := jsonb_build_object(
      'Content-Type',     'application/json',
      'x-webhook-secret', coalesce(_secret, '')
    ),
    body    := jsonb_build_object(
      'email',  NEW.email,
      'userId', NEW.id::text
    )::text
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never block the auth flow if the email call fails.
  RAISE WARNING '[handle_email_confirmed] pg_net call failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Attach trigger to auth.users
-- ─────────────────────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS on_email_confirmed ON auth.users;

CREATE TRIGGER on_email_confirmed
  AFTER UPDATE OF email_confirmed_at ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION auth.handle_email_confirmed();

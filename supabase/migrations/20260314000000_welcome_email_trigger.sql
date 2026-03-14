-- Migration: welcome email trigger
-- Fires the `send-welcome-email` edge function via pg_net when a user's
-- profile row is first inserted into public.profiles (created on email
-- confirmation / first sign-in). Avoids auth schema permission errors.
--
-- Prerequisites:
--   1. Enable pg_net: Dashboard → Database → Extensions → pg_net → Enable
--   2. Set secret: supabase secrets set WELCOME_HOOK_SECRET=<random>
--   3. Persist in DB: ALTER DATABASE postgres SET app.welcome_hook_secret='<same>';

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. Enable pg_net (idempotent)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pg_net;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. Trigger function on public.profiles INSERT
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.on_profile_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _secret TEXT;
  _email  TEXT;
  _url    TEXT := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/send-welcome-email';
BEGIN
  -- Look up email from auth.users (readable via security definer context).
  SELECT email INTO _email FROM auth.users WHERE id = NEW.id;
  IF _email IS NULL THEN RETURN NEW; END IF;

  _secret := coalesce(current_setting('app.welcome_hook_secret', true), '');

  PERFORM net.http_post(
    url     := _url,
    headers := jsonb_build_object(
      'Content-Type',     'application/json',
      'x-webhook-secret', _secret
    ),
    body    := jsonb_build_object(
      'email',  _email,
      'userId', NEW.id::text
    )::text
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING '[on_profile_created] pg_net call failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. Attach trigger to public.profiles (no special permissions needed)
-- ─────────────────────────────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS on_profile_created ON public.profiles;

CREATE TRIGGER on_profile_created
  AFTER INSERT ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.on_profile_created();

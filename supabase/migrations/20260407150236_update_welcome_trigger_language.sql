-- Migration: update welcome email trigger to pass language_code
-- Updates on_profile_created() to include language_code in the webhook body
-- so send-welcome-email can localize the email content.

CREATE OR REPLACE FUNCTION public.on_profile_created()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
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
$$;

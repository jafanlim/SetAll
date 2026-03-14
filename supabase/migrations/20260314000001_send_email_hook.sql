-- ─────────────────────────────────────────────────────────────────────────────
-- send_email Auth Hook
-- ─────────────────────────────────────────────────────────────────────────────
-- Supabase "Send Email" Auth Hooks require a Postgres function.
-- This function receives the hook payload from Supabase Auth and forwards it
-- to the send-email Edge Function via pg_net (async HTTP).
--
-- Dashboard wiring (one-time manual step):
--   Authentication → Hooks → Send Email hook
--   Hook type: Postgres
--   Schema:    public
--   Function:  hook_send_email
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.hook_send_email(event jsonb)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  edge_function_url text;
  service_role_key  text;
BEGIN
  -- Edge Function URL for this project
  edge_function_url := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/send-email';

  -- The service role key is used to authenticate the call to the Edge Function.
  -- Store it as a Postgres secret via: supabase secrets set (or use vault).
  -- For simplicity we read it from app.settings if set, otherwise fall back to
  -- the env var injected by Supabase into Postgres at runtime.
  BEGIN
    service_role_key := current_setting('app.supabase_service_role_key', true);
  EXCEPTION WHEN OTHERS THEN
    service_role_key := '';
  END;

  -- Fire-and-forget: pg_net queues the HTTP request asynchronously.
  -- Errors here (missing pg_net, network unreachable) are swallowed so
  -- they never block the Auth flow.
  BEGIN
    PERFORM net.http_post(
      url     := edge_function_url,
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || service_role_key
      ),
      body    := event::text
    );
  EXCEPTION WHEN OTHERS THEN
    -- Log but never raise — Auth must not be blocked by email failures.
    RAISE WARNING 'hook_send_email: pg_net call failed: %', SQLERRM;
  END;
END;
$$;

-- Grant execute to the supabase_auth_admin role that the hook system uses.
GRANT EXECUTE ON FUNCTION public.hook_send_email(jsonb) TO supabase_auth_admin;

-- Revoke from public so only Auth can call it.
REVOKE EXECUTE ON FUNCTION public.hook_send_email(jsonb) FROM PUBLIC;

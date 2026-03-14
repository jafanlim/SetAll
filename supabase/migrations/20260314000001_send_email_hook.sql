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
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  edge_function_url text;
BEGIN
  -- Edge Function is deployed with --no-verify-jwt so no Authorization header
  -- is required. pg_net fires an async HTTP POST and never blocks Auth.
  edge_function_url := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/send-email';

  BEGIN
    PERFORM net.http_post(
      url     := edge_function_url,
      headers := jsonb_build_object('Content-Type', 'application/json'),
      body    := event::text
    );
  EXCEPTION WHEN OTHERS THEN
    -- Never raise — Auth must not be blocked by email delivery failures.
    RAISE WARNING 'hook_send_email: pg_net call failed: %', SQLERRM;
  END;

  -- Supabase Send Email hooks must return a jsonb object.
  RETURN jsonb_build_object('success', true);
END;
$$;

-- Grant execute to the supabase_auth_admin role that the hook system uses.
GRANT EXECUTE ON FUNCTION public.hook_send_email(jsonb) TO supabase_auth_admin;

-- Revoke from public so only Auth can call it.
REVOKE EXECUTE ON FUNCTION public.hook_send_email(jsonb) FROM PUBLIC;

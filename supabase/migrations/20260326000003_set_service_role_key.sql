-- FEAT-P46: Set app.settings.service_role_key so the bug-triage trigger
-- can pass a valid Authorization header to the edge function.
--
-- Replay-safe guard: ALTER DATABASE requires privileges the local/CI migration
-- role lacks (SQLSTATE 42501). Prod already applied this, so it is never
-- re-run there; the guard only affects fresh replays, where it harmlessly skips.
DO $$
BEGIN
  EXECUTE 'ALTER DATABASE ' || quote_ident(current_database()) ||
          ' SET "app.settings.service_role_key" = ' || quote_literal('REDACTED_JWT');
EXCEPTION
  WHEN insufficient_privilege THEN
    RAISE NOTICE 'skipping app.settings.service_role_key (insufficient privilege on this database; set via dashboard on prod)';
END $$;

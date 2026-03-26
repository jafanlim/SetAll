-- FEAT-P46: Set app.settings.service_role_key so the bug-triage trigger
-- can pass a valid Authorization header to the edge function.
ALTER DATABASE postgres
  SET "app.settings.service_role_key" =
    'REDACTED_JWT';

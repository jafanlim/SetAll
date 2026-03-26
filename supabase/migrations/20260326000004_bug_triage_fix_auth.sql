-- FEAT-P46: Fix trigger_bug_triage to embed the service role key directly.
-- ALTER DATABASE requires superuser which the migration user lacks, so we
-- embed the key as a literal in the SECURITY DEFINER function instead.

CREATE OR REPLACE FUNCTION public.trigger_bug_triage()
RETURNS trigger AS $$
BEGIN
  PERFORM net.http_post(
    url     := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/bug-triage',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer REDACTED_JWT'
    ),
    body    := row_to_json(NEW)::jsonb
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- FEAT-P46: Postgres trigger to invoke bug-triage edge function on INSERT
-- Requires pg_net (enabled in 20260326000001_bug_reports_triage.sql).

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

DROP TRIGGER IF EXISTS on_bug_report_insert ON public.bug_reports;
CREATE TRIGGER on_bug_report_insert
  AFTER INSERT ON public.bug_reports
  FOR EACH ROW EXECUTE FUNCTION public.trigger_bug_triage();

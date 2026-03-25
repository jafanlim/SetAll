-- FEAT-19: Schedule weekly-analysis every Monday at 08:00 UTC
SELECT cron.schedule(
  'weekly-analysis',
  '0 8 * * 1',
  $$ SELECT net.http_post(
    url     := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/weekly-analysis',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (
        SELECT decrypted_secret FROM vault.decrypted_secrets
        WHERE name = 'service_role_key' LIMIT 1
      ),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  ); $$
);

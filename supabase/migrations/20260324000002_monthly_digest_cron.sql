-- FEAT-17: Schedule monthly digest email on the 1st of each month at 09:00 UTC
SELECT cron.schedule(
  'send-monthly-digest',
  '0 9 1 * *',
  $$
    SELECT net.http_post(
      url := current_setting('app.supabase_url') ||
             '/functions/v1/monthly-digest',
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' ||
          current_setting('app.service_role_key'),
        'Content-Type', 'application/json'
      ),
      body := '{}'::jsonb
    );
  $$
);

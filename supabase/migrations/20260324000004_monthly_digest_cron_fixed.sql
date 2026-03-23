-- FEAT-18b: Re-schedule monthly digest using hardcoded project URL + Vault secret.
-- Replaces 20260324000002_monthly_digest_cron.sql which relied on unset GUC settings.

-- Drop the old job if it exists
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'send-monthly-digest') THEN
    PERFORM cron.unschedule('send-monthly-digest');
  END IF;
END $$;

-- Re-schedule using hardcoded project URL + vault secret
SELECT cron.schedule(
  'send-monthly-digest',
  '0 9 1 * *',
  $$
  SELECT net.http_post(
    url := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/monthly-digest',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (
        SELECT decrypted_secret
        FROM vault.decrypted_secrets
        WHERE name = 'service_role_key'
        LIMIT 1
      ),
      'Content-Type', 'application/json'
    ),
    body := '{}'::jsonb
  );
  $$
);

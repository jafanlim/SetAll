-- KEY ROTATION: Switch all edge function triggers and cron jobs from
-- "Authorization: Bearer <service_role>" to "x-edge-secret" header from Vault.
--
-- Prerequisites (run ONCE in SQL editor, NOT as a migration):
--   SELECT vault.create_secret('YOUR_EDGE_SHARED_SECRET', 'edge_shared_secret');
-- And set the same value as a Supabase secret:
--   supabase secrets set EDGE_SHARED_SECRET="YOUR_EDGE_SHARED_SECRET"

-- ── 1. Bug-triage trigger ─────────────────────────────────────────────────────
-- Replaces hardcoded service_role Bearer JWT in 20260326000002 and 20260326000004
CREATE OR REPLACE FUNCTION public.trigger_bug_triage()
RETURNS trigger AS $$
BEGIN
  PERFORM net.http_post(
    url     := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/bug-triage',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-edge-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'edge_shared_secret' LIMIT 1)
    ),
    body    := row_to_json(NEW)::jsonb
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 2. Group-notification trigger ────────────────────────────────────────────
-- Replaces Vault service_role_key lookup in 20260325000004
CREATE OR REPLACE FUNCTION public.notify_group_members()
RETURNS trigger AS $$
DECLARE
  v_member_ids uuid[];
  v_group_id   uuid;
  v_title      text;
  v_body_text  text;
BEGIN
  -- Derive group id and notification text from the triggering row
  v_group_id := COALESCE(NEW.group_id, OLD.group_id);

  SELECT array_agg(DISTINCT user_id)
    INTO v_member_ids
    FROM public.group_members
   WHERE group_id = v_group_id;

  IF v_member_ids IS NULL OR array_length(v_member_ids, 1) = 0
  THEN RETURN COALESCE(NEW, OLD); END IF;

  PERFORM net.http_post(
    url     := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/send-group-notification',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-edge-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'edge_shared_secret' LIMIT 1)
    ),
    body    := jsonb_build_object(
      'recipientUserIds', v_member_ids,
      'title',  COALESCE(NEW.title, 'Group update'),
      'body',   COALESCE(NEW.description, ''),
      'data',   jsonb_build_object('route', '/groups', 'groupId', v_group_id)
    )
  );
  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ── 3. Monthly-digest cron ────────────────────────────────────────────────────
-- Replaces service_role_key Vault lookup in 20260324000004
SELECT cron.unschedule('send-monthly-digest');
SELECT cron.schedule(
  'send-monthly-digest',
  '0 9 1 * *',
  $$
  SELECT net.http_post(
    url     := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/monthly-digest',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-edge-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'edge_shared_secret' LIMIT 1)
    ),
    body    := '{}'::jsonb
  );
  $$
);

-- ── 4. Weekly-analysis cron ───────────────────────────────────────────────────
-- Replaces service_role_key Vault lookup in 20260325000002
SELECT cron.unschedule('weekly-analysis');
SELECT cron.schedule(
  'weekly-analysis',
  '0 8 * * 1',
  $$
  SELECT net.http_post(
    url     := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/weekly-analysis',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'x-edge-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'edge_shared_secret' LIMIT 1)
    ),
    body    := '{}'::jsonb
  );
  $$
);

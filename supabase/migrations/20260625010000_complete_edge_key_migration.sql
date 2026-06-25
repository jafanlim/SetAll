-- KEY MIGRATION COMPLETION: Add apikey header to all trigger/cron net.http_post calls.
-- The 2026-06-01 migration switched from Bearer service_role → x-edge-secret but new-key
-- Supabase projects require a valid apikey on the header for the gateway to route the
-- request. Without it the gateway returns 403 and the function never runs.
--
-- Also re-schedules the two cron jobs with the apikey added.
--
-- Prerequisite (run ONCE in SQL editor, NOT in this migration):
--   SELECT vault.create_secret('sb_secret_…', 'secret_key');
-- The secret is read FROM Vault AT CALL TIME — the value is NEVER in this file.

-- ── 1. Bug-triage trigger ─────────────────────────────────────────────────────
-- Body verbatim from 20260625000000_harden_definer_search_path.sql (PR #22)
-- The ONLY change is the added apikey header line.
CREATE OR REPLACE FUNCTION public.trigger_bug_triage()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM net.http_post(
    url     := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/bug-triage',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key' LIMIT 1),
      'x-edge-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'edge_shared_secret' LIMIT 1)
    ),
    body    := row_to_json(NEW)::jsonb
  );
  RETURN NEW;
END;
$$;

-- ── 2. Group-notification trigger ────────────────────────────────────────────
-- Body verbatim from 20260625000000_harden_definer_search_path.sql (PR #22,
-- which integrated the 20260601000003 title fix). The ONLY change is the added
-- apikey header line.
CREATE OR REPLACE FUNCTION public.notify_group_members()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_group_id   uuid;
  v_actor_id   uuid;
  v_title      text;
  v_body       text;
  v_route      text;
  v_member_ids uuid[];
BEGIN
  IF TG_TABLE_NAME = 'expenses' THEN
    IF TG_OP = 'DELETE' THEN
      v_group_id := OLD.group_id;
      v_actor_id := OLD.payer_id;
      v_title    := 'Expense removed';
      v_body     := COALESCE(OLD.description, 'An expense') || ' was deleted';
    ELSE
      v_group_id := NEW.group_id;
      v_actor_id := NEW.payer_id;
      v_title    := CASE WHEN TG_OP = 'INSERT' THEN 'New expense' ELSE 'Expense updated' END;
      v_body     := COALESCE(NEW.description, 'An expense') ||
                    ' · ' || NEW.currency || ' ' || NEW.amount::text;
    END IF;
    v_route := '/groups/' || v_group_id::text;
  END IF;

  -- Only fire for group expenses (group_id NOT NULL).
  IF v_group_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  -- Collect member ids that have a token and have not disabled group activity
  -- notifications, excluding the actor.
  SELECT ARRAY_AGG(DISTINCT gm.user_id) INTO v_member_ids
  FROM public.group_members gm
  JOIN public.fcm_tokens ft ON ft.user_id = gm.user_id
  LEFT JOIN public.profiles p ON p.id = gm.user_id
  WHERE gm.group_id = v_group_id
    AND gm.user_id  != v_actor_id
    AND (p.notification_preferences->>'group_activity')::boolean IS NOT FALSE;

  IF v_member_ids IS NULL OR array_length(v_member_ids, 1) = 0
  THEN RETURN COALESCE(NEW, OLD); END IF;

  PERFORM net.http_post(
    url     := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/send-group-notification',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key' LIMIT 1),
      'x-edge-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'edge_shared_secret' LIMIT 1)
    ),
    body    := jsonb_build_object(
      'recipientUserIds', to_json(v_member_ids),
      'title',   v_title,
      'body',    v_body,
      'data',    jsonb_build_object('route', v_route, 'groupId', v_group_id)
    )
  );

  RETURN COALESCE(NEW, OLD);
END;
$$;

-- ── 3. Monthly-digest cron ────────────────────────────────────────────────────
-- Command body verbatim from 20260601000001_switch_triggers_to_edge_secret.sql
-- (crons were not touched by #22). The ONLY change is the added apikey header
-- line. Unschedules idempotently first.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'send-monthly-digest') THEN
    PERFORM cron.unschedule('send-monthly-digest');
  END IF;
END $$;

SELECT cron.schedule(
  'send-monthly-digest',
  '0 9 1 * *',
  $$
  SELECT net.http_post(
    url     := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/monthly-digest',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key' LIMIT 1),
      'x-edge-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'edge_shared_secret' LIMIT 1)
    ),
    body    := '{}'::jsonb
  );
  $$
);

-- ── 4. Weekly-analysis cron ───────────────────────────────────────────────────
-- Command body verbatim from 20260601000001_switch_triggers_to_edge_secret.sql
-- (crons were not touched by #22). The ONLY change is the added apikey header
-- line. Unschedules idempotently first.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'weekly-analysis') THEN
    PERFORM cron.unschedule('weekly-analysis');
  END IF;
END $$;

SELECT cron.schedule(
  'weekly-analysis',
  '0 8 * * 1',
  $$
  SELECT net.http_post(
    url     := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/weekly-analysis',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key' LIMIT 1),
      'x-edge-secret', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'edge_shared_secret' LIMIT 1)
    ),
    body    := '{}'::jsonb
  );
  $$
);

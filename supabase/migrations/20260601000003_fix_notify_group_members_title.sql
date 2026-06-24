-- =============================================================================
-- Fix: notify_group_members() references NEW.title, which does not exist on
-- public.expenses (the column is `description`). The Phase 0 rewrite in
-- 20260601000001_switch_triggers_to_edge_secret.sql replaced the original
-- per-table title/body logic (20260325000004) with a hardcoded
-- `COALESCE(NEW.title, 'Group update')`, so every GROUP expense write that
-- fires the AFTER trigger errors with:
--   record "new" has no field "title"  (SQLSTATE 42703)
--
-- Personal (wallet) expenses are unaffected because group_id IS NULL returns
-- early before the bad reference — which is why only group expense updates
-- broke.
--
-- This restores the correct derivation (computed title/body/route, DELETE uses
-- OLD, member/token/preference filtering, personal-expense skip) while keeping
-- the Phase 0 x-edge-secret header (Vault: edge_shared_secret) instead of the
-- old service_role Bearer token. Fix-forward: replaces the function in place.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.notify_group_members()
RETURNS trigger AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

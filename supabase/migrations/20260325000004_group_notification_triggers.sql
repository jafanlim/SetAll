-- FEAT-20: Trigger to notify group members on expense INSERT/UPDATE/DELETE
CREATE OR REPLACE FUNCTION notify_group_members() RETURNS TRIGGER AS $$
DECLARE
  v_group_id  uuid;
  v_actor_id  uuid;
  v_title     text;
  v_body      text;
  v_route     text;
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

  -- Only fire for group expenses (group_id NOT NULL)
  IF v_group_id IS NULL THEN RETURN COALESCE(NEW, OLD); END IF;

  -- Collect member FCM tokens (exclude actor; respect notification pref)
  SELECT ARRAY_AGG(gm.user_id) INTO v_member_ids
  FROM group_members gm
  JOIN fcm_tokens ft ON ft.user_id = gm.user_id
  LEFT JOIN profiles p ON p.id = gm.user_id
  WHERE gm.group_id = v_group_id
    AND gm.user_id  != v_actor_id
    AND (p.notification_preferences->>'group_activity')::boolean IS NOT FALSE;

  IF v_member_ids IS NULL OR array_length(v_member_ids, 1) = 0
  THEN RETURN COALESCE(NEW, OLD); END IF;

  PERFORM net.http_post(
    url     := 'https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/send-group-notification',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || (
        SELECT decrypted_secret FROM vault.decrypted_secrets
        WHERE name = 'service_role_key' LIMIT 1
      ),
      'Content-Type', 'application/json'
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

DROP TRIGGER IF EXISTS notify_on_expense ON public.expenses;
CREATE TRIGGER notify_on_expense
  AFTER INSERT OR UPDATE OR DELETE ON public.expenses
  FOR EACH ROW EXECUTE FUNCTION notify_group_members();

-- RPC: delete_user_data()
-- Soft-deletes the calling user's profile with a 30-day cooling-off period.
-- Called from the Settings screen "Delete Account" flow.
-- SECURITY DEFINER so it can update profiles regardless of RLS policies,
-- but auth.uid() ensures only the authenticated user can delete their own data.

CREATE OR REPLACE FUNCTION public.delete_user_data()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Not authenticated');
  END IF;

  UPDATE public.profiles
  SET
    is_deleted             = true,
    scheduled_deletion_at  = now() + INTERVAL '30 days'
  WHERE id = v_uid;

  RETURN jsonb_build_object('success', true);
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_user_data() TO authenticated;

-- =============================================================================
-- SetAll: create_group RPC — SECURITY DEFINER to bypass RLS on groups INSERT
--
-- The groups INSERT RLS policy (auth.uid() = creator_id) is being blocked
-- despite the policy existing. Using a SECURITY DEFINER function bypasses
-- RLS entirely and is the same pattern used for add_member_by_id.
--
-- Returns the new group's UUID.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.create_group(
  p_name TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid      UUID := auth.uid();
  v_group_id UUID := gen_random_uuid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  IF trim(p_name) = '' THEN
    RAISE EXCEPTION 'group_name_empty';
  END IF;

  INSERT INTO public.groups (id, name, creator_id, type)
  VALUES (v_group_id, trim(p_name), v_uid, 'normal');

  INSERT INTO public.group_members (group_id, user_id)
  VALUES (v_group_id, v_uid)
  ON CONFLICT DO NOTHING;

  RETURN v_group_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_group(TEXT) TO authenticated;

COMMENT ON FUNCTION public.create_group IS
  'Creates a normal group and adds the caller as a member. SECURITY DEFINER bypasses RLS.';

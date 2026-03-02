-- =============================================================================
-- SetAll: SECURITY DEFINER RPC to remove a member from a group.
-- Only the group creator can remove members; a creator cannot remove themselves.
-- Safe to re-run.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.remove_group_member(
  p_group_id UUID,
  p_user_id  UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_creator_id UUID;
BEGIN
  -- Caller must be the group creator.
  SELECT creator_id INTO v_creator_id
    FROM public.groups
   WHERE id = p_group_id;

  IF v_creator_id IS NULL THEN
    RAISE EXCEPTION 'group_not_found';
  END IF;

  IF v_creator_id <> auth.uid() THEN
    RAISE EXCEPTION 'not_group_creator';
  END IF;

  -- Cannot remove the creator themselves.
  IF p_user_id = v_creator_id THEN
    RAISE EXCEPTION 'cannot_remove_creator';
  END IF;

  DELETE FROM public.group_members
   WHERE group_id = p_group_id
     AND user_id  = p_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.remove_group_member(UUID, UUID) TO authenticated;

-- ============================================================
-- SetAll: add_member_by_id RPC
-- Allows any existing group member (not just creator) to add
-- another registered user by their profile UUID.
-- Run in Supabase SQL Editor after the previous migration.
-- ============================================================

CREATE OR REPLACE FUNCTION public.add_member_by_id(
  p_group_id UUID,
  p_user_id  UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Caller must be the group creator OR already a member
  IF NOT EXISTS (
    SELECT 1 FROM public.groups
    WHERE id = p_group_id AND creator_id = auth.uid()
  ) AND NOT EXISTS (
    SELECT 1 FROM public.group_members
    WHERE group_id = p_group_id AND user_id = auth.uid()
  ) THEN
    RAISE EXCEPTION 'You must be a member of this group to add people';
  END IF;

  -- Target user must exist as a real (non-ghost) profile
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = p_user_id AND is_ghost = FALSE
  ) THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  INSERT INTO public.group_members (group_id, user_id)
  VALUES (p_group_id, p_user_id)
  ON CONFLICT (group_id, user_id) DO NOTHING;
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_member_by_id(UUID, UUID) TO authenticated;

COMMENT ON FUNCTION public.add_member_by_id IS
  'Add a registered user to a group by UUID; caller must be group creator or member';

-- =============================================================================
-- SetAll: Add get_group_members() SECURITY DEFINER RPC
--
-- Problem: group_members SELECT RLS may only return the current user's own row
-- if an earlier policy version is still active, causing split calculations to
-- only include 1 participant (the current user or one other member).
--
-- Fix: A SECURITY DEFINER function that reads group_members as the DB owner,
-- bypassing RLS entirely. Only returns members of groups the caller belongs to
-- (enforced via get_my_groups() check so it cannot be abused to enumerate all
-- groups).
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_group_members(p_group_id UUID)
RETURNS TABLE (user_id UUID)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT gm.user_id
  FROM public.group_members gm
  WHERE gm.group_id = p_group_id
    AND p_group_id IN (SELECT public.get_my_groups());
$$;

GRANT EXECUTE ON FUNCTION public.get_group_members(UUID) TO authenticated;

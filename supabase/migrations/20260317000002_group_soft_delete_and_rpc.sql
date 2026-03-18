-- ============================================================
-- 1. Add is_deleted flag to groups so soft-deletes on mobile
--    are also visible to the web (Supabase) query path.
-- ============================================================
ALTER TABLE public.groups
  ADD COLUMN IF NOT EXISTS is_deleted boolean NOT NULL DEFAULT false;

-- Index so RLS / get_my_groups scans stay fast.
CREATE INDEX IF NOT EXISTS idx_groups_is_deleted
  ON public.groups (is_deleted) WHERE is_deleted = false;

-- ============================================================
-- 2. Update get_my_groups() to exclude soft-deleted groups.
--    Previous version returned creator groups even after delete.
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_my_groups()
RETURNS setof uuid
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT group_id
  FROM   public.group_members
  WHERE  user_id = auth.uid()
  UNION
  SELECT id
  FROM   public.groups
  WHERE  creator_id = auth.uid()
    AND  is_deleted = false;
$$;

-- ============================================================
-- 3. SECURITY DEFINER RPC: delete_group
--    Bypasses RLS so the creator can cascade-delete splits and
--    expenses paid by OTHER members (normal RLS would block this).
-- ============================================================
CREATE OR REPLACE FUNCTION public.delete_group(p_group_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_creator_id uuid;
BEGIN
  SELECT creator_id INTO v_creator_id
  FROM   groups
  WHERE  id = p_group_id;

  IF v_creator_id IS DISTINCT FROM auth.uid() THEN
    RAISE EXCEPTION 'permission_denied: only the group creator can delete this group';
  END IF;

  DELETE FROM splits
  WHERE  expense_id IN (
    SELECT id FROM expenses WHERE group_id = p_group_id
  );

  DELETE FROM expenses    WHERE group_id = p_group_id;
  DELETE FROM group_members WHERE group_id = p_group_id;
  DELETE FROM groups        WHERE id       = p_group_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.delete_group(uuid) TO authenticated;

-- ============================================================
-- 4. SECURITY DEFINER RPC: leave_group
--    Non-creator leave — removes only the caller's member row.
-- ============================================================
CREATE OR REPLACE FUNCTION public.leave_group(p_group_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  DELETE FROM group_members
  WHERE  group_id = p_group_id
    AND  user_id  = auth.uid();
END;
$$;

GRANT EXECUTE ON FUNCTION public.leave_group(uuid) TO authenticated;

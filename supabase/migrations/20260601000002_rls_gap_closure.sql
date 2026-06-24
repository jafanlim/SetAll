-- =============================================================================
-- setall-secret-rls-audit · Phase 1 — RLS gap closure
--
-- Closes the three gaps surfaced by the Phase 1 audit. Read paths were diffed
-- first (lib/data/repositories/setall_repository.dart, lib/core/services/
-- sync_service.dart) to confirm none of these changes break an existing query.
--
--   GAP 1 (HIGH)  profiles "Users can read all profiles" USING (true) had no
--                 TO clause → every authenticated user AND anon could SELECT
--                 the entire profiles table. Reads are already covered by
--                 "Profiles viewable by group members" (self + co-members) and
--                 the search_profiles() SECURITY DEFINER RPC, so the blanket
--                 policy is removed.
--
--   GAP 2 (MED)   expenses has a soft-delete column (deleted_at) but neither
--                 SELECT policy filtered it. Group deletes are HARD deletes so
--                 the filter is a no-op there; personal (wallet) deletes on web
--                 are SOFT (update deleted_at) — without the filter those rows
--                 stayed visible in the activity feed / totals and never
--                 propagated to other devices. Adding deleted_at IS NULL fixes
--                 both the exposure and the latent delete-propagation bug.
--
--   GAP 3 (MED)   Non-creator members could not settle/reopen a group: the only
--                 groups UPDATE policy is "Creator can update group". A broad
--                 member-UPDATE policy would also expose name/creator_id/
--                 is_deleted, so settlement is handled by a membership-checked
--                 SECURITY DEFINER RPC instead (same pattern as delete_group /
--                 leave_group / remove_group_member).
--
-- Safe to re-run (idempotent).
-- =============================================================================

BEGIN;

-- ── GAP 1: remove blanket profiles SELECT ───────────────────────────────────
DROP POLICY IF EXISTS "Users can read all profiles" ON public.profiles;

-- Defensive: ensure the group-scoped SELECT policy exists (created in
-- 20260227000002). Recreated here so this migration is self-sufficient.
DROP POLICY IF EXISTS "Profiles viewable by group members" ON public.profiles;
CREATE POLICY "Profiles viewable by group members" ON public.profiles
  FOR SELECT
  USING (
    id = auth.uid()
    OR id IN (
      SELECT gm.user_id FROM public.group_members gm
      WHERE gm.group_id IN (SELECT public.get_my_groups())
    )
  );

-- ── GAP 2: expenses SELECT must hide soft-deleted rows ───────────────────────
DROP POLICY IF EXISTS "Group members can read expenses" ON public.expenses;
CREATE POLICY "Group members can read expenses" ON public.expenses
  FOR SELECT
  USING (
    group_id IN (SELECT public.get_my_groups())
    AND deleted_at IS NULL
  );

DROP POLICY IF EXISTS "Owner can read personal expenses" ON public.expenses;
CREATE POLICY "Owner can read personal expenses" ON public.expenses
  FOR SELECT
  USING (
    group_id IS NULL
    AND payer_id = auth.uid()
    AND deleted_at IS NULL
  );

-- ── GAP 3: membership-checked settlement RPC ─────────────────────────────────
-- groups UPDATE stays creator-only. This RPC runs as the table owner and only
-- mutates settled_at / settled_by after verifying the caller is a group member.
CREATE OR REPLACE FUNCTION public.set_group_settlement(
  p_group_id uuid,
  p_settled  boolean
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_group_id NOT IN (SELECT public.get_my_groups()) THEN
    RAISE EXCEPTION 'permission_denied: only a group member can change settlement';
  END IF;

  IF p_settled THEN
    UPDATE public.groups
       SET settled_at = now(),
           settled_by = auth.uid()
     WHERE id = p_group_id;
  ELSE
    UPDATE public.groups
       SET settled_at = NULL,
           settled_by = NULL
     WHERE id = p_group_id;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_group_settlement(uuid, boolean) TO authenticated;

COMMIT;

-- Reload PostgREST schema cache so the new RPC is exposed immediately.
NOTIFY pgrst, 'reload schema';

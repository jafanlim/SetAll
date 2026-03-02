-- =============================================================================
-- SetAll: Nuclear fix for 42P17 infinite recursion across ALL tables
-- Run in Supabase SQL Editor: Dashboard → SQL Editor → New query → Run
-- Safe to re-run.
--
-- The live DB accumulated overlapping policies from multiple migration runs.
-- Any policy on ANY table that directly subqueries group_members (without
-- SECURITY DEFINER) will trigger group_members's own SELECT policy, which
-- may trigger other policies, creating cross-table recursion cycles.
--
-- Strategy:
--   1. Ensure get_my_groups() SECURITY DEFINER exists — it queries
--      group_members as the DB owner, bypassing RLS entirely.
--   2. Drop EVERY policy on group_members (all SELECT variants).
--   3. Drop EVERY policy on other tables that directly subqueries group_members.
--   4. Recreate one clean policy per table using get_my_groups().
-- =============================================================================

-- ── 1. Ensure SECURITY DEFINER helper ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_my_groups()
RETURNS SETOF UUID
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT group_id FROM public.group_members WHERE user_id = auth.uid()
  UNION
  SELECT id FROM public.groups WHERE creator_id = auth.uid();
$$;
GRANT EXECUTE ON FUNCTION public.get_my_groups() TO authenticated;

-- ── 2. Drop ALL SELECT policies on group_members ──────────────────────────────
DROP POLICY IF EXISTS "Members can read group_members"         ON public.group_members;
DROP POLICY IF EXISTS "members can read group_members"         ON public.group_members;
DROP POLICY IF EXISTS "Members can see other members"          ON public.group_members;
DROP POLICY IF EXISTS "Users can view members of their groups" ON public.group_members;

-- ── 3. Drop broken policies on other tables ───────────────────────────────────

-- groups
DROP POLICY IF EXISTS "Users can read groups they belong to"   ON public.groups;
DROP POLICY IF EXISTS "Users can see groups they belong to"    ON public.groups;

-- expenses
DROP POLICY IF EXISTS "Users can see group expenses"                       ON public.expenses;
DROP POLICY IF EXISTS "Group members can read expenses"                    ON public.expenses;
DROP POLICY IF EXISTS "Group members can insert expenses"                  ON public.expenses;

-- splits
DROP POLICY IF EXISTS "Group members can read splits for their group expenses" ON public.splits;
DROP POLICY IF EXISTS "Users can see group splits"                             ON public.splits;

-- pending_invites
DROP POLICY IF EXISTS "Members can read pending invites for their groups"  ON public.pending_invites;
DROP POLICY IF EXISTS "Group members can read pending invites"             ON public.pending_invites;
DROP POLICY IF EXISTS "Group members can create invites"                   ON public.pending_invites;

-- profiles
DROP POLICY IF EXISTS "Profiles viewable by group members"                ON public.profiles;

-- ── 4. Recreate all policies cleanly using get_my_groups() ───────────────────

-- group_members: single SELECT policy, no recursion
CREATE POLICY "Members can read group_members" ON public.group_members
  FOR SELECT
  USING (
    user_id = auth.uid()
    OR group_id IN (SELECT public.get_my_groups())
  );

-- groups
CREATE POLICY "Users can read groups they belong to" ON public.groups
  FOR SELECT
  USING (id IN (SELECT public.get_my_groups()));

-- expenses
CREATE POLICY "Group members can read expenses" ON public.expenses
  FOR SELECT
  USING (group_id IN (SELECT public.get_my_groups()));

CREATE POLICY "Group members can insert expenses" ON public.expenses
  FOR INSERT
  WITH CHECK (
    auth.uid() = payer_id
    AND group_id IN (SELECT public.get_my_groups())
  );

-- splits
CREATE POLICY "Group members can read splits for their group expenses" ON public.splits
  FOR SELECT
  USING (
    expense_id IN (
      SELECT e.id FROM public.expenses e
      WHERE e.group_id IN (SELECT public.get_my_groups())
    )
  );

-- pending_invites
CREATE POLICY "Group members can read pending invites" ON public.pending_invites
  FOR SELECT
  USING (group_id IN (SELECT public.get_my_groups()));

CREATE POLICY "Group members can create invites" ON public.pending_invites
  FOR INSERT
  WITH CHECK (group_id IN (SELECT public.get_my_groups()));

-- profiles: members of the same group can see each other's profiles
CREATE POLICY "Profiles viewable by group members" ON public.profiles
  FOR SELECT
  USING (
    id = auth.uid()
    OR id IN (
      SELECT gm.user_id FROM public.group_members gm
      WHERE gm.group_id IN (SELECT public.get_my_groups())
    )
  );

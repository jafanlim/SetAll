-- =============================================================================
-- SetAll: Fix missing INSERT/UPDATE/DELETE RLS policies
-- Safe to re-run.
--
-- Problems addressed:
--   1. group_members has no INSERT policy for regular members → addMemberById
--      RPC is SECURITY DEFINER (fine), but _ensureSplitParticipantsAreMembers
--      upserts directly and gets blocked for non-creators.
--   2. splits has no INSERT policy for the payer when inserting via direct
--      client (non-RPC path used by addExpense on web).
--   3. expenses has no UPDATE/DELETE policy reachable via get_my_groups().
--   4. profiles has no UPDATE policy → updateProfile fails for non-owner rows.
-- =============================================================================

-- ── group_members: allow any member of a group to add new members ─────────────
-- The SECURITY DEFINER add_member_by_id RPC already enforces membership checks;
-- this policy covers the direct upsert in _ensureSplitParticipantsAreMembers.
DROP POLICY IF EXISTS "Members can insert group_members" ON public.group_members;
CREATE POLICY "Members can insert group_members" ON public.group_members
  FOR INSERT
  WITH CHECK (
    group_id IN (SELECT public.get_my_groups())
  );

-- ── splits: payer can insert splits for their own expenses ───────────────────
DROP POLICY IF EXISTS "Expense payer can insert splits" ON public.splits;
CREATE POLICY "Expense payer can insert splits" ON public.splits
  FOR INSERT
  WITH CHECK (
    expense_id IN (
      SELECT id FROM public.expenses WHERE payer_id = auth.uid()
    )
  );

-- ── splits: payer can delete/update splits (for updateExpense) ───────────────
-- The old "Expense payer can manage splits" FOR ALL covers SELECT+INSERT+UPDATE+DELETE
-- but SELECT is handled by a separate policy so we keep ALL here for safety.
-- Ensure the policy exists with the right name from migration 20260227000002.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'splits'
      AND policyname = 'Expense payer can manage splits'
  ) THEN
    CREATE POLICY "Expense payer can manage splits" ON public.splits
      FOR ALL
      USING (
        expense_id IN (SELECT id FROM public.expenses WHERE payer_id = auth.uid())
      );
  END IF;
END $$;

-- ── expenses: UPDATE and DELETE policies (payer or group creator) ────────────
DROP POLICY IF EXISTS "Payer or group creator can update expense" ON public.expenses;
CREATE POLICY "Payer or group creator can update expense" ON public.expenses
  FOR UPDATE
  USING (
    payer_id = auth.uid()
    OR group_id IN (SELECT id FROM public.groups WHERE creator_id = auth.uid())
  );

DROP POLICY IF EXISTS "Payer or group creator can delete expense" ON public.expenses;
CREATE POLICY "Payer or group creator can delete expense" ON public.expenses
  FOR DELETE
  USING (
    payer_id = auth.uid()
    OR group_id IN (SELECT id FROM public.groups WHERE creator_id = auth.uid())
  );

-- ── profiles: users can update their own row ─────────────────────────────────
DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile" ON public.profiles
  FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- ── profiles: users can insert their own row (needed for handle_new_user path) ─
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles'
      AND policyname = 'Users can insert own profile'
  ) THEN
    CREATE POLICY "Users can insert own profile" ON public.profiles
      FOR INSERT
      WITH CHECK (id = auth.uid());
  END IF;
END $$;

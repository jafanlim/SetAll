-- =============================================================================
-- SetAll: Fix UPDATE/DELETE RLS on splits + expenses so that any group member
-- can update expenses and their splits, not just the original payer.
--
-- Problems addressed:
--   1. splits DELETE/UPDATE policy only allows payer_id = auth.uid() — this
--      blocks changing payer or fixing splits if you weren't the original payer.
--   2. expenses UPDATE policy only allows payer_id = auth.uid() OR group creator —
--      same problem for group members who want to correct an expense.
-- =============================================================================

-- ── splits: any group member can delete/update splits in their groups ─────────
DROP POLICY IF EXISTS "Expense payer can manage splits" ON public.splits;
DROP POLICY IF EXISTS "Expense payer can insert splits" ON public.splits;
DROP POLICY IF EXISTS "Group members can manage splits" ON public.splits;

CREATE POLICY "Group members can manage splits" ON public.splits
  FOR ALL
  USING (
    expense_id IN (
      SELECT e.id FROM public.expenses e
      WHERE e.group_id IN (SELECT public.get_my_groups())
    )
  )
  WITH CHECK (
    expense_id IN (
      SELECT e.id FROM public.expenses e
      WHERE e.group_id IN (SELECT public.get_my_groups())
    )
  );

-- ── expenses: any group member can update/delete expenses in their groups ─────
DROP POLICY IF EXISTS "Payer or group creator can update expense" ON public.expenses;
DROP POLICY IF EXISTS "Payer or group creator can delete expense" ON public.expenses;
DROP POLICY IF EXISTS "Group members can update expense" ON public.expenses;
DROP POLICY IF EXISTS "Group members can delete expense" ON public.expenses;

CREATE POLICY "Group members can update expense" ON public.expenses
  FOR UPDATE
  USING (group_id IN (SELECT public.get_my_groups()))
  WITH CHECK (group_id IN (SELECT public.get_my_groups()));

CREATE POLICY "Group members can delete expense" ON public.expenses
  FOR DELETE
  USING (group_id IN (SELECT public.get_my_groups()));

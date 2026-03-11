-- Allow any group member to insert an expense on behalf of any payer.
-- Previously the INSERT policy required auth.uid() = payer_id, which blocked
-- the "someone else paid" workflow where user A records an expense paid by B.

-- ── expenses: INSERT ─────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "Group members can insert expenses" ON public.expenses;

CREATE POLICY "Group members can insert expenses" ON public.expenses
  FOR INSERT
  WITH CHECK (
    group_id IN (SELECT public.get_my_groups())
  );

-- Personal (wallet) expenses: still only the owner can insert.
-- These have group_id IS NULL so the group policy above doesn't cover them.
DROP POLICY IF EXISTS "Payer can insert personal expense" ON public.expenses;

CREATE POLICY "Payer can insert personal expense" ON public.expenses
  FOR INSERT
  WITH CHECK (
    group_id IS NULL AND auth.uid() = payer_id
  );

-- ── splits: INSERT ───────────────────────────────────────────────────────────
-- Previously required expense payer = auth.uid(). Now any group member can
-- insert splits for any expense in their group.
DROP POLICY IF EXISTS "Expense payer can insert splits" ON public.splits;

CREATE POLICY "Group members can insert splits" ON public.splits
  FOR INSERT
  WITH CHECK (
    expense_id IN (
      SELECT e.id FROM public.expenses e
      WHERE e.group_id IN (SELECT public.get_my_groups())
    )
  );

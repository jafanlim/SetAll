-- =============================================================================
-- Fix splits RLS: make WITH CHECK explicit so INSERT never fails due to
-- implicit policy evaluation order.
-- Safe to re-run (DROP + CREATE is idempotent here).
-- =============================================================================

DROP POLICY IF EXISTS "Expense payer can manage splits" ON public.splits;

CREATE POLICY "Expense payer can manage splits"
  ON public.splits
  FOR ALL
  USING (
    expense_id IN (
      SELECT id FROM public.expenses WHERE payer_id = auth.uid()
    )
  )
  WITH CHECK (
    expense_id IN (
      SELECT id FROM public.expenses WHERE payer_id = auth.uid()
    )
  );

-- =============================================================================
-- Allow expense payers to soft-delete (set deleted_at) and restore (clear it).
-- The existing "Owner can update personal expenses" policy requires group_id IS NULL
-- and "Group members can update expense" requires group membership — neither
-- explicitly covers the case where the payer just wants to toggle deleted_at.
-- This policy is additive (permissive) and sits alongside existing policies.
-- =============================================================================

-- Let the payer soft-delete or restore any expense they paid for, personal or group.
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'expenses'
      AND policyname = 'Payer can soft-delete own expenses'
  ) THEN
    CREATE POLICY "Payer can soft-delete own expenses"
      ON public.expenses
      FOR UPDATE
      USING (payer_id = auth.uid())
      WITH CHECK (payer_id = auth.uid());
  END IF;
END $$;

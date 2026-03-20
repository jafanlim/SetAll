-- =============================================================================
-- Fix RLS for personal expense upsert (UPDATE path).
--
-- Root cause: SyncService._pushPendingToSupabase uses upsert() which triggers
-- both INSERT and UPDATE policies. The INSERT policy for personal expenses
-- (group_id IS NULL AND payer_id = auth.uid()) is correct, but the UPDATE
-- policy from 20260302000002 only covers group expenses via get_my_groups()
-- and has no WITH CHECK — so when a personal expense row already exists in
-- Supabase and upsert hits the UPDATE path, Postgres finds no matching WITH
-- CHECK and rejects it with 42501.
--
-- Fix: drop and recreate the personal expense UPDATE policy with explicit
-- WITH CHECK so the upsert UPDATE path is permitted.
-- =============================================================================

-- Personal expenses UPDATE: owner can update their own wallet expenses.
DROP POLICY IF EXISTS "Owner can update personal expenses" ON public.expenses;
CREATE POLICY "Owner can update personal expenses"
  ON public.expenses
  FOR UPDATE
  USING (
    group_id IS NULL
    AND payer_id = auth.uid()
  )
  WITH CHECK (
    group_id IS NULL
    AND payer_id = auth.uid()
  );

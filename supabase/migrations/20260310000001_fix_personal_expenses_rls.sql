-- =============================================================================
-- Fix RLS for personal (wallet) expenses: group_id IS NULL rows are owned by
-- payer_id and must be readable/writable by that user.
--
-- The original policies only cover group expenses (group_id IN get_my_groups()).
-- Personal expenses have group_id IS NULL and were therefore invisible to the
-- SELECT policy and blocked by the INSERT policy.
-- =============================================================================

-- ── expenses: allow group_id to be NULL (personal/wallet entries) ─────────────
-- The original column was NOT NULL — drop that constraint so personal expenses
-- can be stored. (Safe no-op if already nullable.)
ALTER TABLE public.expenses
  ALTER COLUMN group_id DROP NOT NULL;

-- ── SELECT: owner can read their own personal expenses ───────────────────────
DROP POLICY IF EXISTS "Owner can read personal expenses" ON public.expenses;
CREATE POLICY "Owner can read personal expenses"
  ON public.expenses FOR SELECT
  USING (
    group_id IS NULL
    AND payer_id = auth.uid()
  );

-- ── INSERT: owner can insert their own personal expenses ─────────────────────
DROP POLICY IF EXISTS "Owner can insert personal expenses" ON public.expenses;
CREATE POLICY "Owner can insert personal expenses"
  ON public.expenses FOR INSERT
  WITH CHECK (
    group_id IS NULL
    AND payer_id = auth.uid()
  );

-- ── UPDATE: owner can update their own personal expenses ─────────────────────
DROP POLICY IF EXISTS "Owner can update personal expenses" ON public.expenses;
CREATE POLICY "Owner can update personal expenses"
  ON public.expenses FOR UPDATE
  USING (
    group_id IS NULL
    AND payer_id = auth.uid()
  );

-- ── DELETE: owner can delete their own personal expenses ─────────────────────
DROP POLICY IF EXISTS "Owner can delete personal expenses" ON public.expenses;
CREATE POLICY "Owner can delete personal expenses"
  ON public.expenses FOR DELETE
  USING (
    group_id IS NULL
    AND payer_id = auth.uid()
  );

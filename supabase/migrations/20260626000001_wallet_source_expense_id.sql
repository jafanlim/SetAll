-- Add source_expense_id to public.expenses for wallet mirror linking + dedupe.
-- Phase 1 (data layer only): no UI, no share calc, no activity events.
-- Idempotent: uses ADD COLUMN IF NOT EXISTS.

DO $$
BEGIN
  -- 1. column ---------------------------------------------------
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'expenses'
      AND column_name  = 'source_expense_id'
  ) THEN
    ALTER TABLE public.expenses
      ADD COLUMN source_expense_id uuid
        REFERENCES public.expenses(id) ON DELETE SET NULL;
  END IF;

  -- 2. partial index (dedupe look-ups) --------------------------
  IF NOT EXISTS (
    SELECT 1 FROM pg_indexes
    WHERE schemaname = 'public'
      AND tablename  = 'expenses'
      AND indexname  = 'idx_expenses_payer_source_expense'
  ) THEN
    CREATE INDEX idx_expenses_payer_source_expense
      ON public.expenses (payer_id, source_expense_id)
      WHERE source_expense_id IS NOT NULL;
  END IF;
END;
$$;

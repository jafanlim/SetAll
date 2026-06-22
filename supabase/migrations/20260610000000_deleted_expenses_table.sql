-- =============================================================================
-- Soft-delete via a dedicated deleted_expenses table.
-- Instead of updating expenses.deleted_at (which requires UPDATE RLS that is
-- currently blocked), we snapshot into this table on delete and read from it
-- on restore. Uses only INSERT + DELETE — both proven to work through RLS.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.deleted_expenses (
  id              uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  expense_id      uuid NOT NULL,
  description     text,
  amount          text NOT NULL,
  original_amount text,
  currency        text NOT NULL DEFAULT 'USD',
  group_id        uuid,
  group_name      text,
  is_income       boolean NOT NULL DEFAULT false,
  category        text NOT NULL DEFAULT 'Other',
  deleted_by      uuid NOT NULL,
  deleted_at      timestamptz NOT NULL DEFAULT now(),
  is_wallet       boolean NOT NULL DEFAULT false
);

-- Enable RLS.
ALTER TABLE public.deleted_expenses ENABLE ROW LEVEL SECURITY;

-- Only the user who deleted an expense can see or restore its tombstone.
CREATE POLICY "Deleter can read own tombs"
  ON public.deleted_expenses FOR SELECT
  USING (deleted_by = auth.uid());

CREATE POLICY "Deleter can insert tombs"
  ON public.deleted_expenses FOR INSERT
  WITH CHECK (deleted_by = auth.uid());

CREATE POLICY "Deleter can delete own tombs"
  ON public.deleted_expenses FOR DELETE
  USING (deleted_by = auth.uid());

-- Enable realtime for sync-like behaviour.
ALTER PUBLICATION supabase_realtime ADD TABLE public.deleted_expenses;

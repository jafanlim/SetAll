ALTER TABLE public.deleted_expenses
  ADD COLUMN IF NOT EXISTS created_at timestamptz;

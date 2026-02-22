-- =============================================================
-- Expenses table: add base_amount_at_entry column
-- Stores the pre-computed expense total in the user's base
-- currency at the moment the expense was created.
-- This column is the definitive answer to "what is this worth
-- in my base currency?" — immune to future rate fluctuations.
-- =============================================================
ALTER TABLE public.expenses
  ADD COLUMN IF NOT EXISTS base_amount_at_entry NUMERIC(24, 10);

COMMENT ON COLUMN public.expenses.base_amount_at_entry IS
  'Total expense amount in the payer''s base currency at entry time. '
  'Used by BalanceService to avoid live rate lookups for historical data. '
  'Populated on every new expense; NULL for legacy rows.';

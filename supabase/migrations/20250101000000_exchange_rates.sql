-- =============================================================
-- SetAll: Automated Exchange Rate Infrastructure
-- =============================================================
-- Single source of truth: populated by Edge Function every 24h.
-- All rates are relative to USD as the base (1 USD = X target).
-- =============================================================

-- Exchange rates table
CREATE TABLE IF NOT EXISTS public.exchange_rates (
  id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  base_currency   TEXT        NOT NULL,
  target_currency TEXT        NOT NULL,
  rate            NUMERIC(24, 12) NOT NULL CHECK (rate > 0),
  last_updated    TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (base_currency, target_currency)
);

-- Row-level security: everyone can read, only service_role can write
ALTER TABLE public.exchange_rates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "exchange_rates_read_authenticated"
  ON public.exchange_rates FOR SELECT
  TO authenticated USING (true);

CREATE POLICY "exchange_rates_read_anon"
  ON public.exchange_rates FOR SELECT
  TO anon USING (true);

-- Fast lookup index
CREATE INDEX IF NOT EXISTS idx_er_pair
  ON public.exchange_rates (base_currency, target_currency);

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

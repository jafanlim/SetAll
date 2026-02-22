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


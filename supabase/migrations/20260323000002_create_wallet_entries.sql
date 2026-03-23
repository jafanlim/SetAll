CREATE TABLE IF NOT EXISTS public.wallet_entries (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  amount numeric NOT NULL CHECK (amount >= 0),
  is_income boolean NOT NULL DEFAULT false,
  description text NOT NULL DEFAULT '',
  category text DEFAULT 'Other',
  currency text NOT NULL DEFAULT 'USD',
  original_amount numeric,
  original_currency text,
  exchange_rate_applied numeric,
  universal_usd_amount numeric NOT NULL DEFAULT 0,
  icon_codepoint integer,
  icon_color integer,
  notes text,
  attachment_urls text,
  deleted_at timestamptz DEFAULT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  synced_at timestamptz,
  CONSTRAINT wallet_entries_pkey PRIMARY KEY (id)
);

DROP TRIGGER IF EXISTS wallet_entries_set_updated_at ON public.wallet_entries;
CREATE TRIGGER wallet_entries_set_updated_at
  BEFORE UPDATE ON public.wallet_entries
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

ALTER TABLE public.wallet_entries ENABLE ROW LEVEL SECURITY;

CREATE POLICY "wallet_entries_owner" ON public.wallet_entries
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_wallet_entries_user_created
  ON public.wallet_entries(user_id, created_at DESC);

ALTER TABLE public.wallet_entries REPLICA IDENTITY FULL;

-- setall-proactive-alerts: alert_prefs + alert_log tables with RLS
-- ---------------------------------------------------------------------

-- alert_prefs: one row per user, stores their alert preferences
CREATE TABLE IF NOT EXISTS public.alert_prefs (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id          UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  anomaly_enabled  BOOLEAN NOT NULL DEFAULT true,
  budget_80_enabled BOOLEAN NOT NULL DEFAULT true,
  budget_100_enabled BOOLEAN NOT NULL DEFAULT true,
  -- k multiplier for anomaly: flag when expense > k * category_mean
  anomaly_k        NUMERIC(4,2) NOT NULL DEFAULT 2.0,
  -- number of months to compute category mean over
  anomaly_months   SMALLINT NOT NULL DEFAULT 3,
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(user_id)
);

ALTER TABLE public.alert_prefs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "alert_prefs_select" ON public.alert_prefs
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "alert_prefs_insert" ON public.alert_prefs
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "alert_prefs_update" ON public.alert_prefs
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "alert_prefs_delete" ON public.alert_prefs
  FOR DELETE USING (auth.uid() = user_id);

-- alert_log: deduplication log — one entry per (user, alert_type, ref_key)
-- Prevents the same alert firing twice for the same event.
CREATE TABLE IF NOT EXISTS public.alert_log (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  alert_type  TEXT NOT NULL,  -- 'anomaly' | 'budget_80' | 'budget_100'
  ref_key     TEXT NOT NULL,  -- expense_id or 'budget:<category>:<period>'
  fired_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.alert_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "alert_log_select" ON public.alert_log
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "alert_log_insert" ON public.alert_log
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "alert_log_delete" ON public.alert_log
  FOR DELETE USING (auth.uid() = user_id);

-- Index for fast dedup look-up
CREATE INDEX IF NOT EXISTS alert_log_user_key
  ON public.alert_log(user_id, alert_type, ref_key);

-- FEAT-19: AI weekly analysis insights table
CREATE TABLE IF NOT EXISTS public.ai_insights (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  analysis_type   text        NOT NULL CHECK (analysis_type IN ('weekly','monthly','on_demand')),
  period_start    timestamptz NOT NULL,
  period_end      timestamptz NOT NULL,
  summary         text        NOT NULL,
  top_category    text,
  net_change      numeric,
  income_total    numeric,
  expense_total   numeric,
  raw_response    jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.ai_insights ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ai_insights_owner" ON public.ai_insights
  FOR ALL USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);

CREATE INDEX IF NOT EXISTS idx_ai_insights_user_type
  ON public.ai_insights(user_id, analysis_type, created_at DESC);

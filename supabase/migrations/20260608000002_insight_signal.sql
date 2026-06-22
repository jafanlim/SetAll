-- setall-insight-self-improvement Stage 1: insight_signal table + RLS
-- ---------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.insight_signal (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id      UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  session_id   TEXT NOT NULL,
  message_id   TEXT NOT NULL,
  signal_type  TEXT NOT NULL,  -- 'shown' | 'dismissed' | 'expanded' | 'followup'
  -- optional context carried by the signal
  extra        JSONB,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.insight_signal ENABLE ROW LEVEL SECURITY;

CREATE POLICY "insight_signal_select" ON public.insight_signal
  FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "insight_signal_insert" ON public.insight_signal
  FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "insight_signal_update" ON public.insight_signal
  FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "insight_signal_delete" ON public.insight_signal
  FOR DELETE USING (auth.uid() = user_id);

-- Index for per-session analytics queries
CREATE INDEX IF NOT EXISTS insight_signal_session
  ON public.insight_signal(user_id, session_id, signal_type);

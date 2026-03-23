-- BACKLOG-02: Bug reports table
CREATE TABLE IF NOT EXISTS public.bug_reports (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid        REFERENCES auth.users(id),
  description text        NOT NULL,
  expected    text,
  severity    text        NOT NULL DEFAULT 'medium',
  device_info text,
  logs        text,
  app_version text,
  created_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.bug_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_insert_own" ON public.bug_reports
  FOR INSERT WITH CHECK (auth.uid() = user_id);

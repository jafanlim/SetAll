-- FEAT-P46: Add AI triage columns to bug_reports
-- Requires pg_net for the trigger HTTP call in the next migration.

CREATE EXTENSION IF NOT EXISTS pg_net;

ALTER TABLE public.bug_reports
  ADD COLUMN IF NOT EXISTS triage_summary  text,
  ADD COLUMN IF NOT EXISTS triage_severity text
    CHECK (triage_severity IN ('critical','high','medium','low','info')),
  ADD COLUMN IF NOT EXISTS triage_area     text,
  ADD COLUMN IF NOT EXISTS cascade_prompt  text,
  ADD COLUMN IF NOT EXISTS triaged_at      timestamptz,
  ADD COLUMN IF NOT EXISTS triage_model    text
    DEFAULT 'llama-3.3-70b-versatile';

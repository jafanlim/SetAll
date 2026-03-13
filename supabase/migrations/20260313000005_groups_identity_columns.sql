-- ============================================================
-- Migration: add identity columns to groups table
-- icon_name, color_value, type, avatar_url were stored only
-- locally; this migration persists them in Supabase so they
-- survive cloud sync without being wiped.
-- ============================================================

ALTER TABLE public.groups
  ADD COLUMN IF NOT EXISTS type        text    NOT NULL DEFAULT 'normal',
  ADD COLUMN IF NOT EXISTS icon_name   text,
  ADD COLUMN IF NOT EXISTS color_value bigint,
  ADD COLUMN IF NOT EXISTS avatar_url  text;

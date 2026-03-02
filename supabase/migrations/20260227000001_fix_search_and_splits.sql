-- =============================================================================
-- SetAll: Fix search_profiles (email search) + splits column rename
-- Run in Supabase SQL Editor: Dashboard → SQL Editor → New query → Run
-- Safe to re-run.
-- =============================================================================

-- ── 1. Rename splits.amount_owed → universal_usd_owed (if not already done) ──
--    Migration 20260220110135 renames this column, but any DB set up from
--    run_in_sql_editor.sql still has the old name, causing balance to read zero.
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'splits'
      AND column_name  = 'amount_owed'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'splits'
      AND column_name  = 'universal_usd_owed'
  ) THEN
    ALTER TABLE public.splits RENAME COLUMN amount_owed TO universal_usd_owed;
  END IF;
END $$;

-- ── 2. Replace search_profiles with email-aware version ──────────────────────
--    Previous version omitted the auth.users JOIN so email queries always
--    returned zero results. SECURITY DEFINER allows reading auth.users.email.
DROP FUNCTION IF EXISTS public.search_profiles(TEXT);
CREATE OR REPLACE FUNCTION public.search_profiles(p_query TEXT)
RETURNS TABLE (
  id               UUID,
  name             TEXT,
  nickname         TEXT,
  avatar_url       TEXT,
  default_currency TEXT,
  is_ghost         BOOLEAN
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    p.id,
    p.name,
    p.nickname,
    p.avatar_url,
    p.default_currency,
    p.is_ghost
  FROM   public.profiles p
  JOIN   auth.users u ON u.id = p.id
  WHERE  p.is_ghost = FALSE
    AND  p.id <> auth.uid()
    AND (
      p.name     ILIKE '%' || p_query || '%'
      OR p.nickname ILIKE '%' || p_query || '%'
      OR p.nickname ILIKE '%' || REPLACE(p_query, '@', '') || '%'
      OR u.email    ILIKE '%' || p_query || '%'
    )
  ORDER BY
    CASE
      WHEN lower(u.email)    = lower(p_query)                          THEN 0
      WHEN lower(p.nickname) = lower(REPLACE(p_query, '@', ''))        THEN 1
      WHEN p.nickname ILIKE p_query
        OR p.nickname ILIKE REPLACE(p_query, '@', '')                  THEN 2
      ELSE 3
    END,
    p.name
  LIMIT 20;
END;
$$;

GRANT EXECUTE ON FUNCTION public.search_profiles(TEXT) TO authenticated;

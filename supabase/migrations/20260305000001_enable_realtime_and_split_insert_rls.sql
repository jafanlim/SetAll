-- =============================================================================
-- SetAll: Enable Supabase Realtime for sync-critical tables.
--
-- Two things are required for onPostgresChanges() to fire:
--   1. The table must be in the supabase_realtime logical replication
--      publication.
--   2. The table must have REPLICA IDENTITY FULL so the WAL record contains
--      the full row, not just the PK.  Without FULL, DELETE events carry no
--      usable data and UPDATE events may be suppressed.
--
-- Safe to re-run (all statements are idempotent).
-- =============================================================================

-- ── 1. REPLICA IDENTITY FULL ─────────────────────────────────────────────────
--    Must be set before adding to the publication or Realtime events will be
--    incomplete / silently dropped.
ALTER TABLE public.groups        REPLICA IDENTITY FULL;
ALTER TABLE public.group_members REPLICA IDENTITY FULL;
ALTER TABLE public.expenses      REPLICA IDENTITY FULL;
ALTER TABLE public.splits        REPLICA IDENTITY FULL;

-- ── 2. Add tables to the Realtime publication ─────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'groups'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.groups;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'group_members'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.group_members;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'expenses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.expenses;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'splits'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.splits;
  END IF;
END $$;

-- ── 3. Notify PostgREST to reload its schema cache ───────────────────────────
NOTIFY pgrst, 'reload schema';

-- =============================================================================
-- SetAll: Enable Realtime publication + ensure splits INSERT is open to all
--         group members (not just the expense payer).
--
-- Context:
--   • fix/cloud-reactivity-realtime subscribes to Postgres changes via
--     supabase.channel('setall-sync').onPostgresChanges(...).
--     Realtime events are ONLY emitted for tables that are members of the
--     supabase_realtime publication.  Without this the websocket channel
--     subscribes successfully but never fires any callbacks.
--
--   • The previous splits INSERT policy (20260302000003) uses FOR ALL which
--     covers INSERT via WITH CHECK.  This migration is a no-op for splits RLS
--     but documents the intent clearly.
--
-- Safe to re-run (all statements are idempotent).
-- =============================================================================

-- ── 1. Add tables to the Realtime publication ─────────────────────────────────
--    supabase_realtime is the default logical replication publication created
--    by the Supabase platform.  Adding tables here enables row-level change
--    events for all subscribed clients.
DO $$
BEGIN
  -- groups
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'groups'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.groups;
  END IF;

  -- group_members
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'group_members'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.group_members;
  END IF;

  -- expenses
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'expenses'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.expenses;
  END IF;

  -- splits
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND tablename = 'splits'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.splits;
  END IF;
END $$;

-- ── 2. Notify PostgREST to reload its schema cache ───────────────────────────
--    Required after any DDL change so PostgREST picks up the publication list.
NOTIFY pgrst, 'reload schema';

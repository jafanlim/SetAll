-- =============================================================================
-- wallet_entries Supabase parity — close gaps vs expenses table.
--
-- GAP ANALYSIS (from migration history audit):
--   MISSING: separate SELECT/INSERT/UPDATE/DELETE RLS policies
--            (current blanket FOR ALL has no deleted_at IS NULL filter on SELECT)
--   MISSING: supabase_realtime publication membership
--            (realtime subscriptions in sync_service.dart fire nothing without this)
--   MISSING: idx_wallet_entries_user_id          (point lookup by user)
--   MISSING: idx_wallet_entries_deleted_at        (partial — active rows only)
--   MISSING: idx_wallet_entries_updated_at        (sync pull ordered by updated_at)
--
--   PRESENT (no action needed):
--     REPLICA IDENTITY FULL, updated_at trigger, idx_wallet_entries_user_created,
--     FK user_id → auth.users, RLS enabled.
--
-- Safe to re-run: all statements are idempotent.
-- =============================================================================

-- ── RLS policies: drop blanket policy, recreate as four granular ones ─────────

DROP POLICY IF EXISTS "wallet_entries_owner"        ON public.wallet_entries;
DROP POLICY IF EXISTS "wallet_entries_select_owner" ON public.wallet_entries;
DROP POLICY IF EXISTS "wallet_entries_insert_owner" ON public.wallet_entries;
DROP POLICY IF EXISTS "wallet_entries_update_owner" ON public.wallet_entries;
DROP POLICY IF EXISTS "wallet_entries_delete_owner" ON public.wallet_entries;

-- SELECT: owner reads own non-deleted rows
CREATE POLICY "wallet_entries_select_owner"
  ON public.wallet_entries FOR SELECT
  USING (auth.uid() = user_id AND deleted_at IS NULL);

-- INSERT: owner inserts own rows
CREATE POLICY "wallet_entries_insert_owner"
  ON public.wallet_entries FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- UPDATE: owner updates own rows (upsert UPDATE path requires WITH CHECK)
CREATE POLICY "wallet_entries_update_owner"
  ON public.wallet_entries FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- DELETE: owner hard-deletes own rows (soft delete is handled in the app)
CREATE POLICY "wallet_entries_delete_owner"
  ON public.wallet_entries FOR DELETE
  USING (auth.uid() = user_id);

-- ── Realtime publication ───────────────────────────────────────────────────────

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND tablename = 'wallet_entries'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.wallet_entries;
  END IF;
END $$;

-- ── Missing indexes ────────────────────────────────────────────────────────────

-- Point lookup: find all entries for a user (used by getWalletEntries WHERE)
CREATE INDEX IF NOT EXISTS idx_wallet_entries_user_id
  ON public.wallet_entries(user_id);

-- Partial index: active (non-deleted) rows only — covers the common query path
CREATE INDEX IF NOT EXISTS idx_wallet_entries_deleted_at
  ON public.wallet_entries(deleted_at)
  WHERE deleted_at IS NULL;

-- Sync pull order: SyncService pulls rows WHERE updated_at > last_sync_time
CREATE INDEX IF NOT EXISTS idx_wallet_entries_updated_at
  ON public.wallet_entries(updated_at DESC);

-- ── Comment ───────────────────────────────────────────────────────────────────

COMMENT ON TABLE public.wallet_entries IS
  'Personal wallet entries — separated from group expenses in SCHEMA-01. '
  'Fully isolated per user via RLS. Realtime enabled for cross-device sync.';

-- ── Notify PostgREST to reload schema cache ───────────────────────────────────

NOTIFY pgrst, 'reload schema';

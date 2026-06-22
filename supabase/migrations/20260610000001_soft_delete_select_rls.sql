-- =============================================================================
-- Allow payers to READ their own soft-deleted expenses so the activity feed
-- can show tombstones (restorable deletion events).
--
-- Existing SELECT policies both require deleted_at IS NULL, making soft-deleted
-- rows completely invisible. This additive policy fills that gap.
-- =============================================================================

CREATE POLICY "Payer can read own soft-deleted expenses"
  ON public.expenses FOR SELECT
  USING (payer_id = auth.uid() AND deleted_at IS NOT NULL);

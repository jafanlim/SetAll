-- =============================================================================
-- SetAll: Ensure groups INSERT policy exists
-- Safe to re-run.
--
-- The "Authenticated users can create groups" INSERT policy may have been
-- silently dropped by earlier migration runs. This restores it.
-- =============================================================================

DROP POLICY IF EXISTS "Authenticated users can create groups" ON public.groups;
CREATE POLICY "Authenticated users can create groups"
  ON public.groups FOR INSERT
  WITH CHECK (auth.uid() = creator_id);

-- =============================================================================
-- SetAll: Fix ghost-row FK violation on pending_invites (TASK 7 / Part A)
--
-- Root cause: run_in_sql_editor.sql defines pending_invites.ghost_id with a FK
--   REFERENCES public.profiles(id) ON DELETE SET NULL (no ON UPDATE clause,
--   defaults to NO ACTION). When handle_new_user later tries to UPDATE the ghost
--   profile's PK to claim it for a real signup, the FK constraint blocks it.
--
-- Fix: Drop the FK constraint on the ghost column if it exists.
--   The migration schema (20260219000001) never had this FK — it uses
--   ghost_user_id with no REFERENCES clause, and the claiming flow DELETEs
--   the ghost profile + invite rather than updating the PK.
--
-- Safe to re-run. All DDL is guarded in PL/pgSQL blocks.
-- =============================================================================

-- ── 1. Drop FK on ghost_id if the column + constraint exist ────────────────────
--    The run_in_sql_editor.sql table uses column "ghost_id" with FK.
--    The migration table uses "ghost_user_id" with no FK. Handle both.
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'pending_invites'
      AND column_name = 'ghost_id'
  ) THEN
    ALTER TABLE public.pending_invites
      DROP CONSTRAINT IF EXISTS pending_invites_ghost_id_fkey;
  END IF;
END $$;

DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'pending_invites'
      AND column_name = 'ghost_user_id'
  ) THEN
    ALTER TABLE public.pending_invites
      DROP CONSTRAINT IF EXISTS pending_invites_ghost_user_id_fkey;
  END IF;
END $$;

-- ── 2. Ensure add_ghost_member is the safe (migration) version ─────────────────
--    Does NOT set nickname on ghost profiles (avoids unique-index conflict).
--    Does NOT reference any FK column on pending_invites.
--    Uses invited_email / ghost_user_id (migration column names).
CREATE OR REPLACE FUNCTION public.add_ghost_member(
  p_group_id    UUID,
  p_email       TEXT,
  p_invited_by  UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ghost_id UUID;
BEGIN
  -- Check if invite already exists for this group+email
  SELECT ghost_user_id INTO v_ghost_id
    FROM public.pending_invites
    WHERE group_id = p_group_id
      AND lower(invited_email) = lower(p_email)
    LIMIT 1;

  IF v_ghost_id IS NOT NULL THEN
    RETURN v_ghost_id;  -- Idempotent
  END IF;

  v_ghost_id := gen_random_uuid();

  -- Create ghost profile (no auth.users FK — ghost profiles use the service-role policy)
  INSERT INTO public.profiles (id, name, is_ghost, default_currency)
    VALUES (v_ghost_id, p_email, TRUE, 'USD')
    ON CONFLICT (id) DO NOTHING;

  -- Add ghost to group_members
  INSERT INTO public.group_members (group_id, user_id, joined_at)
    VALUES (p_group_id, v_ghost_id, now())
    ON CONFLICT DO NOTHING;

  -- Record the pending invite (no FK on ghost_user_id column)
  INSERT INTO public.pending_invites (group_id, invited_email, ghost_user_id, invited_by)
    VALUES (p_group_id, lower(p_email), v_ghost_id, p_invited_by);

  RETURN v_ghost_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.add_ghost_member(UUID, TEXT, UUID) TO authenticated;

-- =============================================================================
-- SetAll: Fix OAuth "Database error saving new user" + Ghost nickname conflict
-- Run in Supabase SQL Editor.  Safe to re-run.
--
-- Root causes addressed:
--   1. handle_new_user fires AFTER on_auth_user_claim_ghost, which already
--      deleted the ghost row.  The INSERT therefore never conflicts on id,
--      but it CAN conflict on the profiles_nickname_unique index if the ghost
--      had a nickname.  Add an explicit ON CONFLICT on that constraint.
--   2. claim_ghost_account only matches ghosts via pending_invites, missing
--      "orphan" ghost profiles whose name = new user's email (created directly
--      via add_ghost_member in older schema versions).  The orphan is left
--      intact, then handle_new_user hits the nickname unique index → crash.
--   3. handle_new_user ghost-lookup searches nickname = NEW.email, but
--      add_ghost_member (run_in_sql_editor version) stores email in nickname
--      while the migration version stores it in name.  Unify the lookup to
--      check both columns.
-- =============================================================================

-- ── 1. Harden claim_ghost_account ────────────────────────────────────────────
--    After processing all pending_invites, also sweep for any orphan ghost
--    profile whose name OR nickname equals the new user's email.
CREATE OR REPLACE FUNCTION public.claim_ghost_account()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invite   RECORD;
  v_orphan   RECORD;
BEGIN
  -- ── Pass 1: claim via pending_invites (canonical path) ──────────────────
  FOR v_invite IN
    SELECT * FROM public.pending_invites
    WHERE lower(invited_email) = lower(NEW.email)
  LOOP
    UPDATE public.splits
      SET user_id = NEW.id
      WHERE user_id = v_invite.ghost_user_id;

    UPDATE public.group_members
      SET user_id = NEW.id
      WHERE user_id = v_invite.ghost_user_id;

    UPDATE public.expenses
      SET payer_id = NEW.id
      WHERE payer_id = v_invite.ghost_user_id;

    DELETE FROM public.profiles WHERE id = v_invite.ghost_user_id;
    DELETE FROM public.pending_invites WHERE id = v_invite.id;
  END LOOP;

  -- ── Pass 2: sweep orphan ghosts (name or nickname = email, no invite row) ─
  FOR v_orphan IN
    SELECT id FROM public.profiles
    WHERE  is_ghost = TRUE
      AND  id NOT IN (SELECT ghost_user_id FROM public.pending_invites)
      AND  (
        lower(name)     = lower(NEW.email)
        OR lower(nickname) = lower(NEW.email)
      )
  LOOP
    UPDATE public.splits     SET user_id  = NEW.id WHERE user_id  = v_orphan.id;
    UPDATE public.group_members SET user_id = NEW.id WHERE user_id  = v_orphan.id;
    UPDATE public.expenses   SET payer_id = NEW.id WHERE payer_id = v_orphan.id;
    DELETE FROM public.profiles WHERE id = v_orphan.id;
  END LOOP;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_claim_ghost ON auth.users;
CREATE TRIGGER on_auth_user_claim_ghost
  BEFORE INSERT ON auth.users   -- BEFORE so ghost rows are gone before handle_new_user fires
  FOR EACH ROW EXECUTE FUNCTION public.claim_ghost_account();


-- ── 2. Harden handle_new_user ─────────────────────────────────────────────────
--    • ON CONFLICT (id)               → promote any surviving ghost row
--    • ON CONFLICT ON CONSTRAINT profiles_nickname_unique → clear the stale
--      nickname so the new real user's row can be inserted cleanly
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_name     TEXT;
  v_nickname TEXT;
BEGIN
  v_name     := COALESCE(NEW.raw_user_meta_data->>'name',
                          SPLIT_PART(NEW.email, '@', 1),
                          'User');
  v_nickname := COALESCE(NEW.raw_user_meta_data->>'nickname', NULL);

  -- Step A: if a ghost profile still exists with this email as nickname,
  -- clear that nickname now so Step B's INSERT cannot conflict on the index.
  UPDATE public.profiles
    SET  nickname = NULL
    WHERE is_ghost = TRUE
      AND lower(nickname) = lower(NEW.email)
      AND id <> NEW.id;

  -- Step B: upsert the real profile row.
  INSERT INTO public.profiles (id, name, nickname, default_currency, is_ghost)
  VALUES (NEW.id, v_name, v_nickname, 'USD', FALSE)
  ON CONFLICT (id) DO UPDATE
    SET name       = EXCLUDED.name,
        nickname   = COALESCE(profiles.nickname, EXCLUDED.nickname),
        is_ghost   = FALSE,
        updated_at = now();

  RETURN NEW;
END;
$$;

-- The trigger already exists from migration 20250217000000; just refresh it.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ── 3. Enforce case-insensitive nickname uniqueness consistently ──────────────
--    run_in_sql_editor.sql created a case-SENSITIVE index; migration created a
--    case-INSENSITIVE one.  Drop both variants and recreate the correct one.
DROP INDEX IF EXISTS public.profiles_nickname_unique;
CREATE UNIQUE INDEX IF NOT EXISTS profiles_nickname_unique
  ON public.profiles (lower(nickname))
  WHERE nickname IS NOT NULL;

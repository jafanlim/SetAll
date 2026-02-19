-- ============================================================
-- SetAll: Nickname, Ghost Users & Pending Invites
-- Run in Supabase SQL Editor (Dashboard → SQL Editor → New query)
-- ============================================================

-- 1. Add nickname and avatar_url to profiles
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS nickname TEXT,
  ADD COLUMN IF NOT EXISTS avatar_url TEXT,
  ADD COLUMN IF NOT EXISTS is_ghost BOOLEAN NOT NULL DEFAULT FALSE;

-- Unique index on nickname (case-insensitive), ignoring NULLs
CREATE UNIQUE INDEX IF NOT EXISTS profiles_nickname_unique
  ON public.profiles (lower(nickname))
  WHERE nickname IS NOT NULL;

-- 2. Remove the FK from profiles.id so ghost rows can exist without auth.users entries.
--    The original migration defined: id uuid primary key references auth.users(id) on delete cascade
--    Ghost users need a UUID in profiles that has NO corresponding auth.users row.
--    We keep the PK, just drop the FK constraint.
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND table_name = 'profiles'
      AND constraint_type = 'FOREIGN KEY'
  ) THEN
    -- The constraint name is usually profiles_id_fkey; drop it safely.
    ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_id_fkey;
  END IF;
END $$;

-- Allow service-role to insert ghost profiles (app uses anon key; ghost insert happens server-side)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles'
      AND policyname = 'Service role can insert ghost profiles'
  ) THEN
    CREATE POLICY "Service role can insert ghost profiles"
      ON public.profiles FOR INSERT
      TO service_role
      WITH CHECK (true);
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles'
      AND policyname = 'Service role can update profiles'
  ) THEN
    CREATE POLICY "Service role can update profiles"
      ON public.profiles FOR UPDATE
      TO service_role
      USING (true);
  END IF;
END $$;

-- 3. pending_invites table
CREATE TABLE IF NOT EXISTS public.pending_invites (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id      UUID NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  invited_email TEXT NOT NULL,
  ghost_user_id UUID NOT NULL,          -- synthetic UUID used in splits/group_members
  invited_by    UUID REFERENCES public.profiles(id),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS pending_invites_email_idx ON public.pending_invites (lower(invited_email));
CREATE INDEX IF NOT EXISTS pending_invites_ghost_idx  ON public.pending_invites (ghost_user_id);

-- RLS on pending_invites
ALTER TABLE public.pending_invites ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'pending_invites'
      AND policyname = 'Members can read pending invites for their groups'
  ) THEN
    CREATE POLICY "Members can read pending invites for their groups"
      ON public.pending_invites FOR SELECT
      USING (
        EXISTS (
          SELECT 1 FROM public.group_members
          WHERE group_members.group_id = pending_invites.group_id
            AND group_members.user_id  = auth.uid()
        )
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'pending_invites'
      AND policyname = 'Group creator can insert pending invites'
  ) THEN
    CREATE POLICY "Group creator can insert pending invites"
      ON public.pending_invites FOR INSERT
      WITH CHECK (
        EXISTS (
          SELECT 1 FROM public.groups
          WHERE groups.id         = pending_invites.group_id
            AND groups.creator_id = auth.uid()
        )
      );
  END IF;
END $$;

-- 4. Ghost-claiming function
--    Triggered AFTER a new auth.users row is inserted.
--    Replaces ghost_user_id → real uid in all affected rows.
CREATE OR REPLACE FUNCTION public.claim_ghost_account()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_invite RECORD;
BEGIN
  -- Find any pending invites whose email matches the new user's email
  FOR v_invite IN
    SELECT * FROM public.pending_invites
    WHERE lower(invited_email) = lower(NEW.email)
  LOOP
    -- Replace ghost user in splits
    UPDATE public.splits
      SET user_id = NEW.id
      WHERE user_id = v_invite.ghost_user_id;

    -- Replace ghost user in group_members
    UPDATE public.group_members
      SET user_id = NEW.id
      WHERE user_id = v_invite.ghost_user_id;

    -- Replace ghost payer in expenses (rare but possible)
    UPDATE public.expenses
      SET payer_id = NEW.id
      WHERE payer_id = v_invite.ghost_user_id;

    -- Merge ghost profile into real profile (will be upserted by handle_new_user)
    DELETE FROM public.profiles WHERE id = v_invite.ghost_user_id;

    -- Remove the pending invite
    DELETE FROM public.pending_invites WHERE id = v_invite.id;
  END LOOP;

  RETURN NEW;
END;
$$;

-- Attach the claiming trigger to auth.users
DROP TRIGGER IF EXISTS on_auth_user_claim_ghost ON auth.users;
CREATE TRIGGER on_auth_user_claim_ghost
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.claim_ghost_account();

-- 5. RPC: search profiles by email or nickname (used by Add Person modal)
CREATE OR REPLACE FUNCTION public.search_profiles(p_query TEXT)
RETURNS TABLE (
  id               UUID,
  name             TEXT,
  nickname         TEXT,
  avatar_url       TEXT,
  default_currency TEXT,
  is_ghost         BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    p.id,
    p.name,
    p.nickname,
    p.avatar_url,
    p.default_currency,
    p.is_ghost
  FROM public.profiles p
  JOIN auth.users u ON u.id = p.id
  WHERE
    p.is_ghost = FALSE
    AND (
      lower(u.email)    ILIKE '%' || lower(p_query) || '%'
      OR lower(p.nickname) ILIKE '%' || lower(p_query) || '%'
      OR lower(p.name)     ILIKE '%' || lower(p_query) || '%'
    )
  LIMIT 20;
$$;

-- 6. RPC: create ghost member for a group
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

  -- Create ghost profile (no auth.users FK — ghost profiles use the service-role policy above)
  INSERT INTO public.profiles (id, name, is_ghost, default_currency)
    VALUES (v_ghost_id, p_email, TRUE, 'USD')
    ON CONFLICT (id) DO NOTHING;

  -- Add ghost to group_members
  INSERT INTO public.group_members (group_id, user_id, joined_at)
    VALUES (p_group_id, v_ghost_id, now())
    ON CONFLICT DO NOTHING;

  -- Record the pending invite
  INSERT INTO public.pending_invites (group_id, invited_email, ghost_user_id, invited_by)
    VALUES (p_group_id, lower(p_email), v_ghost_id, p_invited_by);

  RETURN v_ghost_id;
END;
$$;

-- 7. Update handle_new_user trigger to include nickname = NULL by default
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, name, nickname, default_currency)
  VALUES (
    NEW.id,
    coalesce(NEW.raw_user_meta_data->>'name', split_part(NEW.email, '@', 1)),
    NULL,
    'USD'
  )
  ON CONFLICT (id) DO UPDATE
    SET name = EXCLUDED.name,
        is_ghost = FALSE;  -- Real signup promotes any ghost row
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Note: The trigger on_auth_user_created already exists from migration 20250217000001.
-- The CREATE OR REPLACE above updates the function body. No need to recreate the trigger.

COMMENT ON TABLE  public.pending_invites IS 'Ghost invite emails awaiting account claim';
COMMENT ON COLUMN public.profiles.nickname  IS 'Optional @handle, unique, case-insensitive';
COMMENT ON COLUMN public.profiles.is_ghost  IS 'TRUE for synthetic ghost users before signup';

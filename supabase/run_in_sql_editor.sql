-- =============================================================================
-- SetAll: Complete Supabase schema — run this in SQL Editor
-- Dashboard → SQL Editor → New query → paste → Run
-- Safe to re-run: every statement is idempotent.
-- =============================================================================


-- ─────────────────────────────────────────────────────────────────────────────
-- 1. PROFILES
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id               UUID        PRIMARY KEY,
  name             TEXT        NOT NULL DEFAULT '',
  nickname         TEXT,
  avatar_url       TEXT,
  is_ghost         BOOLEAN     NOT NULL DEFAULT FALSE,
  default_currency TEXT        NOT NULL DEFAULT 'USD',
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Add new columns if the table already existed from an older schema.
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS nickname         TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_url       TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS is_ghost         BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS default_currency TEXT    NOT NULL DEFAULT 'USD';

-- Unique index on nickname for @handle look-ups (null values are excluded).
CREATE UNIQUE INDEX IF NOT EXISTS profiles_nickname_unique
  ON public.profiles (nickname)
  WHERE nickname IS NOT NULL;

-- Drop the FK to auth.users so ghost profiles (no auth account) can be inserted.
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND table_name        = 'profiles'
      AND constraint_type   = 'FOREIGN KEY'
      AND constraint_name   = 'profiles_id_fkey'
  ) THEN
    ALTER TABLE public.profiles DROP CONSTRAINT profiles_id_fkey;
  END IF;
END $$;

ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND policyname='Users can read all profiles') THEN
    CREATE POLICY "Users can read all profiles" ON public.profiles FOR SELECT USING (true);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND policyname='Users can update own profile') THEN
    CREATE POLICY "Users can update own profile" ON public.profiles FOR UPDATE USING (auth.uid() = id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND policyname='Users can insert own profile') THEN
    CREATE POLICY "Users can insert own profile" ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);
  END IF;
END $$;
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='profiles' AND policyname='Service role can insert ghost profiles') THEN
    CREATE POLICY "Service role can insert ghost profiles" ON public.profiles FOR INSERT TO service_role WITH CHECK (true);
  END IF;
END $$;

-- Trigger: create a profile row for every new auth user; also claims ghost.
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ghost_id UUID;
BEGIN
  -- Check for a ghost profile with the same email and promote it.
  SELECT id INTO v_ghost_id
  FROM   public.profiles
  WHERE  nickname = NEW.email AND is_ghost = TRUE
  LIMIT  1;

  IF v_ghost_id IS NOT NULL THEN
    UPDATE public.profiles
    SET    id         = NEW.id,
           name       = COALESCE(NEW.raw_user_meta_data->>'name', 'User'),
           nickname   = COALESCE(NEW.raw_user_meta_data->>'nickname', NULL),
           is_ghost   = FALSE,
           updated_at = now()
    WHERE  id = v_ghost_id;
  ELSE
    INSERT INTO public.profiles (id, name, nickname)
    VALUES (
      NEW.id,
      COALESCE(NEW.raw_user_meta_data->>'name', 'User'),
      COALESCE(NEW.raw_user_meta_data->>'nickname', NULL)
    )
    ON CONFLICT (id) DO UPDATE
      SET name     = EXCLUDED.name,
          nickname = EXCLUDED.nickname;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ─────────────────────────────────────────────────────────────────────────────
-- 2. GROUPS & GROUP_MEMBERS
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.groups (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  name       TEXT        NOT NULL,
  creator_id UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  type       TEXT        NOT NULL DEFAULT 'normal',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.groups ADD COLUMN IF NOT EXISTS type TEXT NOT NULL DEFAULT 'normal';

CREATE INDEX IF NOT EXISTS idx_groups_creator_id ON public.groups(creator_id);
ALTER TABLE public.groups ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.group_members (
  group_id  UUID        NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  user_id   UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  joined_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (group_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_group_members_user_id ON public.group_members(user_id);
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='groups' AND policyname='Users can read groups they belong to') THEN
  CREATE POLICY "Users can read groups they belong to" ON public.groups FOR SELECT
    USING (id IN (SELECT group_id FROM public.group_members WHERE user_id = auth.uid()) OR creator_id = auth.uid());
END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='groups' AND policyname='Authenticated users can create groups') THEN
  CREATE POLICY "Authenticated users can create groups" ON public.groups FOR INSERT WITH CHECK (auth.uid() = creator_id);
END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='groups' AND policyname='Creator can update group') THEN
  CREATE POLICY "Creator can update group" ON public.groups FOR UPDATE USING (creator_id = auth.uid());
END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='groups' AND policyname='Creator can delete group') THEN
  CREATE POLICY "Creator can delete group" ON public.groups FOR DELETE USING (creator_id = auth.uid());
END IF; END $$;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='group_members' AND policyname='Members can read group_members') THEN
  -- get_my_groups() is SECURITY DEFINER so it bypasses RLS when querying
  -- group_members, breaking the recursion cycle. Do NOT use a plain subquery
  -- against group_members here — that causes infinite recursion (42P17).
  CREATE POLICY "Members can read group_members" ON public.group_members FOR SELECT
    USING (user_id = auth.uid()
        OR group_id IN (SELECT public.get_my_groups()));
END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='group_members' AND policyname='Group creator can manage members') THEN
  CREATE POLICY "Group creator can manage members" ON public.group_members FOR ALL
    USING (group_id IN (SELECT id FROM public.groups WHERE creator_id = auth.uid()));
END IF; END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3. EXPENSES & SPLITS
-- ─────────────────────────────────────────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE public.split_type AS ENUM ('even', 'manual', 'parts');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

CREATE TABLE IF NOT EXISTS public.expenses (
  id                    UUID                NOT NULL DEFAULT gen_random_uuid(),
  group_id              UUID                NOT NULL REFERENCES public.groups(id)   ON DELETE CASCADE,
  payer_id              UUID                NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  amount                NUMERIC(14,4)       NOT NULL CHECK (amount >= 0),
  description           TEXT                NOT NULL DEFAULT '',
  currency              TEXT                NOT NULL DEFAULT 'USD',
  split_type            public.split_type   NOT NULL DEFAULT 'even',
  category              TEXT                DEFAULT 'General',
  original_amount       NUMERIC(14,4),
  original_currency     TEXT,
  exchange_rate_applied NUMERIC(14,6),
  base_amount_at_entry  NUMERIC(14,4),
  created_at            TIMESTAMPTZ         NOT NULL DEFAULT now(),
  updated_at            TIMESTAMPTZ         NOT NULL DEFAULT now(),
  PRIMARY KEY (id)
);
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS category              TEXT          DEFAULT 'General';
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS original_amount       NUMERIC(14,4);
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS original_currency     TEXT;
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS exchange_rate_applied NUMERIC(14,6);
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS base_amount_at_entry  NUMERIC(14,4);

CREATE INDEX IF NOT EXISTS idx_expenses_group_id   ON public.expenses(group_id);
CREATE INDEX IF NOT EXISTS idx_expenses_payer_id   ON public.expenses(payer_id);
CREATE INDEX IF NOT EXISTS idx_expenses_created_at ON public.expenses(created_at DESC);
ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='expenses' AND policyname='Group members can read expenses') THEN
  CREATE POLICY "Group members can read expenses" ON public.expenses FOR SELECT
    USING (group_id IN (SELECT group_id FROM public.group_members WHERE user_id = auth.uid())
        OR group_id IN (SELECT id FROM public.groups WHERE creator_id = auth.uid()));
END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='expenses' AND policyname='Group members can insert expenses') THEN
  CREATE POLICY "Group members can insert expenses" ON public.expenses FOR INSERT
    WITH CHECK (auth.uid() = payer_id AND (
      group_id IN (SELECT group_id FROM public.group_members WHERE user_id = auth.uid())
      OR group_id IN (SELECT id FROM public.groups WHERE creator_id = auth.uid())));
END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='expenses' AND policyname='Payer or group creator can update expense') THEN
  CREATE POLICY "Payer or group creator can update expense" ON public.expenses FOR UPDATE
    USING (payer_id = auth.uid() OR group_id IN (SELECT id FROM public.groups WHERE creator_id = auth.uid()));
END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='expenses' AND policyname='Payer or group creator can delete expense') THEN
  CREATE POLICY "Payer or group creator can delete expense" ON public.expenses FOR DELETE
    USING (payer_id = auth.uid() OR group_id IN (SELECT id FROM public.groups WHERE creator_id = auth.uid()));
END IF; END $$;

CREATE TABLE IF NOT EXISTS public.splits (
  id                   UUID          NOT NULL DEFAULT gen_random_uuid(),
  expense_id           UUID          NOT NULL REFERENCES public.expenses(id) ON DELETE CASCADE,
  user_id              UUID          NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  universal_usd_owed   NUMERIC(14,4) NOT NULL DEFAULT 0 CHECK (universal_usd_owed >= 0),
  created_at           TIMESTAMPTZ   NOT NULL DEFAULT now(),
  PRIMARY KEY (id),
  UNIQUE (expense_id, user_id)
);
-- Rename legacy column if it still exists from a pre-migration schema setup
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'splits' AND column_name = 'amount_owed'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'splits' AND column_name = 'universal_usd_owed'
  ) THEN
    ALTER TABLE public.splits RENAME COLUMN amount_owed TO universal_usd_owed;
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_splits_expense_id ON public.splits(expense_id);
CREATE INDEX IF NOT EXISTS idx_splits_user_id    ON public.splits(user_id);
ALTER TABLE public.splits ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='splits' AND policyname='Group members can read splits for their group expenses') THEN
  CREATE POLICY "Group members can read splits for their group expenses" ON public.splits FOR SELECT
    USING (expense_id IN (SELECT e.id FROM public.expenses e
      WHERE e.group_id IN (SELECT group_id FROM public.group_members WHERE user_id = auth.uid())
         OR e.group_id IN (SELECT id FROM public.groups WHERE creator_id = auth.uid())));
END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='splits' AND policyname='Expense payer can manage splits') THEN
  CREATE POLICY "Expense payer can manage splits" ON public.splits FOR ALL
    USING (expense_id IN (SELECT id FROM public.expenses WHERE payer_id = auth.uid()));
END IF; END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4. EXCHANGE RATES
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.exchange_rates (
  base_currency   TEXT        NOT NULL,
  target_currency TEXT        NOT NULL,
  rate            NUMERIC(18,8) NOT NULL,
  last_updated    TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (base_currency, target_currency)
);
ALTER TABLE public.exchange_rates ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='exchange_rates' AND policyname='Anyone can read exchange rates') THEN
  CREATE POLICY "Anyone can read exchange rates" ON public.exchange_rates FOR SELECT USING (true);
END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='exchange_rates' AND policyname='Service role can manage exchange rates') THEN
  CREATE POLICY "Service role can manage exchange rates" ON public.exchange_rates FOR ALL TO service_role USING (true);
END IF; END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 5. PENDING INVITES (ghost accounts)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.pending_invites (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  email       TEXT        NOT NULL,
  group_id    UUID        NOT NULL REFERENCES public.groups(id) ON DELETE CASCADE,
  invited_by  UUID        NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  ghost_id    UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
ALTER TABLE public.pending_invites ENABLE ROW LEVEL SECURITY;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='pending_invites' AND policyname='Group members can read pending invites') THEN
  CREATE POLICY "Group members can read pending invites" ON public.pending_invites FOR SELECT
    USING (group_id IN (SELECT group_id FROM public.group_members WHERE user_id = auth.uid())
        OR group_id IN (SELECT id FROM public.groups WHERE creator_id = auth.uid()));
END IF; END $$;
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename='pending_invites' AND policyname='Group members can create invites') THEN
  CREATE POLICY "Group members can create invites" ON public.pending_invites FOR INSERT WITH CHECK (
    group_id IN (SELECT group_id FROM public.group_members WHERE user_id = auth.uid())
    OR group_id IN (SELECT id FROM public.groups WHERE creator_id = auth.uid()));
END IF; END $$;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6. STORAGE: avatars bucket
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('avatars', 'avatars', true, 5242880, '{image/jpeg,image/jpg,image/png,image/webp,image/gif}')
ON CONFLICT (id) DO UPDATE SET
  public             = true,
  file_size_limit    = 5242880,
  allowed_mime_types = '{image/jpeg,image/jpg,image/png,image/webp,image/gif}';

-- Drop and recreate storage policies cleanly.
DROP POLICY IF EXISTS "Avatar public read"                        ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users upload own avatar"     ON storage.objects;
DROP POLICY IF EXISTS "Users can update own avatar"               ON storage.objects;
DROP POLICY IF EXISTS "Users can delete own avatar"               ON storage.objects;
DROP POLICY IF EXISTS "Public avatar access"                      ON storage.objects;
DROP POLICY IF EXISTS "Authenticated avatar upload"               ON storage.objects;
DROP POLICY IF EXISTS "Authenticated avatar update"               ON storage.objects;
DROP POLICY IF EXISTS "Authenticated avatar delete"               ON storage.objects;

CREATE POLICY "Avatar public read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'avatars');

CREATE POLICY "Authenticated avatar upload"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (bucket_id = 'avatars');

CREATE POLICY "Authenticated avatar update"
  ON storage.objects FOR UPDATE
  TO authenticated
  USING (bucket_id = 'avatars');

CREATE POLICY "Authenticated avatar delete"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (bucket_id = 'avatars');


-- ─────────────────────────────────────────────────────────────────────────────
-- 7. RPCs
-- ─────────────────────────────────────────────────────────────────────────────

-- search_profiles: used by the add-member / add-friend search UI
-- Searches name, nickname, AND auth.users email (SECURITY DEFINER allows auth.users access)
DROP FUNCTION IF EXISTS public.search_profiles(TEXT);
CREATE OR REPLACE FUNCTION public.search_profiles(p_query TEXT)
RETURNS TABLE (id UUID, name TEXT, nickname TEXT, avatar_url TEXT, default_currency TEXT, is_ghost BOOLEAN)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT p.id, p.name, p.nickname, p.avatar_url, p.default_currency, p.is_ghost
  FROM   public.profiles p
  JOIN   auth.users u ON u.id = p.id
  WHERE  p.is_ghost = FALSE
    AND  p.id <> auth.uid()
    AND (
      p.name       ILIKE '%' || p_query || '%'
      OR p.nickname   ILIKE '%' || p_query || '%'
      OR p.nickname   ILIKE '%' || REPLACE(p_query, '@', '') || '%'
      OR u.email      ILIKE '%' || p_query || '%'
    )
  ORDER BY
    CASE
      WHEN lower(u.email)    = lower(p_query)                        THEN 0
      WHEN lower(p.nickname) = lower(REPLACE(p_query, '@', ''))      THEN 1
      WHEN p.nickname ILIKE p_query OR p.nickname ILIKE REPLACE(p_query,'@','') THEN 2
      ELSE 3
    END,
    p.name
  LIMIT 20;
END;
$$;
GRANT EXECUTE ON FUNCTION public.search_profiles(TEXT) TO authenticated;

-- add_member_by_id: SECURITY DEFINER so any group member can add people
DROP FUNCTION IF EXISTS public.add_member_by_id(UUID, UUID);
CREATE OR REPLACE FUNCTION public.add_member_by_id(p_group_id UUID, p_user_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.groups WHERE id = p_group_id AND creator_id = auth.uid())
     AND NOT EXISTS (SELECT 1 FROM public.group_members WHERE group_id = p_group_id AND user_id = auth.uid())
  THEN
    RAISE EXCEPTION 'You must be a member of this group to add people';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = p_user_id AND is_ghost = FALSE) THEN
    RAISE EXCEPTION 'User not found';
  END IF;
  INSERT INTO public.group_members (group_id, user_id)
  VALUES (p_group_id, p_user_id)
  ON CONFLICT (group_id, user_id) DO NOTHING;
END;
$$;
GRANT EXECUTE ON FUNCTION public.add_member_by_id(UUID, UUID) TO authenticated;

-- add_ghost_member: adds a placeholder for a non-registered user
DROP FUNCTION IF EXISTS public.add_ghost_member(UUID, TEXT, UUID);
CREATE OR REPLACE FUNCTION public.add_ghost_member(p_group_id UUID, p_email TEXT, p_invited_by UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_ghost_id UUID;
BEGIN
  SELECT id INTO v_ghost_id FROM public.profiles WHERE nickname = p_email AND is_ghost = TRUE LIMIT 1;
  IF v_ghost_id IS NULL THEN
    v_ghost_id := gen_random_uuid();
    INSERT INTO public.profiles (id, name, nickname, is_ghost)
    VALUES (v_ghost_id, SPLIT_PART(p_email,'@',1), p_email, TRUE);
  END IF;
  INSERT INTO public.group_members (group_id, user_id) VALUES (p_group_id, v_ghost_id) ON CONFLICT DO NOTHING;
  INSERT INTO public.pending_invites (email, group_id, invited_by, ghost_id) VALUES (p_email, p_group_id, p_invited_by, v_ghost_id) ON CONFLICT DO NOTHING;
  RETURN v_ghost_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.add_ghost_member(UUID, TEXT, UUID) TO authenticated;

-- create_direct_group_by_id: 1-on-1 friend group by user UUID
DROP FUNCTION IF EXISTS public.create_direct_group_by_id(UUID);
CREATE OR REPLACE FUNCTION public.create_direct_group_by_id(p_other_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_my_id    UUID := auth.uid();
  v_group_id UUID;
  v_name     TEXT;
BEGIN
  IF v_my_id IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  IF v_my_id = p_other_id THEN RAISE EXCEPTION 'cannot_add_self'; END IF;
  SELECT gm1.group_id INTO v_group_id
  FROM   public.group_members gm1
  JOIN   public.group_members gm2 ON gm1.group_id = gm2.group_id
  JOIN   public.groups g          ON g.id = gm1.group_id
  WHERE  gm1.user_id = v_my_id AND gm2.user_id = p_other_id AND g.type = 'direct'
  LIMIT  1;
  IF v_group_id IS NOT NULL THEN RETURN v_group_id; END IF;
  SELECT COALESCE(name, 'Friend') INTO v_name FROM public.profiles WHERE id = p_other_id;
  INSERT INTO public.groups (id, name, creator_id, type)
  VALUES (gen_random_uuid(), v_name, v_my_id, 'direct') RETURNING id INTO v_group_id;
  INSERT INTO public.group_members (group_id, user_id) VALUES (v_group_id, v_my_id), (v_group_id, p_other_id) ON CONFLICT DO NOTHING;
  RETURN v_group_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.create_direct_group_by_id(UUID) TO authenticated;

-- add_member_by_email: legacy helper
DROP FUNCTION IF EXISTS public.add_member_by_email(UUID, TEXT);
CREATE OR REPLACE FUNCTION public.add_member_by_email(p_group_id UUID, p_email TEXT)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_user_id UUID; BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.groups WHERE id = p_group_id AND creator_id = auth.uid()) THEN
    RAISE EXCEPTION 'Only the group creator can add members'; END IF;
  SELECT id INTO v_user_id FROM auth.users WHERE email = trim(lower(p_email)) LIMIT 1;
  IF v_user_id IS NULL THEN RAISE EXCEPTION 'user_not_found'; END IF;
  INSERT INTO public.group_members (group_id, user_id) VALUES (p_group_id, v_user_id) ON CONFLICT DO NOTHING;
END; $$;
GRANT EXECUTE ON FUNCTION public.add_member_by_email(UUID, TEXT) TO authenticated;

-- is_group_member: convenience helper
DROP FUNCTION IF EXISTS public.is_group_member(UUID);
CREATE OR REPLACE FUNCTION public.is_group_member(p_group_id UUID)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER STABLE SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.group_members WHERE group_id = p_group_id AND user_id = auth.uid())
      OR EXISTS (SELECT 1 FROM public.groups WHERE id = p_group_id AND creator_id = auth.uid());
$$;
GRANT EXECUTE ON FUNCTION public.is_group_member(UUID) TO authenticated;

-- =============================================================================
-- Done. All SetAll schema objects are now created / updated.
-- =============================================================================

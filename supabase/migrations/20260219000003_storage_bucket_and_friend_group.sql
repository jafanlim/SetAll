-- ============================================================
-- Migration 3: avatars storage bucket + create_direct_group_by_id RPC
-- ============================================================

-- ── 1. Storage: avatars bucket ────────────────────────────────────────────────
-- Create the bucket (public so avatar URLs work without signed tokens).
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'avatars',
  'avatars',
  true,
  2097152,          -- 2 MB max
  '{image/jpeg,image/png,image/webp,image/gif}'
)
ON CONFLICT (id) DO UPDATE SET
  public             = true,
  file_size_limit    = 2097152,
  allowed_mime_types = '{image/jpeg,image/png,image/webp,image/gif}';

-- RLS policies on storage.objects for the avatars bucket
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Avatar public read'
  ) THEN
    CREATE POLICY "Avatar public read"
      ON storage.objects FOR SELECT
      USING (bucket_id = 'avatars');
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Authenticated users upload own avatar'
  ) THEN
    CREATE POLICY "Authenticated users upload own avatar"
      ON storage.objects FOR INSERT
      TO authenticated
      WITH CHECK (
        bucket_id = 'avatars'
        AND (storage.foldername(name))[1] = 'avatars'
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Users can update own avatar'
  ) THEN
    CREATE POLICY "Users can update own avatar"
      ON storage.objects FOR UPDATE
      TO authenticated
      USING (
        bucket_id = 'avatars'
        AND owner = auth.uid()
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Users can delete own avatar'
  ) THEN
    CREATE POLICY "Users can delete own avatar"
      ON storage.objects FOR DELETE
      TO authenticated
      USING (
        bucket_id = 'avatars'
        AND owner = auth.uid()
      );
  END IF;
END $$;


-- ── 2. create_direct_group_by_id RPC ─────────────────────────────────────────
-- Creates (or returns existing) a 1-on-1 "direct" group between the caller
-- and another user identified by UUID. Used by the friend-add search flow.
CREATE OR REPLACE FUNCTION public.create_direct_group_by_id(p_other_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_my_id    UUID := auth.uid();
  v_group_id UUID;
  v_name     TEXT;
BEGIN
  IF v_my_id IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;
  IF v_my_id = p_other_id THEN
    RAISE EXCEPTION 'cannot_add_self';
  END IF;

  -- Return existing direct group between the two users if one already exists.
  SELECT gm1.group_id INTO v_group_id
  FROM   public.group_members gm1
  JOIN   public.group_members gm2 ON gm1.group_id = gm2.group_id
  JOIN   public.groups g          ON g.id = gm1.group_id
  WHERE  gm1.user_id = v_my_id
    AND  gm2.user_id = p_other_id
    AND  g.type = 'direct'
  LIMIT 1;

  IF v_group_id IS NOT NULL THEN
    RETURN v_group_id;
  END IF;

  -- Derive a group name from the other user's profile.
  SELECT COALESCE(name, 'Friend') INTO v_name
  FROM   public.profiles
  WHERE  id = p_other_id;

  -- Create the direct group.
  INSERT INTO public.groups (id, name, creator_id, type)
  VALUES (gen_random_uuid(), v_name, v_my_id, 'direct')
  RETURNING id INTO v_group_id;

  -- Add both members.
  INSERT INTO public.group_members (group_id, user_id)
  VALUES (v_group_id, v_my_id), (v_group_id, p_other_id)
  ON CONFLICT DO NOTHING;

  RETURN v_group_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_direct_group_by_id(UUID) TO authenticated;

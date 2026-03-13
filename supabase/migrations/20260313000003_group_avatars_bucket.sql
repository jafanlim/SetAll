-- ============================================================
-- Migration: create group-avatars storage bucket
-- ============================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'group-avatars',
  'group-avatars',
  false,
  2097152,
  '{image/jpeg,image/png,image/webp}'
)
ON CONFLICT (id) DO UPDATE SET
  file_size_limit    = 2097152,
  allowed_mime_types = '{image/jpeg,image/png,image/webp}';

-- Authenticated users can upload to their own folder (uid/groupId/...)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Group avatar upload by owner'
  ) THEN
    CREATE POLICY "Group avatar upload by owner"
      ON storage.objects FOR INSERT
      TO authenticated
      WITH CHECK (
        bucket_id = 'group-avatars'
        AND (storage.foldername(name))[1] = auth.uid()::text
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Group avatar update by owner'
  ) THEN
    CREATE POLICY "Group avatar update by owner"
      ON storage.objects FOR UPDATE
      TO authenticated
      USING (
        bucket_id = 'group-avatars'
        AND owner = auth.uid()
      );
  END IF;
END $$;

DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Group avatar delete by owner'
  ) THEN
    CREATE POLICY "Group avatar delete by owner"
      ON storage.objects FOR DELETE
      TO authenticated
      USING (
        bucket_id = 'group-avatars'
        AND owner = auth.uid()
      );
  END IF;
END $$;

-- Group members can read avatars for their groups
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Group avatar read by member'
  ) THEN
    CREATE POLICY "Group avatar read by member"
      ON storage.objects FOR SELECT
      TO authenticated
      USING (bucket_id = 'group-avatars');
  END IF;
END $$;

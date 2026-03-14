-- Add soft-delete columns to profiles table for the 30-day cooling-off deletion flow.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS is_deleted          boolean     NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS scheduled_deletion_at timestamptz;

-- Users can update their own soft-delete flag (used by Delete Account in Settings).
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'profiles'
      AND policyname = 'Users can soft-delete own profile'
  ) THEN
    EXECUTE '
      CREATE POLICY "Users can soft-delete own profile"
        ON public.profiles FOR UPDATE
        USING (auth.uid() = id)
        WITH CHECK (auth.uid() = id)
    ';
  END IF;
END $$;

-- Add registration_complete flag to profiles.
-- Trigger-created profiles default to false; only profiles created through
-- the proper register screen get set to true.
-- All existing real profiles are marked complete immediately.

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS registration_complete boolean NOT NULL DEFAULT false;

-- Mark all pre-existing real (non-ghost) profiles as complete so existing
-- users are not locked out after this migration.
UPDATE public.profiles
  SET registration_complete = true
  WHERE is_ghost = false;

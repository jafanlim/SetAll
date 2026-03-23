-- FEAT-17: Add notification_preferences jsonb column to profiles
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS notification_preferences jsonb
  NOT NULL DEFAULT jsonb_build_object(
    'monthly_digest', true,
    'expense_alerts', true
  );

-- Add widget_layout column to profiles for Insights Hub persistence.
-- Used by insights.html to save/restore user's widget arrangement.
ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS widget_layout TEXT;

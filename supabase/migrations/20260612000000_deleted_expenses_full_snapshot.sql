-- =============================================================================
-- Complete the deleted_expenses tombstone to carry everything needed for a
-- faithful restore — matching iOS SQLite parity + columns iOS doesn't yet
-- snapshot but that the expenses table needs for a perfect round-trip.
-- =============================================================================

ALTER TABLE public.deleted_expenses
  ADD COLUMN IF NOT EXISTS deleted_with_group_id uuid,
  ADD COLUMN IF NOT EXISTS exchange_rate_applied text,
  ADD COLUMN IF NOT EXISTS base_currency_amount text,
  ADD COLUMN IF NOT EXISTS payer_id            uuid,
  ADD COLUMN IF NOT EXISTS split_type          text,
  ADD COLUMN IF NOT EXISTS icon_codepoint      integer,
  ADD COLUMN IF NOT EXISTS icon_color          bigint,
  ADD COLUMN IF NOT EXISTS notes               text,
  ADD COLUMN IF NOT EXISTS attachment_urls     text;

COMMENT ON COLUMN public.deleted_expenses.deleted_with_group_id IS
  'Set when cascade-deleted with a group. Used by restoreGroup to find only the expenses that were deleted as part of the group.';
COMMENT ON COLUMN public.deleted_expenses.exchange_rate_applied IS
  'Historical FX rate from original_currency to base at entry time.';
COMMENT ON COLUMN public.deleted_expenses.base_currency_amount IS
  'Frozen total in the payer''s base currency at entry time.';
COMMENT ON COLUMN public.deleted_expenses.payer_id IS
  'Original payer of the expense — not necessarily the user who deleted it.';
COMMENT ON COLUMN public.deleted_expenses.split_type IS
  'Original split type (even / manual / parts).';
COMMENT ON COLUMN public.deleted_expenses.icon_codepoint IS
  'Integer codepoint of the custom entry icon.';
COMMENT ON COLUMN public.deleted_expenses.icon_color IS
  'Integer ARGB value of the custom entry accent colour.';
COMMENT ON COLUMN public.deleted_expenses.notes IS
  'Long-form notes attached to the expense.';
COMMENT ON COLUMN public.deleted_expenses.attachment_urls IS
  'JSON-encoded list of attachment storage paths.';

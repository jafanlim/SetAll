-- ============================================================
-- Migration: add entry_amount_owed to splits table
-- Stores the per-person share in the expense's entry currency
-- (e.g. GEL) so the detail view never needs a lossy USD back-conversion.
-- ============================================================

ALTER TABLE public.splits
  ADD COLUMN IF NOT EXISTS entry_amount_owed numeric(14, 4);

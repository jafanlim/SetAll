-- =============================================================================
-- Baseline repair — expenses column drift
--
-- These columns exist in the production `expenses` table (added ad-hoc via the
-- Supabase dashboard) but were never captured as migrations, so a from-scratch
-- replay (`supabase start`, `db reset`, CI, branch databases, disaster recovery)
-- fails at 20260323000003_migrate_personal_expenses.sql, which reads
-- `e.is_income`.
--
-- This migration is intentionally dated BEFORE 20260323000003 so the chain
-- replays cleanly. Every statement is `IF NOT EXISTS`, so it is a guaranteed
-- no-op on the production database where the columns already exist. When
-- `supabase db push` applies this out-of-order missing version, it changes
-- nothing on prod.
--
-- Discovered during the setall-secret-rls-audit Phase 1 local-verification step.
-- Safe to re-run.
-- =============================================================================

ALTER TABLE public.expenses
  -- Personal/wallet entries and income vs. expense flag (used by the app and by
  -- 20260323000003_migrate_personal_expenses.sql).
  ADD COLUMN IF NOT EXISTS is_income boolean NOT NULL DEFAULT false,
  -- Author of the row (uid). No FK: ghost/soft-deleted authors must not block.
  ADD COLUMN IF NOT EXISTS created_by uuid,
  -- Frozen total in the payer's base currency at entry time (schema v33 in the
  -- local SQLite store); eliminates USD-rate drift in wallet totals.
  ADD COLUMN IF NOT EXISTS base_currency_amount numeric(24, 10);

COMMENT ON COLUMN public.expenses.is_income IS
  'True when this row is income rather than a spend (personal/wallet entries).';
COMMENT ON COLUMN public.expenses.created_by IS
  'uid of the row author; no FK so ghost/deleted authors do not block writes.';
COMMENT ON COLUMN public.expenses.base_currency_amount IS
  'Frozen total in the payer base currency at entry time (anti rate-drift).';

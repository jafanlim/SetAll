-- =============================================================================
-- Baseline repair — enable pg_cron (and pg_net) for from-scratch replay
--
-- The scheduled-job migrations (20260324000002, 20260324000004, 20260325000002,
-- 20260601000001) call cron.schedule()/cron.unschedule(), but pg_cron was
-- enabled on production via the dashboard and never captured as a migration, so
-- a from-scratch replay fails with: schema "cron" does not exist.
--
-- Dated BEFORE the first cron usage (20260324000002) so the chain replays.
-- IF NOT EXISTS → guaranteed no-op on production where these extensions are
-- already enabled. pg_net is also created defensively (some net.* call sites
-- predate the migration that first creates it).
--
-- Discovered during the setall-secret-rls-audit Phase 1 local-verification step.
-- Safe to re-run.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

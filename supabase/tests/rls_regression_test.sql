-- =============================================================================
-- RLS regression suite — setall-secret-rls-audit Phase 1
--
-- Run with:  supabase test db
-- (or:  psql "$DATABASE_URL" -f supabase/tests/rls_regression_test.sql)
--
-- Proves the Phase 1 guarantees:
--   • user A cannot read user B's wallet_entries or expenses
--   • a non-member cannot read another group's rows
--   • anon reads nothing on any personal table
--   • soft-deleted expenses are hidden from their owner
--   • the settlement RPC is membership-gated (member ok, non-member rejected)
--
-- The whole file runs inside one pgTAP transaction and is rolled back, so it
-- never pollutes the database. Setup runs as the table owner (RLS bypassed);
-- assertions switch to the authenticated/anon roles with a forged JWT claim.
-- =============================================================================

BEGIN;
SELECT plan(18);

-- ── Fixtures (run as the owner, RLS bypassed) ────────────────────────────────
-- Disable triggers during setup: inserting into auth.users otherwise fires the
-- handle_new_user trigger (auto-creates a profiles row → duplicate-key clash)
-- and the welcome-email pg_net trigger. Restored to 'origin' before assertions.
SET session_replication_role = replica;

\set uidA '11111111-1111-1111-1111-111111111111'
\set uidB '22222222-2222-2222-2222-222222222222'
\set gid  '33333333-3333-3333-3333-333333333333'

INSERT INTO auth.users (instance_id, id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
VALUES
  ('00000000-0000-0000-0000-000000000000', :'uidA', 'authenticated',
   'authenticated', 'a@test.local', '', now(), now(), now()),
  ('00000000-0000-0000-0000-000000000000', :'uidB', 'authenticated',
   'authenticated', 'b@test.local', '', now(), now(), now());

INSERT INTO public.profiles (id, name, default_currency)
VALUES (:'uidA', 'Alice', 'USD'),
       (:'uidB', 'Bob',   'USD');

-- Group owned by A, with A as the only member. B is NOT a member.
INSERT INTO public.groups (id, name, creator_id) VALUES (:'gid', 'A-only group', :'uidA');
INSERT INTO public.group_members (group_id, user_id) VALUES (:'gid', :'uidA');

-- A group expense (payer A) in A's group.
INSERT INTO public.expenses (id, group_id, payer_id, amount, description)
VALUES ('aaaa1111-0000-0000-0000-000000000001', :'gid', :'uidA', 10, 'group exp');

-- A's personal (wallet) expense — active.
INSERT INTO public.expenses (id, group_id, payer_id, amount, description)
VALUES ('aaaa1111-0000-0000-0000-000000000002', NULL, :'uidA', 20, 'personal active');

-- A's personal expense — soft-deleted (must be hidden from A).
INSERT INTO public.expenses (id, group_id, payer_id, amount, description, deleted_at)
VALUES ('aaaa1111-0000-0000-0000-000000000003', NULL, :'uidA', 30, 'personal deleted', now());

-- A's wallet_entries row (legacy table, still RLS-covered).
INSERT INTO public.wallet_entries (id, user_id, amount, is_income, description, universal_usd_amount)
VALUES ('bbbb1111-0000-0000-0000-000000000001', :'uidA', 5, false, 'wallet', '5');

-- A's ai_insights / fcm_tokens / bug_reports rows (for anon-isolation checks).
INSERT INTO public.ai_insights (user_id, analysis_type, period_start, period_end, summary)
VALUES (:'uidA', 'weekly', now(), now(), 'sum');
INSERT INTO public.fcm_tokens (user_id, token, platform)
VALUES (:'uidA', 'tok-A', 'ios');
INSERT INTO public.bug_reports (user_id, description)
VALUES (:'uidA', 'bug');

-- Re-enable triggers / normal enforcement for the assertion phase.
SET session_replication_role = origin;

-- ── Helper to impersonate a user / anon ──────────────────────────────────────
-- auth.uid() reads request.jwt.claims->>'sub'.

-- =====================  ANON: reads nothing on personal tables  ==============
SET LOCAL ROLE anon;
SET LOCAL request.jwt.claims TO '';

SELECT is((SELECT count(*) FROM public.profiles)::int,       0, 'anon: profiles invisible');
SELECT is((SELECT count(*) FROM public.expenses)::int,       0, 'anon: expenses invisible');
SELECT is((SELECT count(*) FROM public.wallet_entries)::int, 0, 'anon: wallet_entries invisible');
SELECT is((SELECT count(*) FROM public.ai_insights)::int,    0, 'anon: ai_insights invisible');
SELECT is((SELECT count(*) FROM public.fcm_tokens)::int,     0, 'anon: fcm_tokens invisible');
SELECT is((SELECT count(*) FROM public.bug_reports)::int,    0, 'anon: bug_reports invisible');

RESET ROLE;

-- =====================  USER B: cannot read A's data  ========================
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"22222222-2222-2222-2222-222222222222","role":"authenticated"}';

SELECT is((SELECT count(*) FROM public.groups   WHERE id = '33333333-3333-3333-3333-333333333333')::int, 0,
          'B: cannot see A-only group');
SELECT is((SELECT count(*) FROM public.expenses WHERE group_id = '33333333-3333-3333-3333-333333333333')::int, 0,
          'B: cannot see A group expenses');
SELECT is((SELECT count(*) FROM public.expenses WHERE payer_id = '11111111-1111-1111-1111-111111111111' AND group_id IS NULL)::int, 0,
          'B: cannot see A personal expenses');
SELECT is((SELECT count(*) FROM public.wallet_entries WHERE user_id = '11111111-1111-1111-1111-111111111111')::int, 0,
          'B: cannot see A wallet_entries');
SELECT is((SELECT count(*) FROM public.profiles WHERE id = '11111111-1111-1111-1111-111111111111')::int, 0,
          'B: cannot see A profile (no shared group)');

-- B is not a member → settlement RPC must be rejected.
SELECT throws_ok(
  $$ SELECT public.set_group_settlement('33333333-3333-3333-3333-333333333333', true) $$,
  'permission_denied: only a group member can change settlement',
  'B: settlement RPC rejected for non-member'
);

RESET ROLE;

-- =====================  USER A: sees own, hides soft-deleted  ================
SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims TO '{"sub":"11111111-1111-1111-1111-111111111111","role":"authenticated"}';

SELECT is((SELECT count(*) FROM public.groups   WHERE id = '33333333-3333-3333-3333-333333333333')::int, 1,
          'A: sees own group');
SELECT is((SELECT count(*) FROM public.expenses WHERE group_id = '33333333-3333-3333-3333-333333333333')::int, 1,
          'A: sees own group expense');
SELECT is((SELECT count(*) FROM public.expenses WHERE group_id IS NULL AND payer_id = '11111111-1111-1111-1111-111111111111')::int, 1,
          'A: sees exactly one active personal expense (soft-deleted hidden)');
SELECT is((SELECT count(*) FROM public.wallet_entries WHERE user_id = '11111111-1111-1111-1111-111111111111')::int, 1,
          'A: sees own wallet_entries');

-- A is a member → settlement RPC succeeds and sets settled_at.
SELECT lives_ok(
  $$ SELECT public.set_group_settlement('33333333-3333-3333-3333-333333333333', true) $$,
  'A: settlement RPC allowed for member'
);

RESET ROLE;
SELECT is((SELECT (settled_at IS NOT NULL) FROM public.groups WHERE id = '33333333-3333-3333-3333-333333333333'),
          true, 'A: settlement persisted settled_at');

SELECT * FROM finish();
ROLLBACK;

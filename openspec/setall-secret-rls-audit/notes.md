# setall-secret-rls-audit — Phase 1 notes

Status: Phase 0 (key rotation, history scrub, legacy keys disabled) **DONE**.
Phase 1 (RLS verification + gap closure + auth hardening) tracked here.

## 1. RLS findings (audit, migration-derived from 46 migrations)

All 11 `public` tables have RLS enabled.

| Table | RLS | Scope | Result |
|---|---|---|---|
| `wallet_entries` | on | owner `auth.uid()`, SELECT filters `deleted_at` | reference template |
| `profiles` | on | self + group co-members | **was** globally readable — fixed |
| `expenses` (group + personal) | on | membership / owner | SELECT **was** missing `deleted_at` — fixed |
| `splits` | on | membership / payer | ok |
| `group_members` | on | membership | ok |
| `groups` | on | membership read, creator write | settlement gap — fixed via RPC |
| `pending_invites` | on | membership | ok |
| `exchange_rates` | on | public read, no client write | ok |
| `fcm_tokens` | on | owner | ok |
| `ai_insights` | on | owner | ok |
| `bug_reports` | on | INSERT-only owner; triage reads via service_role | intentional, safe |

### Gaps closed in `20260601000002_rls_gap_closure.sql`
1. **profiles (HIGH)** — dropped `"Users can read all profiles" USING (true)` (had no
   `TO` clause → anon + any authenticated user could read the whole table). Reads
   are covered by `"Profiles viewable by group members"` + the `search_profiles()`
   SECURITY DEFINER RPC. Read paths diffed first: all profile selects use
   `eq('id', uid)`, `inFilter('id', <co-members>)`, or the RPC.
2. **expenses (MED)** — added `AND deleted_at IS NULL` to both SELECT policies.
   Group deletes are hard deletes (no-op); personal web deletes are soft — the
   filter also fixes a latent bug where web-deleted wallet entries stayed visible
   and never propagated to other devices.
3. **groups settlement (MED)** — added membership-checked `set_group_settlement(uuid, boolean)`
   SECURITY DEFINER RPC so non-creator members can settle/reopen without widening
   the creator-only `groups` UPDATE policy. Client (`setGroupSettled` /
   `clearGroupSettled`) now calls the RPC.

### Regression tests
`supabase/tests/rls_regression_test.sql` (pgTAP). Run: `supabase test db`.
Covers: A≠B (wallet_entries, group + personal expenses, profile), non-member ≠
group rows, anon = nothing on every personal table, soft-deleted expense hidden
from owner, settlement RPC member-allowed / non-member-rejected.

## 2. Auth dashboard hardening (D3) — final settings

Set in Supabase Dashboard → Authentication. Document the applied values here after
toggling (these are the target settings):

- **Email confirmation:** ON (Providers → Email → "Confirm email" enabled).
- **Leaked-password protection:** ON (Authentication → Policies → "Prevent use of
  leaked passwords" / HaveIBeenPwned check enabled).
- **Minimum password length:** ≥ 8; require at least one of lower/upper/digit.
- **JWT expiry:** access token 3600 s (1 h); refresh-token rotation ON with
  reuse-interval 10 s.
- **Redirect allowlist (URL Configuration → Redirect URLs):** explicit entries only,
  **no wildcards** —
  - `https://setall.app/**` → replace with exact paths actually used:
    `https://setall.app/auth/callback`, `https://setall.app/account`,
    `https://setall.app/reset-password`
  - `com.jafa.setall.app://login-callback` (mobile deep link)
  - `http://localhost:3000/auth/callback` (local dev only — remove for prod project)
- **Site URL:** `https://setall.app`.

> After changing JWT expiry, existing sessions keep their old TTL until refresh.

## 3. Pre-release RLS check (run before every release)

```sql
-- 1) Every public table must have RLS enabled (relrowsecurity = true).
SELECT relname, relrowsecurity
FROM   pg_class
WHERE  relkind = 'r' AND relnamespace = 'public'::regnamespace
ORDER  BY relname;

-- 2) Inspect each table's policies (scope = auth.uid() or group membership).
SELECT tablename, policyname, cmd, roles, qual, with_check
FROM   pg_policies
WHERE  schemaname = 'public'
ORDER  BY tablename, cmd;

-- 3) Flag any table with RLS OFF (should return zero rows).
SELECT relname
FROM   pg_class
WHERE  relkind = 'r' AND relnamespace = 'public'::regnamespace
  AND  relrowsecurity = false;

-- 4) Flag personal/soft-delete tables whose SELECT policy omits deleted_at.
--    (manual review of #2 output for wallet_entries + expenses SELECT rows)
```

Gate: #3 returns zero rows; `supabase test db` (RLS suite) green.

## Migration replayability (discovered during local verification)
The migration chain was NOT replayable from scratch (broke `supabase start` / CI /
branch DBs / disaster recovery), independent of the RLS work. Fixed with no-op-on-prod
repairs + one replay-safe guard:
- `20260322000000_repair_expenses_column_drift.sql` — adds expenses
  `is_income` / `created_by` / `base_currency_amount` (`IF NOT EXISTS`).
- `20260324000000_repair_enable_pg_cron.sql` — enables `pg_cron` / `pg_net`
  before their first use.
- `20260326000003_set_service_role_key.sql` — wrapped the `ALTER DATABASE`
  in an exception-safe `DO` block so it skips without admin privileges locally.
  (Value is the `REDACTED_JWT` placeholder — confirms the Phase 0 scrub held.)
A full `supabase start` now replays the entire chain cleanly.

## Exit gate
- [x] Findings table approved
- [x] Full chain replays from scratch (`supabase start`)
- [x] `supabase test db` regression suite passes (18/18)
- [x] Migration `20260601000002` pushed to prod (`supabase db push --include-all`)
- [ ] Dashboard spot-check: `profiles` has only the `Profiles viewable by group members` SELECT policy
- [ ] Auth dashboard settings applied + recorded above (section 2)

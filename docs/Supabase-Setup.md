# Supabase Setup

---

## Project Credentials

Configured in `lib/main.dart` and `lib/core/config/auth_config.dart`:

- **Project URL:** `https://vrsmsgyxeyzyrdonsnrk.supabase.co`
- **Anon Key:** see `lib/main.dart`

---

## Required Tables

Run `supabase/migrations/001_exchange_rates.sql` to set up:

- `exchange_rates` table (rates populated by Edge Function)
- `base_amount_at_entry` column on `expenses`

Other tables (`groups`, `group_members`, `expenses`, `splits`, `profiles`) should be set up with matching structure to the SQLite schema — see [Database Schema](Database-Schema.md).

---

## RPC Functions

### `add_member_by_email`

Adds a user to a group by their email address. Called from the AddMember dialog in GroupDetailScreen.

```sql
-- Example signature (create in Supabase SQL editor)
CREATE OR REPLACE FUNCTION add_member_by_email(
  p_group_id UUID,
  p_email    TEXT
) RETURNS void AS $$
  INSERT INTO group_members (group_id, user_id)
  SELECT p_group_id, id FROM auth.users WHERE email = p_email
  ON CONFLICT DO NOTHING;
$$ LANGUAGE sql SECURITY DEFINER;
```

---

## Edge Functions

### `sync-exchange-rates`
**Location:** `supabase/functions/sync-exchange-rates/index.ts`

Fetches all rates from Frankfurter API and upserts into `exchange_rates` table.

**Deploy:**
```bash
supabase functions deploy sync-exchange-rates
```

**Schedule (Supabase Dashboard):**
- Go to Database → Cron Jobs
- Create job: `0 0 * * *` (daily midnight UTC)
- Command: `SELECT net.http_post('https://vrsmsgyxeyzyrdonsnrk.supabase.co/functions/v1/sync-exchange-rates', '{}', 'application/json');`

**Or use pg_cron via SQL:**
```sql
SELECT cron.schedule(
  'sync-exchange-rates-daily',
  '0 0 * * *',
  $$ SELECT net.http_post(...) $$
);
```

---

## Authentication

### Email/Password
Enable in Supabase Dashboard → Authentication → Providers → Email.

### Google OAuth
1. Create OAuth credentials in Google Cloud Console
2. Add Client ID + Secret in Supabase Dashboard → Authentication → Providers → Google
3. Add redirect URL: `https://vrsmsgyxeyzyrdonsnrk.supabase.co/auth/v1/callback`
4. For mobile deep links, configure your app's URL scheme

### Anonymous Sign-In
Currently **not used** (disabled). The app requires email or Google authentication.

---

## Row Level Security

All tables should have RLS enabled. Recommended policies:

```sql
-- Users can only read/write their own data
CREATE POLICY "users_own_profile" ON profiles
  FOR ALL USING (auth.uid() = id);

CREATE POLICY "group_members_access" ON expenses
  FOR ALL USING (
    group_id IN (
      SELECT group_id FROM group_members WHERE user_id = auth.uid()
    )
  );
```

Exchange rates use read-only policies for all authenticated/anon users (write is service_role only via Edge Function).

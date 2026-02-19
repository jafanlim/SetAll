# SetAll — Supabase setup

## One-time schema setup

1. Open your project: **https://supabase.com/dashboard** → select **SetAll**.
2. Go to **SQL Editor** → **New query**.
3. Open the file **`run_in_sql_editor.sql`** in this folder, copy its full contents, paste into the SQL Editor, and click **Run**.

This creates:

- **profiles** — user profiles (name, default_currency), auto-created on sign-up
- **groups** — cost-sharing groups
- **group_members** — who is in each group
- **expenses** — expenses with amount, currency, category, and optional currency normalization fields
- **splits** — who owes how much per expense
- **RLS policies** — so users only see data for groups they belong to
- **RPCs** — `add_member_by_email`, `is_group_member`

After it runs successfully, the app can sync with Supabase (with URL and anon key set in `lib/main.dart`).

## Optional: run migrations individually

If you prefer to run the original migrations in order instead of the single script, use the files in **`migrations/`** in numeric order. The single script **`run_in_sql_editor.sql`** is equivalent and idempotent (safe to run once; uses `if not exists` / `add column if not exists` where applicable).

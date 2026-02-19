# Database Schema

SetAll uses **SQLite** (mobile/desktop, `sqflite`) and **Supabase PostgreSQL** (cloud sync + web).

---

## SQLite Schema (v4)

### groups
```sql
CREATE TABLE groups (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  creator_id TEXT NOT NULL,
  created_at TEXT,
  updated_at TEXT,
  synced_at  INTEGER
)
```

### group_members
```sql
CREATE TABLE group_members (
  group_id  TEXT NOT NULL,
  user_id   TEXT NOT NULL,
  joined_at TEXT,
  synced_at INTEGER,
  PRIMARY KEY (group_id, user_id)
)
```

### expenses
```sql
CREATE TABLE expenses (
  id                    TEXT PRIMARY KEY,
  group_id              TEXT NOT NULL,
  payer_id              TEXT NOT NULL,
  amount                TEXT NOT NULL,       -- base-currency total (Decimal string)
  description           TEXT,
  currency              TEXT,                -- expense entry currency
  split_type            TEXT,                -- 'even' | 'manual' | 'parts'
  category              TEXT,
  original_amount       TEXT,                -- pre-conversion amount (v3+)
  original_currency     TEXT,                -- pre-conversion currency (v3+)
  exchange_rate_applied TEXT,                -- rate at entry time (v3+)
  base_amount_at_entry  TEXT,                -- frozen base total (v4+) ← KEY FIELD
  created_at            TEXT,
  updated_at            TEXT,
  synced_at             INTEGER
)
```

### splits
```sql
CREATE TABLE splits (
  id          TEXT PRIMARY KEY,
  expense_id  TEXT NOT NULL,
  user_id     TEXT NOT NULL,
  amount_owed TEXT NOT NULL,   -- Decimal string, in expense currency
  created_at  TEXT,
  synced_at   INTEGER
)
```

### profiles
```sql
CREATE TABLE profiles (
  id               TEXT PRIMARY KEY,
  name             TEXT NOT NULL,
  default_currency TEXT,
  synced_at        INTEGER
)
```

### exchange_rates (v4)
```sql
CREATE TABLE exchange_rates (
  base_currency   TEXT NOT NULL,
  target_currency TEXT NOT NULL,
  rate            TEXT NOT NULL,   -- Decimal string, 1 base = rate target
  last_updated    TEXT,
  PRIMARY KEY (base_currency, target_currency)
)
```

---

## Migration History

| Version | Change |
|---------|--------|
| v1 | Initial schema |
| v2 | `ALTER TABLE expenses ADD COLUMN category TEXT` |
| v3 | Add `original_amount`, `original_currency`, `exchange_rate_applied` |
| v4 | Add `base_amount_at_entry` on expenses; add `exchange_rates` table |

---

## Supabase Tables

Same structure as SQLite plus UUID primary keys and native TIMESTAMPTZ. Managed via:

- `supabase/migrations/001_exchange_rates.sql` — exchange_rates table, RLS, and `base_amount_at_entry` column on expenses

### Row-Level Security (exchange_rates)

```sql
-- Anyone authenticated or anonymous can read
CREATE POLICY "exchange_rates_read_authenticated"
  ON public.exchange_rates FOR SELECT TO authenticated USING (true);

CREATE POLICY "exchange_rates_read_anon"
  ON public.exchange_rates FOR SELECT TO anon USING (true);

-- Only service_role (Edge Function) can write
```

---

## Key Design Decisions

### `base_amount_at_entry` (v4)

The most important field added. When a user enters an expense in any currency:

1. The rate is fetched at that moment.
2. The full expense total is converted to the user's base currency.
3. This value is **frozen** in `base_amount_at_entry`.

**Why:** Eliminates the "$104 bug" — previously, balance calculations used live rates, so an expense entered when 1 USD = 0.9 EUR would recalculate differently the next day. Now the historical value is locked in.

`BalanceService` uses it as Priority 1 — no API call, no rate drift, fully offline.

# Changelog

---

## [Unreleased / Current]

### Added
- **CurrencySyncService** — Supabase `exchange_rates` table as single source of truth for exchange rates
  - One Edge Function syncs Frankfurter → Supabase every 24h (one API call per platform per day, not per device)
  - Rates cached to SharedPreferences for full offline support
  - In-memory cache within a session
- **`sync-exchange-rates` Supabase Edge Function** (`supabase/functions/sync-exchange-rates/index.ts`)
  - Fetches all rates from Frankfurter API with `base_currency = USD`
  - Upserts into `public.exchange_rates` table
- **Supabase migration `001_exchange_rates.sql`**
  - `exchange_rates` table with RLS (read: all, write: service_role only)
  - `base_amount_at_entry` column on `expenses` table
- **`base_amount_at_entry` field** on `Expense` entity, `ExpenseModel`, and SQLite schema (v4)
  - Frozen base-currency total written at entry time
  - Eliminates the "$104 bug" — balance calculations are immune to future rate changes
- **`LocalDatabase` schema v4** — `base_amount_at_entry` column + local `exchange_rates` table
- **Background rate sync on startup** — non-blocking, happens after UI is ready

### Changed
- **`BalanceService`** — 4-tier conversion priority:
  1. `baseAmountAtEntry` (v4+, fastest, no API call)
  2. Currency match (no conversion needed)
  3. `exchangeRateApplied` (v3 stored rate)
  4. Live rate lookup (v1-v2 legacy, last resort)
- **`CurrencyService`** — 3-tier rate resolution: manual override → Supabase DB → Frankfurter live
- **`setall_providers.dart`** — wired `CurrencySyncService` into Riverpod provider graph
- **`SetAllRepository`** — writes `base_amount_at_entry` on every new expense
- **`AddExpenseScreen`** — multi-currency wizard: 30 currencies, live rate preview, manual override
- **`DashboardScreen`** — fintech colour palette (teal/orange), responsive NavigationRail
- **`main.dart`** — background rate sync after app ready, improved error handling

### Fixed
- **$104 bug** — historical balances no longer recalculate with live rates
- **Offline balance accuracy** — `base_amount_at_entry` means no network needed for balance display

---

## [Initial Titanium Build]
`commit: 75858c3`

- Initial Flutter project setup
- Supabase integration
- SQLite offline-first v1 schema
- Riverpod state management
- GoRouter navigation with auth guards
- Material 3 dark/light themes
- AddExpense, Dashboard, GroupDetail, Login screens
- Biometric authentication (Face ID / Touch ID)
- Debt simplification engine
- Even expense splitting

---

## [iOS Build Fix]
`commit: 70288c4`

- Resolved codesign failures on iOS
- Config fixes for Runner target

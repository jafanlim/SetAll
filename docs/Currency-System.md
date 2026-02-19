# Currency System

SetAll has a 3-tier exchange rate system with full offline support.

---

## Architecture

```
Frankfurter API (external)
        ↓  (once per 24h, via Edge Function)
Supabase exchange_rates table
        ↓  (on app startup, background sync)
SharedPreferences cache (device)
        ↓  (in-memory during session)
CurrencySyncService._memCache
```

Only the **Edge Function** ever calls Frankfurter. All Flutter clients read from the Supabase table or the local SharedPreferences cache.

---

## Services

### CurrencySyncService (`lib/core/services/currency_sync_service.dart`)

Single source of truth for stored rates.

**Key methods:**
- `syncRates()` — fetches from Supabase, persists to SharedPreferences. Called non-blocking on app startup.
- `getRate(from, to)` — returns cross-rate computed from USD-base rates.

**Rate storage format:** All rates stored as `1 USD = X target`. Cross-rates are computed as `(to_rate / from_rate)`.

**Cache keys:**
- `setall_v2_exchange_rates` — JSON map of rates
- `setall_v2_exchange_rates_ts` — timestamp of last sync

---

### CurrencyService (`lib/core/services/currency_service.dart`)

Rate resolution with 3-tier priority:

| Priority | Source | When used |
|----------|--------|-----------|
| 1 | Manual override (SharedPreferences) | User entered a custom rate |
| 2 | Supabase DB rates via CurrencySyncService | Normal operation |
| 3 | Frankfurter live API | First launch, no cache, device online |

**Manual override:** User can enter a custom exchange rate per transaction (e.g. the actual bank rate they got). Stored with key `setall_rate_override_{from}_{to}`. Inverse is auto-derived.

**Live API cache:** 15-minute in-memory TTL for Frankfurter responses (last resort only).

---

### BalanceService (`lib/core/services/balance_service.dart`)

Converts all split amounts to the user's base currency for summing.

**4-tier conversion priority per split entry:**

| Priority | Field | Description |
|----------|-------|-------------|
| 1 | `baseAmountAtEntry` | Frozen at entry (schema v4+). Zero API calls. |
| 2 | Currency match | Split is already in base currency. |
| 3 | `exchangeRateApplied` | Rate persisted at v3 entry time. |
| 4 | Live rate | Legacy v1-v2 data. Last resort. |

---

## Supabase Edge Function

**Location:** `supabase/functions/sync-exchange-rates/index.ts`

**Schedule:** Every 24 hours (configured in Supabase dashboard).

**What it does:**
1. Fetches all rates from `https://api.frankfurter.dev/latest?from=USD`
2. Upserts rows into `public.exchange_rates` with `base_currency = 'USD'`

**Why centralized:** One network call per day for the entire platform instead of one per device per session. Devices just read from the DB.

---

## Supported Currencies (30)

USD, EUR, GBP, JPY, AUD, CAD, CHF, CNY, HKD, NZD, SEK, KRW, SGD, NOK, MXN, INR, RUB, ZAR, TRY, BRL, THB, DKK, PLN, TWD, CZK, HUF, ILS, MYR, PHP, AED

---

## The $104 Bug (Fixed in v4)

**Problem:** A group expense of 100 EUR entered when EUR/USD = 1.04 would show as $104. If the next day EUR/USD = 1.10, balance calculations would show $110, even though nothing changed.

**Root cause:** BalanceService was doing live rate lookups for every historical split.

**Fix:** `base_amount_at_entry` column stores the frozen base-currency total at entry time. BalanceService Priority 1 returns this directly — no conversion, no drift, no API call.

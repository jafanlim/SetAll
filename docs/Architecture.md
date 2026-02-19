# Architecture

SetAll follows **Clean Architecture** with a clear separation between domain, data, and presentation layers.

---

## Layer Overview

```
lib/
├── domain/          # Pure business logic, no Flutter/Supabase dependencies
│   └── entities/    # Expense, Group, Profile, Split
├── data/            # Data sources: SQLite + Supabase
│   ├── local/       # LocalDatabase (SQLite schema & migrations)
│   ├── models/      # JSON-serializable models extending domain entities
│   └── repositories/# SetAllRepository — offline-first data layer
├── core/            # Cross-cutting concerns
│   ├── services/    # BalanceService, CurrencyService, CurrencySyncService, BiometricService
│   ├── providers/   # Riverpod providers
│   ├── utils/       # SplitEngine, DebtSimplificationEngine, haptics, scaling
│   ├── router/      # GoRouter configuration + auth guards
│   ├── theme/       # Material 3 dark/light themes
│   ├── layout/      # AdaptiveShell — responsive NavigationRail / BottomNav
│   └── widgets/     # GlassCard and shared UI components
└── features/        # UI screens grouped by feature
    ├── auth/        # Login, BiometricGate
    ├── dashboard/   # Dashboard, GroupDetail
    └── expenses/    # AddExpense, EditExpense, GroupPicker
```

---

## State Management

**Riverpod** (`flutter_riverpod ^2.6.1`)

All providers live in `lib/core/providers/setall_providers.dart`:

| Provider | Type | Description |
|----------|------|-------------|
| `setAllRepositoryProvider` | `Provider` | Single repository instance |
| `currencySyncServiceProvider` | `Provider` | Supabase rate sync |
| `currencyServiceProvider` | `Provider` | Rate resolution (override → DB → API) |
| `balanceServiceProvider` | `Provider` | Multi-currency balance calculations |
| `currentUserIdProvider` | `Provider` | Auth user ID |
| `balanceSummaryProvider` | `FutureProvider` | Global net balance |
| `groupBalanceSummaryProvider` | `FutureProvider.family` | Per-group balance |
| `myGroupsProvider` | `FutureProvider` | User's group list |
| `recentExpensesProvider` | `FutureProvider` | Recent activity feed |
| `groupExpensesProvider` | `FutureProvider.family` | Expenses per group |
| `groupMembersProvider` | `FutureProvider.family` | Members per group |
| `simplifiedDebtsProvider` | `FutureProvider.family` | Simplified debts per group |
| `baseCurrencyProvider` | `FutureProvider` | User's base currency |
| `exchangeRateProvider` | `FutureProvider.family` | Live rate for display |
| `rateToBaseProvider` | `FutureProvider.family` | Rate to base currency |

---

## Routing

**GoRouter** (`go_router ^14.6.2`) — configured in `lib/core/router/app_router.dart`.

Auth guard redirects unauthenticated users to `/login`. Deep links and OAuth redirects are handled via `Supabase.instance.client.auth.getSessionFromUrl()`.

---

## Offline-First Strategy

```
Write path:  UI → Repository → SQLite (immediate) → Supabase (when online)
Read path:   Repository → SQLite (fast) → Supabase sync (background)
Rates path:  CurrencySyncService → Supabase exchange_rates → SharedPreferences cache
```

- All writes go to SQLite first; Supabase sync is best-effort.
- `syncIfOnline()` is called before reads to pull fresh server data.
- Exchange rates are synced once per 24h from the Edge Function into Supabase, then cached locally in SharedPreferences. No device ever calls Frankfurter directly in normal operation.
- Web platform uses Supabase-only mode (no SQLite).

---

## Multi-Platform Support

| Platform | Storage | Auth |
|----------|---------|------|
| iOS / Android | SQLite + Supabase | Email, Google OAuth, Biometric |
| macOS / Windows | SQLite + Supabase | Email, Google OAuth |
| Web | Supabase only | Email, Google OAuth |

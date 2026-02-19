# Features

---

## Expense Splitting

Four split methods available in `AddExpenseScreen`:

| Method | Description |
|--------|-------------|
| **Even** | Amount split equally among all members |
| **Percentage** | Each member assigned a percentage (must sum to 100%) |
| **Shares** | Each member assigned share units; converted to percentage |
| **Manual** | Each member's exact amount entered directly |

Logic lives in `lib/core/utils/split_engine.dart`.

---

## Multi-Currency

- Enter any expense in any of 30 supported currencies
- Live exchange rate preview at entry time (Frankfurter via CurrencySyncService)
- Manual rate override for actual bank/cash exchange rates
- All balances displayed in the user's base currency (set in profile)
- Exchange rate locked at entry time via `base_amount_at_entry` — immune to drift

See [Currency System](Currency-System.md) for full details.

---

## Debt Simplification

`lib/core/utils/debt_simplification_engine.dart` — minimizes the number of transactions needed to settle a group.

Example: If A owes B $10 and B owes C $10, simplified result is A pays C $10 directly (B is removed from the chain).

Exposed via `simplifiedDebtsProvider` and shown in GroupDetailScreen.

---

## Offline-First

- All writes save to SQLite immediately
- `syncIfOnline()` runs before reads to pull Supabase updates
- Exchange rates cached in SharedPreferences — balances work with no connectivity
- Web uses Supabase-only mode (no SQLite)

---

## Biometric Authentication

- Face ID / Touch ID on iOS/Android
- `BiometricService` (`lib/core/services/biometric_service.dart`)
- Biometric preference stored in `FlutterSecureStorage`
- `BiometricGateScreen` shown after login if enabled
- Skip option to disable biometrics

---

## Categories

8 expense categories (defined in `lib/domain/entities/expense.dart`):

General, Food & drink, Transport, Entertainment, Bills & utilities, Shopping, Travel, Other

---

## Groups

- Create groups with any name
- Add members by email (Supabase RPC: `add_member_by_email`)
- Special **Personal** group for solo expense tracking
- Per-group balance summary and expense list

---

## Responsive UI

- `AdaptiveShell` (`lib/core/layout/adaptive_shell.dart`): `NavigationRail` on screens ≥ 600px wide, `BottomNavigationBar` on mobile
- `flutter_screenutil` for consistent sizing across screen sizes
- Material 3 dark/light themes with fintech colour palette
  - Teal `#00D9B0` — "You are owed"
  - Orange `#FF8C42` — "You owe"
- Glassmorphism `GlassCard` widget
- Haptic feedback via `HapticUtils`

---

## Authentication

- Email/password sign-in and sign-up
- Google OAuth (requires Google Client IDs configured in Supabase)
- Session recovery from email confirmation and OAuth redirect URLs
- Auth guard in GoRouter redirects unauthenticated users to `/login`

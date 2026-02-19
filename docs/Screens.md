# Screens

---

## LoginScreen
**Path:** `lib/features/auth/presentation/screens/login_screen.dart`

- Email/password sign-in and sign-up tabs
- Google OAuth button
- Email format validation, password strength requirements
- After successful login: prompts to enable biometric if available

---

## BiometricGateScreen
**Path:** `lib/features/auth/presentation/screens/biometric_gate_screen.dart`

- Full-screen biometric authentication prompt
- Shows on app resume if biometric is enabled
- "Skip / Disable biometric" option

---

## DashboardScreen
**Path:** `lib/features/dashboard/presentation/screens/dashboard_screen.dart`

- Global net balance card: "You are owed" (teal) / "You owe" (orange)
- Group list with per-group balance chips
- Recent expenses activity feed
- Theme selector bottom sheet (Dark / Light / System)
- Sign-out
- FAB → AddExpenseScreen (via GroupPickerScreen)
- Responsive: NavigationRail on wide screens

---

## GroupDetailScreen
**Path:** `lib/features/dashboard/presentation/screens/group_detail_screen.dart`

- Group balance summary
- Simplified debts list (who owes whom)
- Group members list
- Group expenses list with payer, amount, category, date
- Add member by email (dialog)
- Delete expense (popup menu, payer only)
- FAB → AddExpenseScreen pre-filled with group

---

## AddExpenseScreen
**Path:** `lib/features/expenses/presentation/screens/add_expense_screen.dart`

3-step wizard:

**Step 1 — Amount & Currency**
- Amount input with currency picker (30 currencies)
- Live exchange rate preview (→ base currency)
- Manual rate override toggle

**Step 2 — Split Method**
- Even / Percentage / Shares / Manual
- Real-time per-member split calculations
- Validation (totals must sum correctly)

**Step 3 — Details**
- Category picker (8 categories)
- Description text field
- Confirm button → saves expense + splits

---

## EditExpenseScreen
**Path:** `lib/features/expenses/presentation/screens/edit_expense_screen.dart`

- Pre-fills all fields from existing expense and splits
- Supports Even or Custom split editing
- Updates expense and split records in SQLite + queues Supabase sync

---

## GroupPickerScreen
**Path:** `lib/features/expenses/presentation/screens/group_picker_screen.dart`

- List of existing groups to add expense to
- Special "Personal" group for solo tracking
- Create new group inline (dialog)
- Navigates to AddExpenseScreen with selected group

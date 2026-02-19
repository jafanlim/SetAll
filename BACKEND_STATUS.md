# Backend & Sync Status

## ✅ Completed

### Database Connection
- **Supabase Integration**: Fully implemented in `lib/main.dart`
  - Initializes Supabase client when URL/key are provided
  - Falls back to offline-only mode when not configured
  - Anonymous sign-in for seamless user experience

### Offline-First Architecture
- **Local SQLite Database**: `lib/data/local/local_database.dart`
  - Tables: `profiles`, `groups`, `group_members`, `expenses`, `splits`
  - Version 3 includes currency normalization fields
  - All writes go to local DB first (`synced_at = NULL` = pending)

### Sync Implementation
- **`syncPendingToSupabase()`**: Pushes local changes to Supabase
  - Syncs groups, group_members, expenses, splits
  - ✅ **Updated**: Now includes currency normalization fields (`original_amount`, `original_currency`, `exchange_rate_applied`)
  - Marks items as synced (`synced_at` timestamp)

- **`_syncFromSupabase(uid)`**: Pulls remote changes to local
  - Fetches user's groups, members, expenses, splits
  - ✅ **Updated**: Now reads currency normalization fields from Supabase
  - Uses `ConflictAlgorithm.replace` for idempotency

- **Automatic Sync Triggers**:
  - `getMyGroups()` → syncs before reading
  - `getBalanceSummary()` → syncs before reading
  - `getRecentExpenses()` → syncs before reading
  - `BalanceService` → calls `syncIfOnline()` before balance calculations

### Supabase Schema & RLS
- **6 Migrations** in `supabase/migrations/`:
  1. `profiles` table + RLS
  2. `groups` + `group_members` + RLS
  3. `expenses` + RLS
  4. `splits` + RLS
  5. `add_member_by_email` RPC
  6. RLS simplification guard (`is_group_member()`)
  7. ✅ **Currency normalization** (`original_amount`, `original_currency`, `exchange_rate_applied`)

- **RLS Policies**: Group-scoped access enforced
  - Users can only read/write expenses/splits for groups they belong to
  - Simplification functions check `is_group_member()`

## ⚠️ Known Limitations

1. **Update Expense**: `updateExpense()` doesn't preserve currency normalization fields when editing
   - If editing an expense with `original_amount`/`original_currency`, those fields are lost
   - **Fix needed**: Add optional parameters to `updateExpense()` or preserve existing values

2. **Profile Sync**: Profiles table sync is not fully implemented
   - Local profiles are created but not synced to Supabase
   - `default_currency` changes won't sync across devices

3. **Conflict Resolution**: No merge strategy for concurrent edits
   - Last-write-wins (Supabase overwrites local on sync)

## 🚀 Web Support

- **Web folder exists**: `web/index.html`, `web/manifest.json`
- **Flutter Web**: Should work out of the box
- **SQLite on Web**: Uses `sqflite_web` (via `sqflite` package) - works in browser
- **Supabase**: Works in web (no CORS issues expected)

### To Test Web:
```bash
flutter run -d chrome
# or
flutter run -d web-server --web-port 8080
```

## 📋 Setup Checklist

1. **Supabase Project**:
   - [ ] Create project at [supabase.com](https://supabase.com)
   - [ ] Run all 7 migrations in order (`supabase/migrations/`)
   - [ ] Copy project URL and anon key to `lib/main.dart`:
     ```dart
     const String _supabaseUrl = 'https://xxxxx.supabase.co';
     const String _supabaseAnonKey = 'eyJhbGc...';
     ```

2. **Test Sync**:
   - [ ] Add expense offline → verify `synced_at IS NULL` in local DB
   - [ ] Go online → verify expense appears in Supabase
   - [ ] Add expense on another device → verify sync to first device

3. **Test Web**:
   - [ ] Run `flutter run -d chrome`
   - [ ] Verify SQLite works (add expense, refresh, data persists)
   - [ ] Verify Supabase sync works (if configured)

## 🔧 Next Steps (Optional Enhancements)

1. **Profile Sync**: Implement profile sync to Supabase
2. **Update Expense**: Preserve currency normalization fields when editing
3. **Conflict Resolution**: Add merge strategy for concurrent edits
4. **Real-time Sync**: Use Supabase Realtime for live updates across devices
5. **Offline Queue**: Better handling of failed syncs (retry logic)

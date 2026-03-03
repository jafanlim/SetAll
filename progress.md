# SetAll – Development Progress Log

---

## Session: Feb 27, 2026

### Changes Made Today

#### 1. Stale profile data on user switch (`lib/app.dart`)
- Converted `SetAllApp` to `ConsumerStatefulWidget`
- Listens to `Supabase.onAuthStateChange`
- On different user sign-in: wipes local SQLite (`splits`, `expenses`, `group_members`, `groups`, `profiles`) and invalidates all Riverpod providers
- On sign-out: invalidates all providers

#### 2. Clear all expenses feature (`lib/data/repositories/setall_repository.dart`, `lib/features/settings/presentation/screens/settings_screen.dart`)
- Added `clearAllExpenses()` to repository — deletes from SQLite + Supabase (scoped to user's groups)
- Added confirmation dialog + "Clear all expenses" tile in Settings screen

#### 3. Deep linking for Google OAuth (`ios/Runner/Info.plist`, `android/app/src/main/AndroidManifest.xml`, `lib/core/config/auth_config.dart`)
- Registered `com.jafa.setall` URL scheme in iOS Info.plist and Android AndroidManifest
- Set `kAuthRedirectBaseUrl = 'com.jafa.setall://login-callback'`
- Fixed `_authRedirectUrl()` to return custom-scheme URLs verbatim (no trailing slash)
- Added `FlutterDeepLinkingEnabled = true` to iOS Info.plist

#### 4. PKCE OAuth flow (`lib/main.dart`)
- Added `authOptions: FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce)` to both `Supabase.initialize` calls

#### 5. OAuth browser launch mode (`lib/features/auth/presentation/screens/login_screen.dart`)
- Changed `signInWithOAuth` to use `LaunchMode.inAppWebView`
- Added `queryParams: {'prompt': 'select_account'}` to force Google account picker

#### 6. Balance raw data Supabase fallback (`lib/data/repositories/setall_repository.dart`)
- `getBalanceRawData`: on mobile, falls back to Supabase when local SQLite is empty
- `getGroupBalanceRawData`: same Supabase fallback — fixes "settled up" shown on fresh login

#### 7. `getGroupMembers` Supabase-first on mobile (`lib/data/repositories/setall_repository.dart`)
- Extracted `_getGroupMembersFromSupabase()` helper
- `getGroupMembers` now fetches fresh from Supabase when online, caches locally
- Fixes: split members not visible when creating expense; split-evenly assigning all debt to one user

#### 8. Auto-add split participants to `group_members` (`lib/data/repositories/setall_repository.dart`)
- Added `_ensureSplitParticipantsAreMembers()` called at end of `addExpense`
- Upserts all split participant IDs into `group_members` locally + Supabase
- Fixes: users split into an expense not appearing in group members list

#### 9. Per-expense converted amount in group screen (`lib/features/dashboard/presentation/screens/group_detail_screen.dart`)
- `_ExpenseTile` now shows `≈ GEL 45.20` subtitle when expense currency differs from user's default currency
- Uses `universalUsdAmount` × `rateToBaseProvider` for conversion

---

## TODO for Next Session

### Issue 1 — Nickname "already taken" (ghost rows, FK violation)
**Problem:** `DELETE FROM profiles WHERE is_ghost = TRUE` fails with:
```
ERROR 23503: update or delete on table "profiles" violates foreign key constraint
"pending_invites_invited_by_fkey" on table "pending_invites"
```
**Fix needed:** Delete `pending_invites` rows referencing the ghost profiles first, then delete ghost profiles. Correct SQL:
```sql
-- Step 1: delete pending_invites referencing ghost profiles
DELETE FROM public.pending_invites
WHERE invited_by IN (
  SELECT id FROM public.profiles WHERE is_ghost = TRUE
)
OR ghost_user_id IN (
  SELECT id FROM public.profiles WHERE is_ghost = TRUE
);

-- Step 2: now safe to delete ghost profiles
DELETE FROM public.profiles
WHERE is_ghost = TRUE
   OR id NOT IN (SELECT id FROM auth.users);
```

### Issue 2 — Google OAuth browser doesn't auto-close (loading limbo)
**Problem:** After successful Google auth the in-app browser stays open / shows loading.
**Suspects:**
- `supabase_flutter` v2 deep link interception not triggering on iOS simulator vs device
- May need to switch back to `LaunchMode.externalApplication` + rely on system to redirect
- Check if `FlutterDeepLinkingEnabled` needs to be in a different plist location
- Consider using `uni_links` / `app_links` package explicitly

### Issue 3 — Group invite search (email/nickname) broken
**Problem:** Search returns no results for both email and nickname in the invite/add member screen.
**Investigate:** `searchProfiles` RPC call in `addMemberByEmail` — check if the `search_profiles` Supabase function still exists and its parameter names haven't changed. May be a Supabase RPC signature mismatch.

### Issue 6 — "Settled up" persists until toggle/reopen after account switch
**Problem:** Even with the Supabase fallback, the balance provider is stale on first load after login.
**Fix needed:** In `app.dart` `_onAuthChange`, after invalidating providers on `signedIn`, also force an immediate re-fetch by calling `ref.read(groupBalanceSummaryProvider(groupId))` — or better, trigger `syncIfOnline` eagerly in the provider itself so the first build already has fresh data.

### Issue 7 (NEW) — Net balance not calculated between two users
**Problem:** If A paid 100 split with B, and B paid 100 split with A — each shows as 50 owed separately instead of netting to zero.
**Root cause:** `getGroupBalanceSummary` sums `youOwe` and `youAreOwed` independently and shows both. No netting/offsetting logic exists.
**Fix needed:** In `BalanceService.getGroupBalanceSummary`, compute net:
```dart
final net = youAreOwed - youOwe;
if (net > 0) → you are owed net amount
if (net < 0) → you owe |net| amount
if net == 0  → settled
```
Apply same netting to global `getBalanceSummary`.

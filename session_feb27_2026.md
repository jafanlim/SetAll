# SetAll – Full Dev Session Log
**Date:** Feb 27, 2026  
**Participants:** User (jafa) + Cascade AI

---

## Context Coming In

From the previous session, the following were already in progress or completed:
- Currency selection expansion
- Group edit/delete functionality
- "Who paid?" selector on expenses
- Dashboard currency conversion fixes
- "Clear all expenses" feature
- Stale profile data fix on user switch
- Supabase `handle_new_user` trigger fix (SQL provided)
- Deep linking setup for Google OAuth
- PKCE flow enabled

---

## Issues Reported at Start of Session

1. **Nickname "already taken"** — ghost profile rows surviving in Supabase
2. **Google OAuth in-app browser doesn't auto-close** after successful login
3. **User added to group during expense creation not visible** in group members screen
4. **Split evenly assigns all debt to one user** instead of dividing
5. **Group expense list** should show per-expense amount in user's default currency
6. **Group balance shows "settled up"** even when debt exists (after switching users)

---

## Work Done This Session

### Fix: `app.dart` — Stale profile data on user switch

Converted `SetAllApp` to `ConsumerStatefulWidget`. Subscribes to `Supabase.onAuthStateChange`. On different user sign-in: wipes SQLite cache + invalidates all providers. On sign-out: invalidates providers.

```dart
// lib/app.dart lines 1-87
class SetAllApp extends ConsumerStatefulWidget { ... }
class _SetAllAppState extends ConsumerState<SetAllApp> {
  StreamSubscription<AuthState>? _authSub;
  String? _lastUserId;

  Future<void> _onAuthChange(AuthState state) async {
    final newUid = state.session?.user.id;
    if (state.event == AuthChangeEvent.signedIn &&
        newUid != null && _lastUserId != null && newUid != _lastUserId) {
      await _wipeSQLiteCache();
      _invalidateAllProviders();
    }
    if (newUid != null) _lastUserId = newUid;
    if (state.event == AuthChangeEvent.signedOut) {
      _lastUserId = null;
      _invalidateAllProviders();
    }
  }
}
```

---

### Fix: Deep Linking for Google OAuth

**`ios/Runner/Info.plist`**
```xml
<key>FlutterDeepLinkingEnabled</key>
<true/>
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.jafa.setall</string>
    </array>
  </dict>
</array>
```

**`android/app/src/main/AndroidManifest.xml`**
```xml
<intent-filter>
  <action android:name="android.intent.action.VIEW"/>
  <category android:name="android.intent.category.DEFAULT"/>
  <category android:name="android.intent.category.BROWSABLE"/>
  <data android:scheme="com.jafa.setall"/>
</intent-filter>
```

**`lib/core/config/auth_config.dart`**
```dart
const String kAuthRedirectBaseUrl = 'com.jafa.setall://login-callback';
```

**`lib/features/auth/presentation/screens/login_screen.dart`**
```dart
// _authRedirectUrl() returns custom schemes verbatim
String? _authRedirectUrl() {
  if (!kAuthRedirectBaseUrl.startsWith('http')) return kAuthRedirectBaseUrl;
  return kAuthRedirectBaseUrl.endsWith('/') ? kAuthRedirectBaseUrl : '$kAuthRedirectBaseUrl/';
}

// signInWithOAuth
await Supabase.instance.client.auth.signInWithOAuth(
  OAuthProvider.google,
  redirectTo: redirectUrl,
  authScreenLaunchMode: LaunchMode.inAppWebView,
  queryParams: const {'prompt': 'select_account'},
);
```

**`lib/main.dart`** — PKCE flow added:
```dart
await Supabase.initialize(
  url: _supabaseUrl,
  anonKey: _supabaseAnonKey,
  authOptions: const FlutterAuthClientOptions(authFlowType: AuthFlowType.pkce),
);
```

---

### Fix: Issue 6 — Balance shows "settled up" despite debt

`getBalanceRawData` and `getGroupBalanceRawData` in `setall_repository.dart` now fall back to Supabase when local SQLite returns empty, so freshly-signed-in users see correct balances before background sync completes.

```dart
// getGroupBalanceRawData
final local = await _getGroupBalanceRawDataLocal(uid, groupId);
if (local != null) return local;
if (_client != null && await _isOnline) {
  return _getGroupBalanceRawDataWeb(uid, groupId);
}
return null;

// getBalanceRawData
final local = await _getBalanceRawDataLocal(uid);
if (local.youOwe.isNotEmpty || local.youAreOwed.isNotEmpty) return local;
if (_client != null && await _isOnline) return _getBalanceRawDataWeb(uid);
return local;
```

---

### Fix: Issues 3 & 4 — Members not visible / split evenly broken

**Root cause:** `getGroupMembers` only read local SQLite. For a freshly signed-in User B, or when User A hadn't synced yet, `_memberIds` had only 1 person → `splitEven` assigned 100% to that person.

**Fix 1:** `getGroupMembers` now fetches from Supabase when online, caches locally.

```dart
Future<List<ProfileModel>> getGroupMembers(String groupId) async {
  if (_client != null && await _isOnline) {
    try {
      final members = await _getGroupMembersFromSupabase(groupId);
      // cache locally...
      return members;
    } catch (_) {}
  }
  // offline fallback: local SQLite
}
```

**Fix 2:** After every `addExpense`, all split participant IDs are silently upserted into `group_members`:

```dart
await _ensureSplitParticipantsAreMembers(groupId, splits.map((s) => s.userId).toList());

Future<void> _ensureSplitParticipantsAreMembers(String groupId, List<String> userIds) async {
  for (final userId in userIds) {
    // insert into local SQLite with ConflictAlgorithm.ignore
    // upsert into Supabase group_members on conflict group_id,user_id
  }
}
```

---

### Fix: Issue 5 — Per-expense converted amount in group screen

`_ExpenseTile` in `group_detail_screen.dart` now shows `≈ GEL 45.20` subtitle when expense currency ≠ user's base currency.

```dart
final showConversion = expense.currency != baseCurrency && expense.universalUsdAmount != null;
final convertedAmount = showConversion && rateAsync?.valueOrNull != null
    ? ((Decimal.tryParse(expense.universalUsdAmount ?? '0') ?? Decimal.zero) *
        (Decimal.tryParse(rateAsync!.valueOrNull!) ?? Decimal.one))
        .round(scale: 2).toStringAsFixed(2)
    : null;

// In widget:
if (convertedAmount != null)
  Text('≈ $baseCurrency $convertedAmount', ...)
```

---

## Test Results from User

| # | Issue | Result |
|---|-------|--------|
| 1 | Nickname ghost rows | ❌ SQL failed: FK violation on `pending_invites` |
| 2 | OAuth browser auto-close | ❌ Still stuck in loading limbo |
| 3 | Member search in invite screen | ❌ Broken again — email + nickname both return nothing |
| 4 | Split evenly | ✅ Works |
| 5 | Per-expense converted amount | ✅ Works |
| 6 | Balance "settled up" | ⚠️ Fixed, but only after toggle/reopen — stale on first load |
| 7 | **NEW** Net balance not calculated | ❌ A owes 50 + B owes 50 shown separately instead of netting to 0 |

---

## TODO for Next Session

### Issue 1 — Ghost row delete (FK cascade fix)
Run this SQL instead:
```sql
-- Delete pending_invites rows that reference the ghost profiles first
DELETE FROM public.pending_invites
WHERE invited_by IN (SELECT id FROM public.profiles WHERE is_ghost = TRUE)
   OR ghost_user_id IN (SELECT id FROM public.profiles WHERE is_ghost = TRUE);

-- Now safe to delete the ghost profiles
DELETE FROM public.profiles
WHERE is_ghost = TRUE
   OR id NOT IN (SELECT id FROM auth.users);
```

### Issue 2 — OAuth browser doesn't close
- `FlutterDeepLinkingEnabled` added to Info.plist but not resolving
- Investigate: does the simulator handle custom URL schemes differently from device?
- Try `LaunchMode.externalApplication` as alternative
- Consider explicit `app_links` / `uni_links` package

### Issue 3 — Invite search (email/nickname) broken
- `searchProfiles` RPC likely has a signature mismatch or RLS blocking
- Inspect the Supabase `search_profiles` function and check what parameters it expects
- Check RLS policies on `profiles` table for authenticated users

### Issue 6 — Balance stale on first load after sign-in
- Provider invalidation in `_onAuthChange` triggers rebuild but data re-fetch is async
- Fix: In `app.dart`, after invalidating providers on `signedIn` event, eagerly trigger `syncIfOnline()` so first build gets fresh data
- Or: `groupBalanceSummaryProvider` should call `syncIfOnline` before reading local data (already does, but race condition on provider rebuild timing)

### Issue 7 (NEW) — Net balance not calculated
**Problem:** A paid 100 split with B → A is owed 50. B paid 100 split with A → B is owed 50. App shows both as separate streams. Should net to zero.

**Root cause:** `getGroupBalanceSummary` and `getBalanceSummary` sum `youOwe` and `youAreOwed` independently, no offset/netting.

**Fix plan in `BalanceService`:**
```dart
Future<BalanceSummary> getGroupBalanceSummary(String groupId) async {
  ...
  final owedRaw = await _sumInBase(raw.youAreOwed, baseCurrency);
  final oweRaw  = await _sumInBase(raw.youOwe,     baseCurrency);
  final net = owedRaw - oweRaw;
  return BalanceSummary(
    youAreOwed: net > Decimal.zero ? net.toStringAsFixed(2) : '0.00',
    youOwe:     net < Decimal.zero ? (-net).toStringAsFixed(2) : '0.00',
    currency: baseCurrency,
  );
}
```
Apply same netting to global `getBalanceSummary`.

---

## Files Modified This Session

| File | Change |
|------|--------|
| `lib/app.dart` | Auth state listener, SQLite wipe, provider invalidation |
| `lib/main.dart` | PKCE flow in both Supabase.initialize calls |
| `lib/core/config/auth_config.dart` | Set deep link redirect URL |
| `lib/features/auth/presentation/screens/login_screen.dart` | inAppWebView launch, PKCE redirect, account picker |
| `ios/Runner/Info.plist` | `com.jafa.setall` URL scheme + `FlutterDeepLinkingEnabled` |
| `android/app/src/main/AndroidManifest.xml` | `com.jafa.setall` intent-filter |
| `lib/data/repositories/setall_repository.dart` | Balance Supabase fallback, getGroupMembers Supabase-first, _ensureSplitParticipantsAreMembers, clearAllExpenses |
| `lib/features/dashboard/presentation/screens/group_detail_screen.dart` | Per-expense converted amount subtitle |
| `lib/features/settings/presentation/screens/settings_screen.dart` | "Clear all expenses" settings tile |

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/balance_service.dart';
import '../services/currency_service.dart';
import '../services/currency_sync_service.dart';
import '../services/sync_service.dart';
import '../../domain/services/settlement_engine.dart';
import '../../data/repositories/setall_repository.dart';
import '../../data/models/group_model.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/profile_model.dart';

// Supported currencies with display names and emoji flags.
// "Most used" group shown first in pickers.
const List<Map<String, String>> kMostUsedCurrencies = [
  {'code': 'USD', 'name': 'US Dollar',        'flag': '🇺🇸'},
  {'code': 'EUR', 'name': 'Euro',              'flag': '🇪🇺'},
  {'code': 'GBP', 'name': 'British Pound',     'flag': '🇬🇧'},
  {'code': 'GEL', 'name': 'Georgian Lari',     'flag': '🇬🇪'},
  {'code': 'AED', 'name': 'UAE Dirham',        'flag': '🇦🇪'},
];

const List<Map<String, String>> kAllSupportedCurrencies = [
  {'code': 'USD', 'name': 'US Dollar',        'flag': '🇺🇸'},
  {'code': 'EUR', 'name': 'Euro',              'flag': '🇪🇺'},
  {'code': 'GBP', 'name': 'British Pound',     'flag': '🇬🇧'},
  {'code': 'GEL', 'name': 'Georgian Lari',     'flag': '🇬🇪'},
  {'code': 'AED', 'name': 'UAE Dirham',        'flag': '🇦🇪'},
  {'code': 'TRY', 'name': 'Turkish Lira',      'flag': '🇹🇷'},
  {'code': 'PLN', 'name': 'Polish Złoty',      'flag': '🇵🇱'},
  {'code': 'CAD', 'name': 'Canadian Dollar',   'flag': '🇨🇦'},
  {'code': 'AUD', 'name': 'Australian Dollar', 'flag': '🇦🇺'},
  {'code': 'CHF', 'name': 'Swiss Franc',       'flag': '🇨🇭'},
  {'code': 'JPY', 'name': 'Japanese Yen',      'flag': '🇯🇵'},
  {'code': 'CNY', 'name': 'Chinese Yuan',      'flag': '🇨🇳'},
  {'code': 'INR', 'name': 'Indian Rupee',      'flag': '🇮🇳'},
  {'code': 'BRL', 'name': 'Brazilian Real',    'flag': '🇧🇷'},
  {'code': 'MXN', 'name': 'Mexican Peso',      'flag': '🇲🇽'},
  {'code': 'SEK', 'name': 'Swedish Krona',     'flag': '🇸🇪'},
  {'code': 'NOK', 'name': 'Norwegian Krone',   'flag': '🇳🇴'},
  {'code': 'DKK', 'name': 'Danish Krone',      'flag': '🇩🇰'},
  {'code': 'SGD', 'name': 'Singapore Dollar',  'flag': '🇸🇬'},
  {'code': 'HKD', 'name': 'Hong Kong Dollar',  'flag': '🇭🇰'},
];

// ---------------------------------------------------------------------------
// Infrastructure providers
// ---------------------------------------------------------------------------

/// Supabase-backed rate sync service (single source of truth for rates).
final currencySyncServiceProvider = Provider<CurrencySyncService>((ref) {
  try {
    return CurrencySyncService(client: Supabase.instance.client);
  } catch (_) {
    return CurrencySyncService();
  }
});

/// Currency service: manual override > Supabase DB rates > Frankfurter API.
final currencyServiceProvider = Provider<CurrencyService>((ref) {
  return CurrencyService(syncService: ref.watch(currencySyncServiceProvider));
});

final setAllRepositoryProvider = Provider<SetAllRepository>((ref) {
  try {
    return SetAllRepository(
      client: Supabase.instance.client,
      currencyService: ref.watch(currencyServiceProvider),
    );
  } catch (_) {
    return SetAllRepository(
      currencyService: ref.watch(currencyServiceProvider),
    );
  }
});

/// Standalone sync coordinator. Call [SyncService.performFullSync] to trigger
/// a full push-then-pull cycle outside the data-fetch loop.
final syncServiceProvider = Provider<SyncService>((ref) {
  try {
    return SyncService(
      repository: ref.watch(setAllRepositoryProvider),
      client: Supabase.instance.client,
    );
  } catch (_) {
    return SyncService(
      repository: ref.watch(setAllRepositoryProvider),
    );
  }
});

/// Balance service: correct multi-currency conversion using [baseAmountAtEntry].
final balanceServiceProvider = Provider<BalanceService>((ref) {
  return BalanceService(
    repository: ref.watch(setAllRepositoryProvider),
    currencyService: ref.watch(currencyServiceProvider),
  );
});

// ---------------------------------------------------------------------------
// Current user
// ---------------------------------------------------------------------------

final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(setAllRepositoryProvider).currentUserId;
});

// ---------------------------------------------------------------------------
// Balance
// ---------------------------------------------------------------------------

/// Global net balance lazily localized to the user's [default_currency].
///
/// Watches [baseCurrencyProvider] and [currencyServiceProvider] so Riverpod
/// automatically invalidates and re-fetches this provider whenever the user
/// changes their preferred currency. Conversion math uses [Decimal] (no
/// floating-point rounding errors) via [BalanceService.getBalanceSummary].
final balanceSummaryProvider = FutureProvider<BalanceSummary>((ref) async {
  ref.watch(baseCurrencyProvider);
  ref.watch(currencyServiceProvider);
  // Watch the groups stream so the total refreshes when sync pulls new data.
  ref.watch(myGroupsProvider);
  return ref
      .watch(balanceServiceProvider)
      .getBalanceSummary();
});

/// Group-scoped balance lazily localized to the user's [default_currency].
///
/// Watches [baseCurrencyProvider] and [currencyServiceProvider] so Riverpod
/// automatically invalidates and re-fetches this provider whenever the user
/// changes their preferred currency. Conversion math uses [Decimal] (no
/// floating-point rounding errors) via [BalanceService.getGroupBalanceSummary].
final groupBalanceSummaryProvider =
    FutureProvider.family<BalanceSummary, String>((ref, groupId) async {
  final targetCurrency = await ref.watch(baseCurrencyProvider.future);
  ref.watch(currencyServiceProvider);
  // Watch the expense stream so this provider recomputes automatically
  // whenever a sync pull or local write changes expenses — no manual
  // ref.invalidate(groupBalanceSummaryProvider) needed anywhere.
  ref.watch(groupExpensesProvider(groupId));
  return ref
      .watch(balanceServiceProvider)
      .getGroupBalanceSummary(groupId, targetCurrency: targetCurrency);
});

// ---------------------------------------------------------------------------
// Groups & expenses
// ---------------------------------------------------------------------------

/// Normal (non-direct) groups for the Groups/Dashboard tab.
/// StreamProvider — emits immediately from SQLite, then re-emits on every
/// local write or sync completion. No manual invalidation needed.
final myGroupsProvider = StreamProvider<List<GroupModel>>((ref) {
  return ref.watch(setAllRepositoryProvider).watchGroups();
});

/// Direct (1-on-1 friend) groups for the Friends tab.
final friendGroupsProvider = FutureProvider<List<GroupModel>>((ref) async {
  return ref.watch(setAllRepositoryProvider).getDirectGroups();
});

final recentExpensesProvider = FutureProvider<List<ExpenseModel>>((ref) async {
  return ref.watch(setAllRepositoryProvider).getRecentExpenses();
});

/// Expenses for a specific group.
/// StreamProvider.family — re-emits automatically on any local change.
final groupExpensesProvider =
    StreamProvider.family<List<ExpenseModel>, String>((ref, groupId) {
  return ref.watch(setAllRepositoryProvider).watchGroupExpenses(groupId);
});

final groupMembersProvider =
    FutureProvider.family<List<ProfileModel>, String>((ref, groupId) async {
  return ref.watch(setAllRepositoryProvider).getGroupMembers(groupId);
});

/// Creator ID for a given group. Used to gate member-removal UI.
final groupCreatorProvider =
    FutureProvider.family<String?, String>((ref, groupId) async {
  return ref.watch(setAllRepositoryProvider).getGroupCreatorId(groupId);
});

// ---------------------------------------------------------------------------
// Debt simplification
// ---------------------------------------------------------------------------

/// Simplified debts for a group, amounts expressed in the user's base currency.
final simplifiedDebtsProvider =
    FutureProvider.family<List<SettlementTransaction>, String>((ref, groupId) async {
  final baseCurrency = await ref.watch(baseCurrencyProvider.future);
  return ref
      .watch(setAllRepositoryProvider)
      .getSimplifiedDebts(groupId, baseCurrency: baseCurrency);
});

// ---------------------------------------------------------------------------
// Currency helpers
// ---------------------------------------------------------------------------

/// User's base currency (from profile). Defaults to USD.
final baseCurrencyProvider = FutureProvider<String>((ref) async {
  return ref.watch(balanceServiceProvider).getBaseCurrency();
});

/// Live display rate: 1 USD → [toCurrency]. Used for UI preview only.
final exchangeRateProvider =
    FutureProvider.family<String, String>((ref, toCurrency) async {
  if (toCurrency == 'USD') return '1';
  final svc = ref.watch(currencyServiceProvider);
  final rate = await svc.getRate('USD', toCurrency);
  return rate.toStringAsFixed(4);
});

/// Rate from [from] currency to user's [base] currency (for conversion preview).
final rateToBaseProvider =
    FutureProvider.family<String, ({String from, String base})>(
        (ref, params) async {
  if (params.from == params.base) return '1';
  final svc = ref.watch(currencyServiceProvider);
  final rate = await svc.getRate(params.from, params.base);
  return rate.toStringAsFixed(6);
});

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

/// Current user's full profile (includes nickname, avatarUrl, isGhost).
final currentProfileProvider = FutureProvider<ProfileModel?>((ref) async {
  return ref.watch(setAllRepositoryProvider).getCurrentUserProfile();
});

// ---------------------------------------------------------------------------
// User search
// ---------------------------------------------------------------------------

/// Real-time user search by email or nickname. Pass the search query string.
/// Returns empty list for queries shorter than 2 characters.
final searchUsersProvider =
    FutureProvider.family<List<ProfileModel>, String>((ref, query) async {
  if (query.trim().length < 2) return [];
  return ref.watch(setAllRepositoryProvider).searchUsers(query);
});

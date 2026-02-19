import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/balance_service.dart';
import '../services/currency_service.dart';
import '../services/currency_sync_service.dart';
import '../utils/debt_simplification_engine.dart';
import '../../data/repositories/setall_repository.dart';
import '../../data/models/group_model.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/profile_model.dart';

// ---------------------------------------------------------------------------
// Infrastructure providers
// ---------------------------------------------------------------------------

final setAllRepositoryProvider = Provider<SetAllRepository>((ref) {
  try {
    return SetAllRepository(client: Supabase.instance.client);
  } catch (_) {
    return SetAllRepository();
  }
});

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

/// Global net balance in user's base currency. Uses BalanceService for
/// correct multi-currency conversion with [baseAmountAtEntry] fast path.
final balanceSummaryProvider = FutureProvider<BalanceSummary>((ref) async {
  return ref.watch(balanceServiceProvider).getBalanceSummary();
});

/// Group-scoped balance in base currency.
final groupBalanceSummaryProvider =
    FutureProvider.family<BalanceSummary, String>((ref, groupId) async {
  return ref.watch(balanceServiceProvider).getGroupBalanceSummary(groupId);
});

// ---------------------------------------------------------------------------
// Groups & expenses
// ---------------------------------------------------------------------------

final myGroupsProvider = FutureProvider<List<GroupModel>>((ref) async {
  return ref.watch(setAllRepositoryProvider).getMyGroups();
});

final recentExpensesProvider = FutureProvider<List<ExpenseModel>>((ref) async {
  return ref.watch(setAllRepositoryProvider).getRecentExpenses();
});

final groupExpensesProvider =
    FutureProvider.family<List<ExpenseModel>, String>((ref, groupId) async {
  return ref.watch(setAllRepositoryProvider).getExpensesForGroup(groupId);
});

final groupMembersProvider =
    FutureProvider.family<List<ProfileModel>, String>((ref, groupId) async {
  return ref.watch(setAllRepositoryProvider).getGroupMembers(groupId);
});

// ---------------------------------------------------------------------------
// Debt simplification
// ---------------------------------------------------------------------------

final simplifiedDebtsProvider =
    FutureProvider.family<List<SimplifiedDebt>, String>((ref, groupId) async {
  return ref.watch(setAllRepositoryProvider).getSimplifiedDebts(groupId);
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

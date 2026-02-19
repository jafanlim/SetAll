import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/services/balance_service.dart';
import '../../core/services/currency_service.dart';
import '../../core/utils/debt_simplification_engine.dart';
import '../../data/repositories/setall_repository.dart';
import '../../data/models/group_model.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/profile_model.dart';
import '../../domain/entities/expense.dart';

final setAllRepositoryProvider = Provider<SetAllRepository>((ref) {
  try {
    final client = Supabase.instance.client;
    return SetAllRepository(client: client);
  } catch (_) {
    return SetAllRepository();
  }
});

/// Current user id (null if not configured or not signed in).
final currentUserIdProvider = Provider<String?>((ref) {
  return ref.watch(setAllRepositoryProvider).currentUserId;
});

/// Balance service: multi-currency conversion to base currency.
final balanceServiceProvider = Provider<BalanceService>((ref) {
  return BalanceService(
    repository: ref.watch(setAllRepositoryProvider),
    currencyService: ref.watch(currencyServiceProvider),
  );
});

/// Balance summary (global net in base currency). Uses BalanceService for correct conversion.
final balanceSummaryProvider = FutureProvider<BalanceSummary>((ref) async {
  return ref.watch(balanceServiceProvider).getBalanceSummary();
});

/// User's groups from Supabase.
final myGroupsProvider = FutureProvider<List<GroupModel>>((ref) async {
  final repo = ref.watch(setAllRepositoryProvider);
  return repo.getMyGroups();
});

/// Recent expenses across all groups.
final recentExpensesProvider = FutureProvider<List<ExpenseModel>>((ref) async {
  final repo = ref.watch(setAllRepositoryProvider);
  return repo.getRecentExpenses();
});

/// Expenses for a specific group.
final groupExpensesProvider = FutureProvider.family<List<ExpenseModel>, String>((ref, groupId) async {
  final repo = ref.watch(setAllRepositoryProvider);
  return repo.getExpensesForGroup(groupId);
});

/// Members of a group.
final groupMembersProvider = FutureProvider.family<List<ProfileModel>, String>((ref, groupId) async {
  final repo = ref.watch(setAllRepositoryProvider);
  return repo.getGroupMembers(groupId);
});

/// Group-scoped balance in base currency.
final groupBalanceSummaryProvider = FutureProvider.family<BalanceSummary, String>((ref, groupId) async {
  return ref.watch(balanceServiceProvider).getGroupBalanceSummary(groupId);
});

/// Simplified debts for a group (minimal transactions, group-scoped).
final simplifiedDebtsProvider = FutureProvider.family<List<SimplifiedDebt>, String>((ref, groupId) async {
  final repo = ref.watch(setAllRepositoryProvider);
  return repo.getSimplifiedDebts(groupId);
});

/// Currency service for live rates and manual override (e.g. bank fees).
final currencyServiceProvider = Provider<CurrencyService>((ref) {
  return CurrencyService();
});

/// Live rate 1 USD -> [toCurrency]. Refreshes when [toCurrency] changes.
final exchangeRateProvider = FutureProvider.family<String, String>((ref, toCurrency) async {
  if (toCurrency == 'USD') return '1';
  final svc = ref.watch(currencyServiceProvider);
  final rate = await svc.getRate('USD', toCurrency);
  return rate.toStringAsFixed(4);
});

/// User's base currency for balance (from profile). Default USD.
final baseCurrencyProvider = FutureProvider<String>((ref) async {
  return ref.watch(balanceServiceProvider).getBaseCurrency();
});

/// Rate from [fromCurrency] to base (for converted amount preview).
final rateToBaseProvider = FutureProvider.family<String, ({String from, String base})>((ref, params) async {
  if (params.from == params.base) return '1';
  final svc = ref.watch(currencyServiceProvider);
  final rate = await svc.getRate(params.from, params.base);
  return rate.toStringAsFixed(6);
});

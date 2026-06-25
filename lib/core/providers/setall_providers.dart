import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart' show Locale;
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
import '../../data/models/wallet_entry_model.dart';
import '../../data/models/ai_insight_model.dart';
import '../../features/wallet/data/ingest_row.dart';
import '../../features/wallet/data/ingest_service.dart';
import '../../features/recurring/data/recurring_candidate.dart';
import '../../features/recurring/data/recurring_detection_service.dart';
import '../../domain/entities/activity_event.dart';
export '../constants/currencies.dart';

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
  // Watch group list so balance recomputes when settled_at changes.
  ref.watch(myGroupsProvider);
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

/// Recent expenses across all groups.
/// Watches [myGroupsProvider] so it auto-refreshes whenever a group is
/// created, deleted, or updated — no manual invalidation needed.
final recentExpensesProvider = FutureProvider<List<ExpenseModel>>((ref) async {
  ref.watch(myGroupsProvider);
  return ref.watch(setAllRepositoryProvider).getRecentExpenses();
});

/// Personal (wallet) expenses — StreamProvider so the Wallet screen
/// auto-refreshes whenever a sync pull or local write calls _notify(),
/// exactly like [groupExpensesProvider] for group expenses.
final personalExpensesProvider = StreamProvider<List<ExpenseModel>>((ref) {
  return ref.watch(setAllRepositoryProvider).watchPersonalExpenses();
});

/// Wallet entries ledger stream — dedicated personal finance table (schema v28).
final walletEntriesProvider = StreamProvider<List<WalletEntryModel>>((ref) {
  return ref.watch(setAllRepositoryProvider).watchWalletEntries();
});

/// Wallet entry totals (income / spend / net) in the user's base currency.
final walletEntryTotalsProvider =
    FutureProvider<({Decimal income, Decimal spend, Decimal net})>((ref) async {
  final baseCurrency = await ref.watch(baseCurrencyProvider.future);
  ref.watch(walletEntriesProvider);
  return ref
      .watch(setAllRepositoryProvider)
      .getWalletEntryTotals(baseCurrency: baseCurrency);
});

/// Unified activity feed stream: group + personal expenses, sorted newest-first.
final activityFeedProvider = StreamProvider<List<ExpenseModel>>((ref) {
  return ref.watch(setAllRepositoryProvider).watchActivityFeed();
});

/// Omni activity feed: polymorphic [ActivityEvent] stream (expenses, group creation, settlements).
final omniActivityProvider = StreamProvider<List<ActivityEvent>>((ref) {
  return ref.watch(setAllRepositoryProvider).watchOmniActivity();
});

/// Personal wallet balance, converted to the user's base currency.
/// Watches [personalExpensesProvider] stream so it recomputes automatically
/// on every sync pull or local write — no manual invalidation needed.
final walletBalanceProvider = FutureProvider<String>((ref) async {
  // Watch base currency — invalidates this provider when the user changes it.
  final baseCurrency = await ref.watch(baseCurrencyProvider.future);
  // Watch both expense streams — recomputes on every sync/write.
  ref.watch(personalExpensesProvider);
  ref.watch(walletEntriesProvider);
  final balance = await ref
      .watch(setAllRepositoryProvider)
      .getWalletOnlyBalance(baseCurrency: baseCurrency);
  return balance.toStringAsFixed(2);
});

/// Exchange rate: 1 USD → baseCurrency. Used by the wallet screen to convert
/// universalUsdAmount to the user's base currency for category annotations.
/// Returns Decimal.one when baseCurrency is already USD.
final usdToBaseCurrencyRateProvider = FutureProvider<Decimal>((ref) async {
  final baseCurrency = await ref.watch(baseCurrencyProvider.future);
  if (baseCurrency == 'USD') return Decimal.one;
  return ref.watch(currencyServiceProvider).getRate('USD', baseCurrency);
});

/// Wallet income, expenses, and net — all separately, in the user's base
/// currency. Drives the Income / Expenses pills in WalletHero.
final walletTotalsProvider =
    FutureProvider<({Decimal income, Decimal spend, Decimal net})>((ref) async {
  final baseCurrency = await ref.watch(baseCurrencyProvider.future);
  ref.watch(personalExpensesProvider);
  return ref
      .watch(setAllRepositoryProvider)
      .getWalletTotals(baseCurrency: baseCurrency);
});

// ---------------------------------------------------------------------------
// Master balance — combines personal wallet cash + shared group position
// ---------------------------------------------------------------------------

/// Aggregated financial snapshot for the Dashboard Control Center.
class MasterBalance {
  const MasterBalance({
    required this.netWorth,
    required this.walletCash,
    required this.sharedOwed,
    required this.sharedOwe,
    required this.currency,
  });

  /// (walletCash) + (sharedOwed - sharedOwe)
  final Decimal netWorth;

  /// Personal income − personal spend (wallet).
  final Decimal walletCash;

  /// Total owed to you across all groups.
  final Decimal sharedOwed;

  /// Total you owe across all groups.
  final Decimal sharedOwe;

  final String currency;

  Decimal get sharedNet => sharedOwed - sharedOwe;
  bool get netWorthPositive => netWorth >= Decimal.zero;
}

/// Combines [walletBalanceProvider] and [balanceSummaryProvider] into a single
/// [MasterBalance] snapshot used by the Dashboard Control Center hero card.
final masterBalanceProvider = FutureProvider<MasterBalance>((ref) async {
  final walletStr = await ref.watch(walletBalanceProvider.future);
  final summary   = await ref.watch(balanceSummaryProvider.future);

  final wallet  = Decimal.tryParse(walletStr)       ?? Decimal.zero;
  final owed    = Decimal.tryParse(summary.youAreOwed) ?? Decimal.zero;
  final owe     = Decimal.tryParse(summary.youOwe)     ?? Decimal.zero;

  return MasterBalance(
    netWorth:    wallet + owed - owe,
    walletCash:  wallet,
    sharedOwed:  owed,
    sharedOwe:   owe,
    currency:    summary.currency.isEmpty ? 'USD' : summary.currency,
  );
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

/// Batch-loads all members for every currently visible group in a single
/// Supabase round-trip (2 queries total instead of 2N).
/// The groups list screen watches this instead of [groupMembersProvider]
/// per tile to eliminate N+1 slowness.
final allGroupMembersBatchProvider =
    FutureProvider<Map<String, List<ProfileModel>>>((ref) async {
  final groupsAsync = ref.watch(myGroupsProvider);
  final groups      = groupsAsync.asData?.value ?? [];
  final groupIds    = groups.map((g) => g.id).toList();
  if (groupIds.isEmpty) return {};
  return ref.watch(setAllRepositoryProvider).getGroupMembersBatch(groupIds);
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

/// Smart custom categories for the current user.
final userCategoriesProvider = FutureProvider<List<Map<String, String>>>((ref) async {
  return ref.watch(setAllRepositoryProvider).getUserCategories();
});

/// All unique profiles from every group the current user belongs to.
/// Used for fast-add member suggestions in group create/edit screens.
/// Uses [getGroupMembersBatch] to avoid N+1 Supabase queries.
final allGroupMembersProvider = FutureProvider<List<ProfileModel>>((ref) async {
  final groups = await ref.watch(myGroupsProvider.future);
  final repo   = ref.watch(setAllRepositoryProvider);
  final uid    = await repo.ensureUser();
  final batchMap = await repo.getGroupMembersBatch(
    groups.map((g) => g.id).toList(),
  );
  final seen   = <String>{};
  final result = <ProfileModel>[];
  for (final members in batchMap.values) {
    for (final m in members) {
      if (m.id != uid && seen.add(m.id)) result.add(m);
    }
  }
  result.sort((a, b) => a.name.compareTo(b.name));
  return result;
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

// ---------------------------------------------------------------------------
// FEAT-19: AI Insights
// ---------------------------------------------------------------------------

/// Latest AI weekly/monthly/on_demand insights for the current user.
final aiInsightsProvider = FutureProvider<List<AiInsightModel>>((ref) async {
  final uid = Supabase.instance.client.auth.currentUser?.id;
  if (uid == null) return [];
  try {
    final rows = await Supabase.instance.client
        .from('ai_insights')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false)
        .limit(5) as List;
    return rows.map((r) => AiInsightModel.fromMap(r as Map<String, dynamic>)).toList();
  } catch (_) {
    return [];
  }
});

// ---------------------------------------------------------------------------
// setall-ingestion-pipeline providers
// ---------------------------------------------------------------------------

/// IngestService singleton — depends on repository for getUserCategories + upsertWalletEntry.
final ingestServiceProvider = Provider<IngestService>((ref) {
  return IngestService(repository: ref.watch(setAllRepositoryProvider));
});

/// Mutable list of pending IngestRows for the review screen.
/// Notifier exposes mutation helpers (approve, reject, edit, setAll).
class IngestNotifier extends Notifier<List<IngestRow>> {
  @override
  List<IngestRow> build() => [];

  void setRows(List<IngestRow> rows) => state = List.unmodifiable(rows);

  void clear() => state = [];

  void approveAll() {
    state = List.unmodifiable(
      state.map((r) => r.status == IngestRowStatus.rejected
          ? r
          : r.copyWith(status: IngestRowStatus.approved)).toList(),
    );
  }

  void toggleStatus(String id) {
    state = List.unmodifiable(state.map((r) {
      if (r.id != id) return r;
      final next = r.status == IngestRowStatus.approved
          ? IngestRowStatus.rejected
          : r.status == IngestRowStatus.rejected
              ? IngestRowStatus.pending
              : IngestRowStatus.approved;
      return r.copyWith(status: next);
    }).toList());
  }

  void editRow(String id, {String? description, String? category, bool? isIncome}) {
    state = List.unmodifiable(state.map((r) {
      if (r.id != id) return r;
      return r.copyWith(
        description: description,
        category:    category,
        isIncome:    isIncome,
      );
    }).toList());
  }
}

final ingestRowsProvider =
    NotifierProvider<IngestNotifier, List<IngestRow>>(IngestNotifier.new);

/// Tracks the active app locale so providers without BuildContext can read languageCode.
/// Updated by adaptive_shell on every build.
final localeProvider = StateProvider<Locale>((ref) => const Locale('en'));

/// True while a screen (wallet / groups) is in edit mode.
/// Shell reads this to hide the voice FAB, matching the screen's own FAB hide logic.
final screenEditModeProvider = StateProvider<bool>((ref) => false);

// setall-recurring-detection providers
// ---------------------------------------------------------------------------

/// Runs heuristic detection over all user-paid expenses (personal + group)
/// and returns candidates not already in confirmed recurring_rules.
/// Uses FutureProvider to properly await the Supabase fetch before running
/// detection — avoids the empty-initial-value timing issue with StreamProvider.
final recurringCandidatesProvider =
    FutureProvider<List<RecurringCandidate>>((ref) async {
  final repo = ref.watch(setAllRepositoryProvider);
  final expenses = await repo.getAllPayerExpenses();
  return RecurringDetectionService.detect(expenses);
});

/// Confirmed recurring rules from Supabase.
final recurringRulesProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  return ref.watch(setAllRepositoryProvider).getRecurringRules();
});

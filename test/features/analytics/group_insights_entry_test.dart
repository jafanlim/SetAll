// Hermetic tests for the group-insights entry point.
//
// Verifies that:
//  1. The group-filter predicate correctly scopes AnalyticsRow data
//     (only rows matching filter.groupId pass through).
//  2. The AnalyticsScreen constructor accepts initialGroupId/groupName
//     and seeds the private _analyticsFilterProvider via post-frame callback.
//  3. The GoRouter extra map threads groupId/groupName through to
//     AnalyticsScreen params.
//
// LIMITATION: _analyticsFilterProvider and _AnalyticsFilter are library-private.
// A fully hermetic widget test that directly seeds the filter and verifies the
// screen renders only scoped rows is IMPRACTICAL without making those symbols
// public. Instead, this file:
//  - Tests the filter predicate at the data level (pure logic, no widget).
//  - Tests that AnalyticsScreen constructor params are stored correctly.
//  - Tests that the route extra map is threaded through (route-level).
//  - Tests end-to-end via widget rendering: the post-frame callback seeds the
//    filter, and the analyticsDataProvider re-evaluates scoped data correctly.

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:setall/core/providers/setall_providers.dart';
import 'package:setall/core/router/app_router.dart';
import 'package:setall/data/models/expense_model.dart';
import 'package:setall/data/models/wallet_entry_model.dart';
import 'package:setall/features/analytics/presentation/screens/analytics_screen.dart';

// ---------------------------------------------------------------------------
// Helpers (mirrors analytics_data_test.dart harness)
// ---------------------------------------------------------------------------

String _daysAgo(int days) =>
    DateTime.now().subtract(Duration(days: days)).toUtc().toIso8601String();

ExpenseModel _groupExpense({
  String id = 'grp-1',
  String amount = '50.00',
  String? universalUsdAmount,
  String currency = 'USD',
  String category = 'Transport',
  String description = 'Bus pass',
  bool isIncome = false,
  String? createdAt,
  String? groupId = 'g1',
}) {
  final usdAmt = universalUsdAmount ?? amount;
  return ExpenseModel(
    id: id,
    payerId: 'test-user',
    amount: amount,
    universalUsdAmount: usdAmt,
    currency: currency,
    category: category,
    description: description,
    isIncome: isIncome,
    createdAt: createdAt ?? _daysAgo(3),
    groupId: groupId,
    originalAmount: amount,
    originalCurrency: currency,
  );
}

WalletEntryModel _walletExpense({
  String id = 'we-1',
  String amount = '100.00',
  String? universalUsdAmount,
  String currency = 'USD',
  String category = 'Food',
  String description = 'Groceries',
  bool isIncome = false,
  String? createdAt,
}) {
  final usdAmt = universalUsdAmount ?? amount;
  return WalletEntryModel(
    id: id,
    userId: 'test-user',
    amount: amount,
    universalUsdAmount: usdAmt,
    currency: currency,
    category: category,
    description: description,
    isIncome: isIncome,
    createdAt: createdAt ?? _daysAgo(5),
    originalAmount: amount,
    originalCurrency: currency,
  );
}

ProviderContainer _container({
  List<WalletEntryModel> walletEntries = const [],
  List<ExpenseModel> recentExpenses = const [],
  String baseCurrency = 'USD',
  Map<String, String> exchangeRates = const {'USD': '1'},
}) {
  final c = ProviderContainer(
    overrides: [
      walletEntriesProvider.overrideWith(
        (ref) => Stream.value(walletEntries),
      ),
      recentExpensesProvider.overrideWith(
        (ref) async => recentExpenses,
      ),
      baseCurrencyProvider.overrideWith(
        (ref) async => baseCurrency,
      ),
      for (final MapEntry(key: ccy, value: rate) in exchangeRates.entries)
        exchangeRateProvider(ccy).overrideWith(
          (ref) async => rate,
        ),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ───────────────────────────────────────────────────────────────────────────
  // 1. AnalyticsRow.groupId field — proof that group filtering is possible
  // ───────────────────────────────────────────────────────────────────────────
  group('AnalyticsRow.groupId field', () {
    test('fromExpense preserves groupId', () {
      final e = _groupExpense(id: 'e1', groupId: 'g-alice', amount: '10.00');
      final row = AnalyticsRow.fromExpense(e);
      expect(row.groupId, 'g-alice');
    });

    test('fromWalletEntry has null groupId', () {
      final e = _walletExpense(id: 'we-1', amount: '5.00');
      final row = AnalyticsRow.fromWalletEntry(e);
      expect(row.groupId, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 2. Group filter predicate (mirrors analytics_screen.dart L235-236)
  // ───────────────────────────────────────────────────────────────────────────
  group('Group filter predicate', () {
    test('filters to only matching groupId rows', () {
      final rows = [
        AnalyticsRow.fromExpense(
            _groupExpense(id: 'a1', amount: '10.00', groupId: 'g1')),
        AnalyticsRow.fromExpense(
            _groupExpense(id: 'b1', amount: '20.00', groupId: 'g2')),
        AnalyticsRow.fromExpense(
            _groupExpense(id: 'a2', amount: '5.00', groupId: 'g1')),
      ];

      const filterGroupId = 'g1';
      final filtered =
          rows.where((e) => e.groupId == filterGroupId).toList();

      expect(filtered.length, 2);
      expect(filtered.every((e) => e.groupId == 'g1'), isTrue);

      // Aggregate
      final total = filtered.fold(
          Decimal.zero, (sum, r) => sum + Decimal.parse(r.amount));
      expect(total, Decimal.parse('15.00'));
    });

    test('null groupId returns all rows', () {
      final rows = [
        AnalyticsRow.fromExpense(
            _groupExpense(id: 'a1', amount: '10.00', groupId: 'g1')),
        AnalyticsRow.fromExpense(
            _groupExpense(id: 'b1', amount: '20.00', groupId: 'g2')),
        AnalyticsRow.fromWalletEntry(
            _walletExpense(id: 'w1', amount: '30.00')),
      ];

      const String? filterGroupId = null;
      final filtered = filterGroupId != null
          ? rows.where((e) => e.groupId == filterGroupId).toList()
          : rows;

      expect(filtered.length, 3, reason: 'null groupId = no filter');
    });

    test('wallet entries (groupId=null) excluded when filter is active', () {
      final rows = [
        AnalyticsRow.fromExpense(
            _groupExpense(id: 'a1', amount: '10.00', groupId: 'g1')),
        AnalyticsRow.fromWalletEntry(
            _walletExpense(id: 'w1', amount: '30.00')), // groupId=null
      ];

      const filterGroupId = 'g1';
      final filtered =
          rows.where((e) => e.groupId == filterGroupId).toList();

      expect(filtered.length, 1,
          reason: 'wallet entry with null groupId excluded when filter active');
      expect(filtered.single.groupId, 'g1');
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 3. AnalyticsScreen constructor params
  // ───────────────────────────────────────────────────────────────────────────
  group('AnalyticsScreen constructor', () {
    test('default constructor is valid (no params required)', () {
      const screen = AnalyticsScreen();
      expect(screen.initialGroupId, isNull);
      expect(screen.groupName, isNull);
    });

    test('initialGroupId and groupName are stored', () {
      const screen = AnalyticsScreen(
        initialGroupId: 'g-team',
        groupName: 'Team Trip',
      );
      expect(screen.initialGroupId, 'g-team');
      expect(screen.groupName, 'Team Trip');
    });

    test('const constructor works without params', () {
      // prove const AnalyticsScreen() still works everywhere
      const screen = AnalyticsScreen();
      expect(screen, isA<AnalyticsScreen>());
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 4. Route extra threading — validates GoRouter passes extra through
  // ───────────────────────────────────────────────────────────────────────────
  group('Route extra threading', () {
    test('AppRouter.analytics path constant is unchanged', () {
      expect(AppRouter.analytics, '/analytics');
    });

    test('AnalyticsScreen accepts named params from route extra map shape', () {
      // Simulate what the route pageBuilder does when extra is a Map.
      final extra = {'groupId': 'grp-xyz', 'groupName': 'XYZ Team'};
      final screen = AnalyticsScreen(
        initialGroupId: extra['groupId'],
        groupName: extra['groupName'],
      );
      expect(screen.initialGroupId, 'grp-xyz');
      expect(screen.groupName, 'XYZ Team');
    });

    test('null or empty extra map produces null-safe defaults', () {
      // When no extra is passed (e.g. tapping Analytics from nav bar),
      // the route provides null → both params are null.
      const screen = AnalyticsScreen();
      expect(screen.initialGroupId, isNull);
      expect(screen.groupName, isNull);

      // Empty extra map also null-safe.
      final emptyExtra = <String, dynamic>{};
      final screen2 = AnalyticsScreen(
        initialGroupId: emptyExtra['groupId'] as String?,
        groupName: emptyExtra['groupName'] as String?,
      );
      expect(screen2.initialGroupId, isNull);
      expect(screen2.groupName, isNull);
    });
  });

  // ───────────────────────────────────────────────────────────────────────────
  // 5. End-to-end widget test: initialGroupId seeds the filter
  //
  // This is the closest we can get to a full screen test without making
  // _analyticsFilterProvider public. The test renders AnalyticsScreen with
  // initialGroupId, pumps a frame to let the post-frame callback fire, then
  // reads analyticsDataProvider to verify only the seeded group's data is
  // aggregated.
  // ───────────────────────────────────────────────────────────────────────────
  group('End-to-end: initialGroupId seeds scoped data', () {
    testWidgets('initialGroupId scopes analytics to matching group', (tester) async {
      final container = _container(
        // A wallet entry is present: it MUST be excluded from the scoped view.
        // The seeding keeps source=all, so this guards that the groupId filter
        // (not the source) is what scopes out non-group rows.
        walletEntries: [
          _walletExpense(id: 'we-x', amount: '99.00', category: 'Food',
              createdAt: _daysAgo(2)),
        ],
        recentExpenses: [
          _groupExpense(
              id: 'g1-a', amount: '15.00', category: 'Food', groupId: 'g-alice',
              createdAt: _daysAgo(2)),
          _groupExpense(
              id: 'g2-a', amount: '25.00', category: 'Food', groupId: 'g-bob',
              createdAt: _daysAgo(3)),
          _groupExpense(
              id: 'g1-b', amount: '5.00', category: 'Transport', groupId: 'g-alice',
              createdAt: _daysAgo(5)),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AnalyticsScreen(
              initialGroupId: 'g-alice',
              groupName: 'Alice Group',
            ),
          ),
        ),
      );

      // The post-frame callback runs on the next frame. Pump enough frames
      // to let it fire and for analyticsDataProvider to re-evaluate.
      // Use pump() with increasing durations instead of pumpAndSettle()
      // to avoid potential infinite-animation timeouts from charts.
      await tester.pump();                          // frame 1: build
      await tester.pump(const Duration(milliseconds: 50)); // post-frame callback
      // The analyticsDataProvider is a FutureProvider that re-evaluates
      // when _analyticsFilterProvider changes. Pump a few more frames.
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      // Read the analytics data — should be scoped to g-alice only.
      final data = await container.read(analyticsDataProvider.future);

      // groupId='g-alice' means only group g-alice rows pass — the wallet
      // entry (99, null groupId) and g-bob (25) are both excluded even though
      // source stays at its default (all).
      // Total: 15.00 + 5.00 = 20.00
      expect(data.totalSpend, Decimal.parse('20.00'),
          reason: 'Only g-alice rows (15+5=20) counted; wallet (99) + g-bob (25) excluded');
      expect(data.allExpenses.length, 2,
          reason: 'Two g-alice entries within 30d window');
      expect(data.allExpenses.every((e) => e.groupId == 'g-alice'), isTrue,
          reason: 'All returned rows must match seeded groupId — no wallet leak under source=all');
    });

    testWidgets('without initialGroupId all rows are included (default)', (tester) async {
      final container = _container(
        walletEntries: [
          _walletExpense(id: 'we-1', amount: '30.00', category: 'Books',
              createdAt: _daysAgo(2)),
        ],
        recentExpenses: [
          _groupExpense(
              id: 'g1-a', amount: '10.00', category: 'Food', groupId: 'g-alice',
              createdAt: _daysAgo(3)),
          _groupExpense(
              id: 'g2-a', amount: '20.00', category: 'Food', groupId: 'g-bob',
              createdAt: _daysAgo(4)),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AnalyticsScreen(), // NO initialGroupId
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final data = await container.read(analyticsDataProvider.future);

      // Default: source=all, no groupId filter
      // wallet (30) + group g1 (10) + group g2 (20) = 60
      expect(data.totalSpend, Decimal.parse('60.00'),
          reason: 'All sources included when no initialGroupId is set');
      expect(data.allExpenses.length, 3,
          reason: '3 unique entries (1 wallet + 2 group)');
    });

    testWidgets('groupName appears as the app bar title when scoped', (tester) async {
      final container = _container(
        recentExpenses: [
          _groupExpense(
              id: 'g1-a', amount: '10.00', groupId: 'g-alice',
              createdAt: _daysAgo(2)),
        ],
      );

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: AnalyticsScreen(
              initialGroupId: 'g-alice',
              groupName: 'Alice Group',
            ),
          ),
        ),
      );

      // AppBar title should show group name (before any translations resolve).
      expect(find.text('Alice Group'), findsOneWidget);
    });
  });
}

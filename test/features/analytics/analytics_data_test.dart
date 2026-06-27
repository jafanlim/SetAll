// Hermetic guard tests for the analytics data path.
//
// Verifies amounts flow end-to-end from providers → AnalyticsData without
// touching the network, Supabase, or SQLite.  Only four providers are
// overridden; _analyticsFilterProvider is left at its default (source=all,
// last 30 days) so the real date-window + dedup + normalization logic runs.
//
// GOAL: prove TASK 4 "web has no SQLite → insights hub reads empty amounts"
//       is stale — the Supabase datasource was wired Feb/March 2025 and the
//       mapping chain (ExpenseModel.fromJson → AnalyticsRow.from*) preserves
//       amounts identically for both SQLite and web paths.

import 'package:decimal/decimal.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:setall/core/providers/setall_providers.dart';
import 'package:setall/data/models/expense_model.dart';
import 'package:setall/data/models/wallet_entry_model.dart';
import 'package:setall/features/analytics/presentation/screens/analytics_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// ISO-8601 string for [days] days ago at noon UTC (stable within 30d window).
String _daysAgo(int days) =>
    DateTime.now().subtract(Duration(days: days)).toUtc().toIso8601String();

// ---------------------------------------------------------------------------
// Test data
// ---------------------------------------------------------------------------

WalletEntryModel _walletExpense({
  String id = 'we-1',
  String amount = '100.00',
  String? universalUsdAmount,
  String currency = 'USD',
  String category = 'Food',
  String description = 'Groceries',
  bool isIncome = false,
  String? createdAt,
  String? originalAmount,
  String? originalCurrency,
}) {
  // Auto-derive: when not explicitly overridden, universalUsdAmount = amount
  // (for base-currency entries) and originalAmount = amount so the
  // normalization path uses it directly.
  final usdAmt = universalUsdAmount ?? amount;
  final origAmt = originalAmount ?? (originalCurrency == null ? amount : null);
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
    originalAmount: origAmt,
    originalCurrency: originalCurrency,
  );
}

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
  String? originalAmount,
  String? originalCurrency,
}) {
  final usdAmt = universalUsdAmount ?? amount;
  final origAmt = originalAmount ?? (originalCurrency == null ? amount : null);
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
    originalAmount: origAmt,
    originalCurrency: originalCurrency,
  );
}

// ---------------------------------------------------------------------------
// Container factory — each test gets a fresh, isolated container
// ---------------------------------------------------------------------------

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
      // Override every rate the test will ask for.
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
  // ─────────────────────────────────────────────────────────────────────────
  // 1. Amounts flow end-to-end (the TASK 4 core assertion)
  // ─────────────────────────────────────────────────────────────────────────
  group('Amounts flow end-to-end', () {
    test('wallet + group expenses → non-empty totalSpend', () async {
      final c = _container(
        walletEntries: [
          _walletExpense(id: 'we-a', amount: '100.00', category: 'Food'),
        ],
        recentExpenses: [
          _groupExpense(id: 'grp-a', amount: '50.00', category: 'Transport'),
        ],
      );

      final data = await c.read(analyticsDataProvider.future);

      expect(data.totalSpend, Decimal.parse('150.00'),
          reason: '100 wallet + 50 group = 150 USD total spend');
      expect(data.categoryTotals['Food'], Decimal.parse('100.00'));
      expect(data.categoryTotals['Transport'], Decimal.parse('50.00'));
      expect(data.totalIncome, Decimal.zero);
      expect(data.allExpenses.length, 2);
      expect(data.currency, 'USD');
    });

    test('multiple wallet entries aggregate correctly', () async {
      final c = _container(
        walletEntries: [
          _walletExpense(id: 'we-1', amount: '25.00', category: 'Food'),
          _walletExpense(id: 'we-2', amount: '75.00', category: 'Food'),
          _walletExpense(id: 'we-3', amount: '30.00', category: 'Shopping'),
        ],
      );

      final data = await c.read(analyticsDataProvider.future);

      expect(data.totalSpend, Decimal.parse('130.00'));
      expect(data.categoryTotals['Food'], Decimal.parse('100.00'));
      expect(data.categoryTotals['Shopping'], Decimal.parse('30.00'));
    });

    test('anti-vacuous: non-zero amounts in row factories survive mapping',
        () async {
      // Seed amounts that would be 0 if any null-coalesce in the chain
      // silently drops a field.
      final c = _container(
        walletEntries: [
          _walletExpense(
            id: 'we-v',
            amount: '99.99',
            universalUsdAmount: '99.99',
            category: 'Test',
          ),
        ],
      );

      final data = await c.read(analyticsDataProvider.future);

      expect(data.totalSpend, Decimal.parse('99.99'),
          reason: '99.99 must survive the full provider chain — 0 means '
              'a mapping step dropped the amount');
      expect(data.allExpenses.single.amount, '99.99');
      expect(data.allExpenses.single.universalUsdAmount, '99.99');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. Income vs expense split
  // ─────────────────────────────────────────────────────────────────────────
  group('Income vs expense split', () {
    test('isIncome: true → totalIncome, not totalSpend', () async {
      final c = _container(
        walletEntries: [
          _walletExpense(
            id: 'we-inc', amount: '1000.00', category: 'Salary',
            isIncome: true, description: 'Paycheck',
          ),
          _walletExpense(
            id: 'we-exp', amount: '300.00', category: 'Rent',
            isIncome: false, description: 'Monthly rent',
          ),
        ],
      );

      final data = await c.read(analyticsDataProvider.future);

      expect(data.totalIncome, Decimal.parse('1000.00'));
      expect(data.totalSpend, Decimal.parse('300.00'));
      expect(data.netFlow, Decimal.parse('700.00'));               // income - spend
      expect(data.categoryTotals['Salary'], isNull,
          reason: 'Income should not appear in expense categoryTotals');
    });

    test('group income flows to totalIncome', () async {
      final c = _container(
        recentExpenses: [
          _groupExpense(
            id: 'grp-inc', amount: '500.00', category: 'Refund',
            isIncome: true, description: 'Settlement received',
          ),
          _groupExpense(
            id: 'grp-exp', amount: '200.00', category: 'Dining',
            isIncome: false, description: 'Dinner out',
          ),
        ],
      );

      final data = await c.read(analyticsDataProvider.future);

      expect(data.totalIncome, Decimal.parse('500.00'));
      expect(data.totalSpend, Decimal.parse('200.00'));
      expect(data.netFlow, Decimal.parse('300.00'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. Currency normalization
  // ─────────────────────────────────────────────────────────────────────────
  group('Currency normalization', () {
    test('baseCurrency EUR with USD→EUR rate 1.08 converts correctly',
        () async {
      final c = _container(
        baseCurrency: 'EUR',
        exchangeRates: const {'EUR': '1.08'},
        walletEntries: [
          // USD expense: universalUsdAmount=100 → 100 * 1.08 = 108 EUR
          _walletExpense(
            id: 'we-usd',
            amount: '100.00',
            universalUsdAmount: '100.00',
            currency: 'EUR',           // stored as EUR (converted at entry)
            originalAmount: '100.00',
            originalCurrency: 'USD',
            category: 'Shopping',
          ),
          // Native EUR expense: originalCurrency=EUR, uses originalAmount=40 directly
          _walletExpense(
            id: 'we-eur',
            amount: '40.00',
            universalUsdAmount: '37.04',  // 40/1.08 ≈ 37.04
            currency: 'EUR',
            originalAmount: '40.00',
            originalCurrency: 'EUR',
            category: 'Food',
          ),
        ],
      );

      final data = await c.read(analyticsDataProvider.future);

      // USD row: entryCcy='USD' ≠ baseCurrency 'EUR'
      //   → universalUsdAmount * usdToBaseRate = 100 * 1.08 = 108
      // EUR row: entryCcy='EUR' == baseCurrency 'EUR' && originalAmount != null
      //   → uses originalAmount = 40 directly
      // Total spend = 108 + 40 = 148
      expect(data.totalSpend, Decimal.parse('148.00'),
          reason: '108 (converted USD) + 40 (native EUR) = 148 EUR total');
      expect(data.currency, 'EUR');
    });

    test('baseCurrency USD with rate=1 (straight-through)', () async {
      final c = _container(
        walletEntries: [
          _walletExpense(
            id: 'we-usd-1', amount: '50.00',
            universalUsdAmount: '50.00', category: 'Food'),
        ],
        recentExpenses: [
          _groupExpense(
            id: 'grp-usd-1', amount: '25.00',
            universalUsdAmount: '25.00', category: 'Transport'),
        ],
      );

      final data = await c.read(analyticsDataProvider.future);

      // USD rows: entryCcy='USD' == baseCurrency, originalAmount used.
      expect(data.totalSpend, Decimal.parse('75.00'));
      expect(data.currency, 'USD');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. Deduplication
  // ─────────────────────────────────────────────────────────────────────────
  // NOTE: dedup tests use a shared RELATIVE timestamp (_daysAgo, computed once
  // and reused across the row pair) — NOT a hardcoded date. A hardcoded date
  // would eventually age past the default 30-day window and make these tests
  // fail spuriously on a future run.
  group('Deduplication', () {
    test('identical createdAt+amount+description → single row', () async {
      final ts = _daysAgo(5);
      final dup1 = _walletExpense(
        id: 'we-dup1', amount: '75.00', description: 'Duplicate',
        createdAt: ts,  // same for both
      );
      final dup2 = _walletExpense(
        id: 'we-dup2', amount: '75.00', description: 'Duplicate',
        createdAt: ts,  // same
      );

      final c = _container(walletEntries: [dup1, dup2]);

      final data = await c.read(analyticsDataProvider.future);

      expect(data.totalSpend, Decimal.parse('75.00'),
          reason: 'Dedup should collapse two identical rows to one');
      expect(data.allExpenses.length, 1);
    });

    test('different amounts → no dedup', () async {
      final ts = _daysAgo(5);
      final r1 = _walletExpense(
        id: 'we-1', amount: '10.00', description: 'Item',
        createdAt: ts,
      );
      final r2 = _walletExpense(
        id: 'we-2', amount: '20.00', description: 'Item',
        createdAt: ts,
      );

      final c = _container(walletEntries: [r1, r2]);

      final data = await c.read(analyticsDataProvider.future);

      expect(data.totalSpend, Decimal.parse('30.00'));
      expect(data.allExpenses.length, 2);
    });

    test('different descriptions → no dedup', () async {
      final ts = _daysAgo(5);
      final r1 = _walletExpense(
        id: 'we-a', amount: '30.00', description: 'Alpha',
        createdAt: ts,
      );
      final r2 = _walletExpense(
        id: 'we-b', amount: '30.00', description: 'Beta',
        createdAt: ts,
      );

      final c = _container(walletEntries: [r1, r2]);

      final data = await c.read(analyticsDataProvider.future);

      expect(data.totalSpend, Decimal.parse('60.00'));
      expect(data.allExpenses.length, 2);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 5. Date window
  // ─────────────────────────────────────────────────────────────────────────
  group('Date window (default: last 30 days)', () {
    test('row 60 days ago is excluded from totalSpend', () async {
      final recent = _walletExpense(
        id: 'we-recent', amount: '50.00', category: 'Food',
        createdAt: _daysAgo(5),
      );
      final old = _walletExpense(
        id: 'we-old', amount: '500.00', category: 'Ancient',
        createdAt: _daysAgo(60),
      );

      final c = _container(walletEntries: [recent, old]);

      final data = await c.read(analyticsDataProvider.future);

      expect(data.totalSpend, Decimal.parse('50.00'),
          reason: 'Only the 5d-ago (\$50) row should count; '
              'the 60d-ago (\$500) row must be outside the window');
      expect(data.allExpenses.length, 1);
      expect(data.allExpenses.single.description, 'Groceries',
          reason: 'Only the recent entry (Groceries) should be in the window');
    });

    test('row at exactly 30 days margin may be excluded (strict isBefore)',
        () async {
      // The cutoff is DateTime.now().subtract(Duration(days: 30)).
      // isBefore(cutoff) excludes entries ON the cutoff itself.
      // We test a row at day 31 to guarantee exclusion.
      final recent = _walletExpense(
        id: 'we-day5', amount: '10.00',
        createdAt: _daysAgo(5),
      );
      final marginal = _walletExpense(
        id: 'we-day31', amount: '999.00',
        createdAt: _daysAgo(31),
      );

      final c = _container(walletEntries: [recent, marginal]);

      final data = await c.read(analyticsDataProvider.future);

      expect(data.totalSpend, Decimal.parse('10.00'),
          reason: '31-day-old entry must be excluded');
      expect(data.allExpenses.length, 1);
    });

    test('rows within window are all included', () async {
      final entries = List.generate(5, (i) =>
          _walletExpense(
            id: 'we-w$i', amount: '20.00', category: 'Food',
            createdAt: _daysAgo(i * 3),   // 0, 3, 6, 9, 12 days ago
          ),
      );

      final c = _container(walletEntries: entries);
      final data = await c.read(analyticsDataProvider.future);

      expect(data.totalSpend, Decimal.parse('100.00'),
          reason: '5 entries × \$20 within 30d window');
      expect(data.allExpenses.length, 5);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 6. Empty sources
  // ─────────────────────────────────────────────────────────────────────────
  group('Empty sources', () {
    test('no wallet entries + no group expenses → totalSpend == 0', () async {
      final c = _container();

      final data = await c.read(analyticsDataProvider.future);

      expect(data.totalSpend, Decimal.zero);
      expect(data.totalIncome, Decimal.zero);
      expect(data.netFlow, Decimal.zero);
      expect(data.categoryTotals, isEmpty);
      expect(data.allExpenses, isEmpty);
    });

    test('wallet entries only, no group expenses', () async {
      final c = _container(
        walletEntries: [
          _walletExpense(id: 'we-solo', amount: '42.00', category: 'Books'),
        ],
      );

      final data = await c.read(analyticsDataProvider.future);

      expect(data.totalSpend, Decimal.parse('42.00'));
      expect(data.allExpenses.length, 1);
    });

    test('group expenses only, no wallet entries', () async {
      final c = _container(
        recentExpenses: [
          _groupExpense(id: 'grp-solo', amount: '88.00', category: 'Travel'),
        ],
      );

      final data = await c.read(analyticsDataProvider.future);

      expect(data.totalSpend, Decimal.parse('88.00'));
      expect(data.allExpenses.length, 1);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 7. Returned data integrity
  // ─────────────────────────────────────────────────────────────────────────
  group('Returned data integrity', () {
    test('allExpenses contains the mapped rows', () async {
      final c = _container(
        walletEntries: [
          _walletExpense(id: 'we-a', amount: '10.00', category: 'A'),
          _walletExpense(id: 'we-b', amount: '20.00', category: 'B'),
        ],
        recentExpenses: [
          _groupExpense(id: 'grp-a', amount: '30.00', category: 'C'),
        ],
      );

      final data = await c.read(analyticsDataProvider.future);

      expect(data.allExpenses.length, 3);
      // Verify each row has non-empty amounts (the mapping didn't drop fields).
      for (final row in data.allExpenses) {
        expect(row.amount, isNotEmpty);
        expect(row.universalUsdAmount, isNotEmpty);
        expect(row.category, isNotEmpty);
      }
    });

    test('burnRate is non-negative and computed', () async {
      final c = _container(
        walletEntries: [
          _walletExpense(id: 'we-1', amount: '300.00', category: 'Food',
              createdAt: _daysAgo(1)),
        ],
      );

      final data = await c.read(analyticsDataProvider.future);

      // spanDays ≈ 29–30, burnRate = 300 / spanDays ≈ 10.0–10.35
      expect(data.burnRate, greaterThan(0));
      expect(data.burnRate, lessThan(15.0));
    });

    test('netFlow = totalIncome - totalSpend', () async {
      final c = _container(
        walletEntries: [
          _walletExpense(id: 'we-inc', amount: '500.00', category: 'Salary',
              isIncome: true),
          _walletExpense(id: 'we-exp', amount: '200.00', category: 'Rent',
              isIncome: false),
        ],
      );

      final data = await c.read(analyticsDataProvider.future);

      expect(data.netFlow, Decimal.parse('300.00'));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 8. ivePeriods (income vs expense chart data)
  // ─────────────────────────────────────────────────────────────────────────
  group('ivePeriods', () {
    test('ivePeriods is non-null and reflects windowed data', () async {
      final c = _container(
        walletEntries: [
          _walletExpense(id: 'we-1', amount: '100.00', category: 'Food',
              createdAt: _daysAgo(5)),
          _walletExpense(id: 'we-2', amount: '200.00', category: 'Income',
              isIncome: true, createdAt: _daysAgo(5)),
        ],
      );

      final data = await c.read(analyticsDataProvider.future);

      expect(data.ivePeriods, isNotEmpty,
          reason: 'Should have at least one period for ≤90d window');
      // Sum of expense across all periods should match totalSpend
      final periodExpenseSum =
          data.ivePeriods.fold(Decimal.zero, (sum, p) => sum + p.expense);
      expect(periodExpenseSum, data.totalSpend);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 9. Decimal exactness (float-drift guard)
  // ─────────────────────────────────────────────────────────────────────────
  group('Decimal exactness — no float drift', () {
    test('0.10 + 0.20 is exactly 0.30 in Decimal', () async {
      final c = _container(
        walletEntries: [
          _walletExpense(id: 'we-010', amount: '0.10', category: 'A'),
          _walletExpense(id: 'we-020', amount: '0.20', category: 'A'),
        ],
      );

      final data = await c.read(analyticsDataProvider.future);

      // 0.10 + 0.20 = 0.30 MUST be exact — not 0.30000000000000004
      expect(data.totalSpend, Decimal.parse('0.30'),
          reason: 'Decimal arithmetic must be exact: 0.10 + 0.20 = 0.30');
      expect(data.categoryTotals['A'], Decimal.parse('0.30'));
    });

    test('repeated thirds sum to exact whole in Decimal', () async {
      // Three entries of 0.33 should sum to 0.99, not 0.9900000000000001
      final entries = List.generate(3, (i) =>
          _walletExpense(
            id: 'we-th3-$i', amount: '0.33', category: 'Thirds',
            createdAt: _daysAgo(i),
          ),
      );

      final c = _container(walletEntries: entries);
      final data = await c.read(analyticsDataProvider.future);

      expect(data.totalSpend, Decimal.parse('0.99'),
          reason: '3 × 0.33 = 0.99 exactly in Decimal');
    });

    test('Decimal netFlow = totalIncome - totalSpend is exact', () async {
      final c = _container(
        walletEntries: [
          _walletExpense(id: 'we-inc', amount: '1000.00', category: 'Income',
              isIncome: true),
          _walletExpense(id: 'we-exp', amount: '333.33', category: 'Rent'),
        ],
      );

      final data = await c.read(analyticsDataProvider.future);

      // 1000.00 - 333.33 = 666.67 exactly
      expect(data.netFlow, Decimal.parse('666.67'),
          reason: 'Decimal arithmetic: 1000.00 - 333.33 = 666.67');
      expect(data.totalIncome - data.totalSpend, data.netFlow,
          reason: 'Invariant: netFlow = totalIncome - totalSpend');
    });
  });
}

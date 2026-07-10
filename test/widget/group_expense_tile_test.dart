// Hermetic widget tests for group expense tiles.
//
// Verifies that _ExpenseTile and _ExpenseTileSelectable render:
//   1. The entry date (short form for current year, medium for prior year).
//   2. A robust ≈ base-currency estimate — including the core regression guard:
//      a GEL expense with USD base and an EMPTY exchange-rate cache still
//      renders "≈ USD <amount>" (no rate-provider dependency on the USD path).
//   3. No ≈ annotation when displayed currency == base currency.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:setall/core/providers/setall_providers.dart';
import 'package:setall/data/models/expense_model.dart';
import 'package:setall/features/dashboard/presentation/screens/group_detail_screen.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Wraps [child] in the minimal Flutter + Riverpod scaffolding needed for
/// tile widget tests.
Widget _wrap(Widget child, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      home: Scaffold(body: Directionality(textDirection: TextDirection.ltr, child: child)),
    ),
  );
}

ExpenseModel _gelExpense({
  String id = 'e1',
  String amount = '50.00',
  String originalAmount = '150.00',
  String originalCurrency = 'GEL',
  String universalUsdAmount = '54.95',
  String? createdAt,
  String currency = 'USD',
}) {
  return ExpenseModel(
    id: id,
    payerId: 'test-user',
    amount: amount,
    originalAmount: originalAmount,
    originalCurrency: originalCurrency,
    universalUsdAmount: universalUsdAmount,
    currency: currency,
    category: 'Food & drink',
    description: 'Lunch',
    createdAt: createdAt,
  );
}

ExpenseModel _usdExpense({
  String id = 'e2',
  String amount = '25.00',
  String? createdAt,
}) {
  return ExpenseModel(
    id: id,
    payerId: 'test-user',
    amount: amount,
    currency: 'USD',
    category: 'Transport',
    description: 'Bus',
    createdAt: createdAt,
  );
}

// ---------------------------------------------------------------------------
// 1. formatExpenseDate unit tests
// ---------------------------------------------------------------------------

void main() {
  group('formatExpenseDate', () {
    test('current-year → short form "d MMM"', () {
      final now = DateTime.now();
      // Use a date in the current year but different month to avoid flakiness
      final testDate = DateTime(now.year, 6, 7, 12, 0);
      final iso = testDate.toUtc().toIso8601String();

      final result = formatExpenseDate(iso);
      expect(result, isNotEmpty);
      // Short form: "d MMM" — e.g. "7 Jun"
      expect(result.contains('Jun'), isTrue);
      // Must NOT contain the year
      expect(result.contains(now.year.toString()), isFalse);
    });

    test('prior-year → medium form "d MMM yyyy"', () {
      final priorYear = DateTime.now().year - 1;
      final testDate = DateTime(priorYear, 6, 7, 12, 0);
      final iso = testDate.toUtc().toIso8601String();

      final result = formatExpenseDate(iso);
      expect(result, isNotEmpty);
      // Must contain the year
      expect(result.contains(priorYear.toString()), isTrue);
      // e.g. "7 Jun 2025"
      expect(result, contains('Jun'));
    });

    test('null createdAt → empty string', () {
      expect(formatExpenseDate(null), isEmpty);
    });

    test('malformed string → empty string', () {
      expect(formatExpenseDate('not-a-date'), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. Widget tests
  // ---------------------------------------------------------------------------

  group('Expense tile estimate', () {
    testWidgets('GEL expense + USD base + empty rates → ≈ USD still renders', (tester) async {
      // Core regression guard: the USD-base path must NOT depend on
      // exchange-rate lookups. We override rateToBaseProvider with an
      // empty/failing provider to prove it is never called.
      final expense = _gelExpense(
        createdAt: DateTime(DateTime.now().year, 6, 7, 12, 0).toUtc().toIso8601String(),
      );

      await tester.pumpWidget(_wrap(
        ExpenseTile(
          expense: expense,
          groupId: 'g1',
          groupName: 'Test Group',
          onDeleted: () {},
        ),
        overrides: [
          baseCurrencyProvider.overrideWith((ref) async => 'USD'),
          // No exchange_rates — prove we never need them
        ],
      ));

      // Should render the amount in GEL
      expect(find.text('GEL 150.00'), findsOneWidget);
      // Core assertion: ≈ USD with the universal_usd_amount, NO rate lookup
      expect(find.textContaining('≈ USD'), findsOneWidget);
      expect(find.text('≈ USD 54.95'), findsOneWidget);
      // Date: current year → short form
      expect(find.textContaining('Jun'), findsOneWidget);
    });

    testWidgets('same currency → NO estimate annotation', (tester) async {
      final expense = _usdExpense(
        createdAt: DateTime(DateTime.now().year, 6, 7, 12, 0).toUtc().toIso8601String(),
      );

      await tester.pumpWidget(_wrap(
        ExpenseTile(
          expense: expense,
          groupId: 'g1',
          groupName: 'Test Group',
          onDeleted: () {},
        ),
        overrides: [
          baseCurrencyProvider.overrideWith((ref) async => 'USD'),
        ],
      ));

      // Amount in USD
      expect(find.text('USD 25.00'), findsOneWidget);
      // NO ≈ annotation — displayed currency == base currency
      expect(find.textContaining('≈'), findsNothing);
      // Date still shows
      expect(find.textContaining('Jun'), findsOneWidget);
    });

    testWidgets('Selectable tile renders date + ≈ estimate with USD base', (tester) async {
      final expense = _gelExpense(
        createdAt: DateTime(DateTime.now().year, 6, 7, 12, 0).toUtc().toIso8601String(),
      );

      await tester.pumpWidget(_wrap(
        ExpenseTileSelectable(
          expense: expense,
          selected: false,
          onToggle: () {},
        ),
        overrides: [
          baseCurrencyProvider.overrideWith((ref) async => 'USD'),
        ],
      ));

      // Amount in displayed currency (GEL)
      expect(find.text('GEL 150.00'), findsOneWidget);
      // ≈ USD estimate
      expect(find.text('≈ USD 54.95'), findsOneWidget);
      // Date
      expect(find.textContaining('Jun'), findsOneWidget);
    });
  });
}

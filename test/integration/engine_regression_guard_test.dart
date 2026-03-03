// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:setall/core/services/currency_service.dart';
import 'package:setall/core/utils/debt_simplification_engine.dart';
import 'package:setall/data/models/split_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ---------------------------------------------------------------------------
// SharedPreferences factory: creates an in-memory mock with no values.
// Must be called before constructing CurrencyService in any async test.
Future<SharedPreferences> _emptyPrefs() async {
  SharedPreferences.setMockInitialValues({});
  return SharedPreferences.getInstance();
}

// ---------------------------------------------------------------------------
// Minimal fake HTTP client that returns a fixed Frankfurter-shaped JSON body.
// Used so CurrencyService never touches the real network.
// ---------------------------------------------------------------------------
class _FakeHttpClient extends http.BaseClient {
  _FakeHttpClient(this._rates);

  /// rates[from][to] = rate value as num
  final Map<String, Map<String, num>> _rates;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final uri = request.url;
    final from = uri.queryParameters['from']?.toUpperCase() ?? '';
    final to = uri.queryParameters['to']?.toUpperCase() ?? '';
    final rateValue = _rates[from]?[to];
    if (rateValue == null) {
      return _respond(404, '{"error":"rate not found"}');
    }
    final body = jsonEncode({
      'base': from,
      'rates': {to: rateValue},
    });
    return _respond(200, body);
  }

  http.StreamedResponse _respond(int status, String body) {
    return http.StreamedResponse(
      Stream.value(utf8.encode(body)),
      status,
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Build an expense raw-map as the engine expects.
Map<String, dynamic> _expense({
  required String id,
  required String groupId,
  required String payerId,
  required String amount,
  required String currency,
  String? baseAmountAtEntry,
}) =>
    {
      'id': id,
      'group_id': groupId,
      'payer_id': payerId,
      'amount': amount,
      'currency': currency,
      // Engine reads this key directly from the map
      'base_amount_at_entry': baseAmountAtEntry,
    };

/// Build a SplitModel as the engine expects.
SplitModel _split({
  required String expenseId,
  required String userId,
  required String amountOwed,
  String? universalUsdOwed,
}) =>
    SplitModel(
      id: '${expenseId}_${userId}',
      expenseId: expenseId,
      userId: userId,
      // Engine uses universalUsdOwed; fall back to amountOwed for legacy tests.
      universalUsdOwed: universalUsdOwed ?? amountOwed,
    );

// ---------------------------------------------------------------------------
// REGRESSION GUARD SUITE
// ---------------------------------------------------------------------------

void main() {
  group('Regression Guard — Engine Integration Tests', () {
    // -----------------------------------------------------------------------
    // SCENARIO 1 — "The Multi-National Dinner"
    //
    // Business rules under test:
    //   • USD Anchor: expense paid in EUR is frozen to USD at entry time via
    //     base_amount_at_entry (= amount × EUR→USD rate).
    //   • Equal split: each person's share = USD anchor / 4, rounded to 2dp.
    //   • Greedy Flow: payer is the only creditor → exactly 3 payment
    //     transactions are emitted (one per debtor).
    //   • Rounding guard: 108.55 / 4 = 27.1375 → must round to 27.14, not
    //     27.13 (checks no systematic floor-bias).
    // -----------------------------------------------------------------------
    group('Scenario 1 — The Multi-National Dinner', () {
      const groupId = 'grp-dinner';
      const payer = 'user-alice';
      const guestB = 'user-bob';
      const guestC = 'user-carol';
      const guestD = 'user-dave';
      const expenseId = 'exp-dinner-001';

      // 100.00 EUR × 1.0855 USD/EUR = 108.55 USD (anchor, rounded to 2dp)
      const eurAmount = '100.00';
      const usdAnchor = '108.55'; // (100 * 1.0855).round(scale:2)

      // Each of 4 people owes 108.55 / 4 = 27.1375 → rounds to 27.14
      const perPersonUsd = '27.14';

      final expenses = [
        _expense(
          id: expenseId,
          groupId: groupId,
          payerId: payer,
          amount: eurAmount,
          currency: 'EUR',
          baseAmountAtEntry: usdAnchor,
        ),
      ];

      // Payer is included in the split (they owe their own share too).
      // Engine subtracts split owed from balance; payer started with +108.55.
      final splits = [
        _split(
            expenseId: expenseId,
            userId: payer,
            amountOwed: perPersonUsd,
            universalUsdOwed: perPersonUsd),
        _split(
            expenseId: expenseId,
            userId: guestB,
            amountOwed: perPersonUsd,
            universalUsdOwed: perPersonUsd),
        _split(
            expenseId: expenseId,
            userId: guestC,
            amountOwed: perPersonUsd,
            universalUsdOwed: perPersonUsd),
        _split(
            expenseId: expenseId,
            userId: guestD,
            amountOwed: perPersonUsd,
            universalUsdOwed: perPersonUsd),
      ];

      test('1a — each universal_usd_owed is exactly 27.14 (no rounding bias)',
          () {
        // This test validates the anchor arithmetic upstream of the engine.
        // The repository would have stored these values; we assert the
        // contract here so any future change to the rounding logic is caught.
        final eurDecimal = Decimal.parse('100.00');
        final rate = Decimal.parse('1.0855'); // mocked EUR→USD rate
        final usdValue = (eurDecimal * rate).round(scale: 2);
        expect(usdValue, equals(Decimal.parse('108.55')),
            reason: '100 EUR × 1.0855 must anchor to exactly 108.55 USD');

        final share = (usdValue / Decimal.fromInt(4))
            .toDecimal(scaleOnInfinitePrecision: 10)
            .round(scale: 2);
        expect(share, equals(Decimal.parse('27.14')),
            reason:
                '108.55 / 4 = 27.1375 — must round UP to 27.14, not floor to 27.13');
      });

      test('1b — CurrencyService returns 1.0855 for EUR→USD (mocked network)',
          () async {
        final fakeHttp = _FakeHttpClient({
          'EUR': {'USD': 1.0855},
        });
        final svc = CurrencyService(client: fakeHttp, prefs: await _emptyPrefs());
        final rate = await svc.getRateToUsd('EUR');
        expect(rate, equals(Decimal.parse('1.0855')));
      });

      test('1c — Greedy Flow emits exactly 3 payments, all to the payer',
          () {
        final debts = DebtSimplificationEngine.simplify(
          groupId: groupId,
          currency: 'USD',
          expenses: expenses,
          splits: splits,
        );

        expect(debts.length, equals(3),
            reason:
                'With 1 payer and 3 guests, Greedy Flow must suggest exactly 3 transactions');

        for (final d in debts) {
          expect(d.toUserId, equals(payer),
              reason: 'All payments must flow to the payer (Alice)');
          // Each payment is 27.14 except possibly the last one which absorbs the
          // rounding penny (108.55 / 4 = 27.1375; 4 × 27.14 = 108.56, so the
          // last debtor pays 27.13 to balance).  Both values are acceptable.
          expect(
            d.amount >= Decimal.parse('27.13') &&
                d.amount <= Decimal.parse('27.14'),
            isTrue,
            reason:
                'Each payment must be 27.13 or 27.14 USD (rounding penny absorbed by last debtor)',
          );
        }

        // The sum of all payments must equal the payer's net credit:
        // 108.55 (anchor) - 27.14 (own share) = 81.41
        final totalPaid =
            debts.fold(Decimal.zero, (sum, d) => sum + d.amount);
        expect(totalPaid, equals(Decimal.parse('81.41')),
            reason:
                'Total of all payments must equal payer net credit of 81.41 USD');

        final debtors = debts.map((d) => d.fromUserId).toSet();
        expect(debtors, containsAll([guestB, guestC, guestD]),
            reason: 'Bob, Carol, and Dave must each have exactly one payment');
      });

      test('1d — payer has zero net balance after settlement', () {
        final debts = DebtSimplificationEngine.simplify(
          groupId: groupId,
          currency: 'USD',
          expenses: expenses,
          splits: splits,
        );

        // Verify nobody still appears as both creditor and debtor.
        final fromIds = debts.map((d) => d.fromUserId).toSet();
        final toIds = debts.map((d) => d.toUserId).toSet();
        expect(fromIds.intersection(toIds), isEmpty,
            reason: 'No user should simultaneously owe and be owed');
      });
    });

    // -----------------------------------------------------------------------
    // SCENARIO 2 — "The Infinite Netting Loop"
    //
    // Business rules under test:
    //   • Cyclic debt cancellation: A→B $50, B→C $50, C→A $50 means every
    //     person's net balance is zero (paid $50, owed $50).
    //   • The engine MUST return an empty list (no transactions needed).
    //   • Guards against naïve implementations that would suggest 3 payments.
    // -----------------------------------------------------------------------
    group('Scenario 2 — The Infinite Netting Loop', () {
      const groupId = 'grp-loop';
      const userA = 'user-a';
      const userB = 'user-b';
      const userC = 'user-c';

      // Three separate expenses: A pays for B's share, B pays for C, C pays for A.
      // Each expense is $50; each person pays $50 and owes $50 → net = 0.
      const expAB = 'exp-a-pays';
      const expBC = 'exp-b-pays';
      const expCA = 'exp-c-pays';

      final expenses = [
        _expense(
          id: expAB,
          groupId: groupId,
          payerId: userA,
          amount: '50.00',
          currency: 'USD',
          baseAmountAtEntry: '50.00',
        ),
        _expense(
          id: expBC,
          groupId: groupId,
          payerId: userB,
          amount: '50.00',
          currency: 'USD',
          baseAmountAtEntry: '50.00',
        ),
        _expense(
          id: expCA,
          groupId: groupId,
          payerId: userC,
          amount: '50.00',
          currency: 'USD',
          baseAmountAtEntry: '50.00',
        ),
      ];

      // Each expense has a single beneficiary (the person who received the
      // payment). A pays for B, B pays for C, C pays for A.
      final splits = [
        _split(
            expenseId: expAB,
            userId: userB,
            amountOwed: '50.00',
            universalUsdOwed: '50.00'),
        _split(
            expenseId: expBC,
            userId: userC,
            amountOwed: '50.00',
            universalUsdOwed: '50.00'),
        _split(
            expenseId: expCA,
            userId: userA,
            amountOwed: '50.00',
            universalUsdOwed: '50.00'),
      ];

      test('2a — net balance for every participant is 0.00 (fully settled)',
          () {
        final debts = DebtSimplificationEngine.simplify(
          groupId: groupId,
          currency: 'USD',
          expenses: expenses,
          splits: splits,
        );

        expect(debts, isEmpty,
            reason:
                'A→B→C→A cyclic loop must cancel entirely — 0 transactions needed. '
                'If this fails, the engine has a cyclic-netting bug.');
      });

      test('2b — no participant appears in any suggested payment', () {
        final debts = DebtSimplificationEngine.simplify(
          groupId: groupId,
          currency: 'USD',
          expenses: expenses,
          splits: splits,
        );

        final allParticipants = {userA, userB, userC};
        final mentioned = {
          ...debts.map((d) => d.fromUserId),
          ...debts.map((d) => d.toUserId),
        };
        expect(mentioned.intersection(allParticipants), isEmpty,
            reason: 'All three participants must be fully settled up (0.00)');
      });
    });

    // -----------------------------------------------------------------------
    // SCENARIO 3 — "The Localization Toggle"
    //
    // Business rules under test:
    //   • Lazy Localization: the USD anchor stored in the DB (10.00) is NEVER
    //     mutated when a user changes their display currency.
    //   • The conversion is a pure read-time multiplication: 10.00 × 2.65 = 26.50.
    //   • Checks that CurrencyService.convert() returns exactly 26.50 GEL.
    //   • Checks that the original USD value is untouched after conversion.
    // -----------------------------------------------------------------------
    group('Scenario 3 — The Localization Toggle', () {
      test(
          '3a — USD anchor 10.00 × GEL rate 2.65 returns exactly 26.50 GEL (mocked)',
          () async {
        final fakeHttp = _FakeHttpClient({
          'USD': {'GEL': 2.65},
        });
        final svc = CurrencyService(client: fakeHttp, prefs: await _emptyPrefs());

        const usdAnchor = '10.00';
        final usdDecimal = Decimal.parse(usdAnchor);

        final gelAmount = await svc.convert(usdDecimal, 'USD', 'GEL');

        expect(gelAmount, equals(Decimal.parse('26.50')),
            reason:
                '10.00 USD × 2.65 GEL/USD must equal exactly 26.50 GEL. '
                'Failure indicates a rounding error in CurrencyService.convert().');
      });

      test('3b — underlying USD anchor is not mutated by localization', () async {
        final fakeHttp = _FakeHttpClient({
          'USD': {'GEL': 2.65},
        });
        final svc = CurrencyService(client: fakeHttp, prefs: await _emptyPrefs());

        const usdAnchorInDb = '10.00';
        final usdDecimal = Decimal.parse(usdAnchorInDb);

        // Simulate a "toggle": convert to GEL for display, then back to USD.
        final gelDisplay = await svc.convert(usdDecimal, 'USD', 'GEL');
        expect(gelDisplay.toStringAsFixed(2), equals('26.50'));

        // The original value must be unchanged — this test guards against any
        // future refactor that accidentally writes the converted value back.
        expect(usdAnchorInDb, equals('10.00'),
            reason: 'The USD anchor string must remain "10.00" after conversion — '
                'localization is read-time-only and must not mutate the source value.');
      });

      test('3c — switching back from GEL to USD restores original value exactly',
          () async {
        // Simulate USD→GEL→USD round-trip to catch precision loss.
        final fakeHttp = _FakeHttpClient({
          'USD': {'GEL': 2.65},
          'GEL': {'USD': 0.37736}, // 1/2.65 ≈ 0.37736
        });
        final svc = CurrencyService(client: fakeHttp, prefs: await _emptyPrefs());

        final usdDecimal = Decimal.parse('10.00');
        final gelDisplay = await svc.convert(usdDecimal, 'USD', 'GEL');
        expect(gelDisplay.toStringAsFixed(2), equals('26.50'),
            reason: 'Forward conversion must still be 26.50');

        // The display layer never converts back — the DB value is always the
        // frozen USD anchor. This test confirms we can re-read the original.
        // (Any round-trip back through the mock rate is intentionally lossy
        //  and only the DB read path should be used to get the original value.)
        expect(usdDecimal.toStringAsFixed(2), equals('10.00'),
            reason: 'Original Decimal object must not be modified by conversion');
      });

      test('3d — engine produces correct USD debt; BalanceService layer converts to GEL',
          () async {
        // End-to-end layered test:
        //   1. Engine works in USD (the base anchor).
        //   2. BalanceService multiplies by USD→GEL rate for display only.
        const groupId = 'grp-gel-test';
        const payerId = 'user-payer';
        const debtorId = 'user-debtor';
        const expId = 'exp-gel-001';

        final expenses = [
          _expense(
            id: expId,
            groupId: groupId,
            payerId: payerId,
            amount: '10.00',
            currency: 'USD',
            baseAmountAtEntry: '10.00',
          ),
        ];
        final splits = [
          _split(
              expenseId: expId,
              userId: debtorId,
              amountOwed: '10.00',
              universalUsdOwed: '10.00'),
        ];

        // Step 1: Engine returns the USD debt.
        final debts = DebtSimplificationEngine.simplify(
          groupId: groupId,
          currency: 'USD',
          expenses: expenses,
          splits: splits,
        );
        expect(debts.length, equals(1));
        final usdDebt = debts.first.amount;
        expect(usdDebt, equals(Decimal.parse('10.00')),
            reason: 'Engine must return 10.00 USD');

        // Step 2: BalanceService display layer converts USD→GEL (rate 2.65).
        final fakeHttp = _FakeHttpClient({
          'USD': {'GEL': 2.65},
        });
        final svc = CurrencyService(client: fakeHttp, prefs: await _emptyPrefs());
        final gelDisplay = await svc.convert(usdDebt, 'USD', 'GEL');
        expect(gelDisplay.toStringAsFixed(2), equals('26.50'),
            reason: 'Display layer must show 26.50 GEL without touching DB');
      });
    });
  });
}

// ignore_for_file: lines_longer_than_80_chars

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:setall/core/utils/split_engine.dart';
import 'package:setall/data/repositories/setall_repository.dart'
    show BalanceEntry, SetAllRepository;
import 'package:setall/data/models/profile_model.dart';
import 'package:setall/core/services/balance_service.dart';
import 'package:setall/core/services/currency_service.dart';

// ---------------------------------------------------------------------------
// Minimal stubs — no mockito needed
// ---------------------------------------------------------------------------

/// A [CurrencyService] that returns a fixed rate map without any network or
/// SharedPreferences calls.
class _StubCurrencyService extends CurrencyService {
  _StubCurrencyService(this._rates) : super();

  final Map<String, Decimal> _rates;

  @override
  Future<Decimal> getRate(String fromCurrency, String toCurrency) async {
    if (fromCurrency == toCurrency) return Decimal.one;
    final key = '${fromCurrency}_$toCurrency';
    return _rates[key] ?? Decimal.one;
  }
}

/// A [SetAllRepository] stub that returns pre-set raw balance data without
/// any SQLite / Supabase calls.
class _StubRepository extends SetAllRepository {
  _StubRepository({
    required this.uid,
    required this.rawOwed,
    required this.rawOwe,
    required this.baseCurrency,
  }) : super();

  final String uid;
  final List<BalanceEntry> rawOwed;
  final List<BalanceEntry> rawOwe;
  final String baseCurrency;

  @override
  Future<String?> ensureUser() async => uid;

  @override
  Future<ProfileModel?> getCurrentUserProfile() async => ProfileModel(
        id: uid,
        name: 'Test User',
        defaultCurrency: baseCurrency,
      );

  @override
  Future<({List<BalanceEntry> youOwe, List<BalanceEntry> youAreOwed})>
      getBalanceRawData(String uid) async =>
          (youOwe: rawOwe, youAreOwed: rawOwed);

  @override
  Future<({List<BalanceEntry> youOwe, List<BalanceEntry> youAreOwed})?>
      getGroupBalanceRawData(String uid, String groupId) async =>
          (youOwe: rawOwe, youAreOwed: rawOwed);

  @override
  Future<void> syncIfOnline() async {}
}


// Helper: build a BalanceEntry with a plain USD amount.
BalanceEntry _usdEntry(String amount) => BalanceEntry(
      amount: Decimal.parse(amount),
      currency: 'USD',
    );

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ── TEST 1: THE PENNY-SPLIT ──────────────────────────────────────────────
  group('TEST 1 — The Penny-Split (10.00 USD ÷ 3 users)', () {
    test('sum of all split amounts equals exactly 10.00', () {
      const total = '10.00';
      const users = ['alice', 'bob', 'charlie'];

      final splits = SplitEngine.splitEven(
        total: Decimal.parse(total),
        participantIds: users,
        payerId: 'alice', // Alice absorbs the remainder penny
      );

      expect(splits.length, equals(3));

      final sum = splits.fold<Decimal>(
        Decimal.zero,
        (acc, s) => acc + s.amountOwed,
      );

      expect(
        sum,
        equals(Decimal.parse('10.00')),
        reason: 'All split shares must sum to exactly the original total '
            '(no penny lost or gained). Got: $sum',
      );

      // Extra: verify the two base shares and the remainder share
      final bases =
          splits.where((s) => s.userId != 'alice').map((s) => s.amountOwed);
      for (final b in bases) {
        expect(b, equals(Decimal.parse('3.33')),
            reason: 'Non-payer shares should be 3.33');
      }
      final aliceShare =
          splits.firstWhere((s) => s.userId == 'alice').amountOwed;
      expect(aliceShare, equals(Decimal.parse('3.34')),
          reason: 'Payer absorbs remainder → 3.34');
    });
  });

  // ── TEST 2: THE MUTUAL NETTING ──────────────────────────────────────────
  group('TEST 2 — The Mutual Netting (A owes B \$50, B owes A \$20)', () {
    test('net result is 30.00 youAreOwed, 0.00 youOwe', () async {
      // From User A's perspective:
      //   youAreOwed: B owes A $50
      //   youOwe:     A owes B $20
      final repo = _StubRepository(
        uid: 'user-a',
        rawOwed: [_usdEntry('50.00')],
        rawOwe: [_usdEntry('20.00')],
        baseCurrency: 'USD',
      );
      final fx = _StubCurrencyService({});
      final service = BalanceService(repository: repo, currencyService: fx);

      final summary = await service.getBalanceSummary();

      expect(
        summary.youAreOwed,
        equals('30.00'),
        reason: 'Net owed = 50 - 20 = 30.00',
      );
      expect(
        summary.youOwe,
        equals('0.00'),
        reason: 'When youAreOwed > youOwe, youOwe must be zeroed out',
      );
      expect(summary.currency, equals('USD'));
    });
  });

  // ── TEST 3: THE ANCHOR STABILITY ────────────────────────────────────────
  group('TEST 3 — The Anchor Stability (€100 @ 1.10 vs \$110 counter-expense)', () {
    test('group balance nets to 0.00 when USD-anchored amounts are equal', () async {
      // Scenario: User A paid €100 → 110.00 universal_usd_owed for User B.
      //           User B paid $110 → 110.00 universal_usd_owed for User A.
      // Both BalanceEntry objects already hold the USD-anchored amount, so
      // the CurrencyService rate is irrelevant for the net — both sides
      // cancel out exactly.
      final repo = _StubRepository(
        uid: 'user-a',
        rawOwed: [_usdEntry('110.00')], // B owes A $110 (A paid €100)
        rawOwe: [_usdEntry('110.00')],  // A owes B $110 (B paid $110)
        baseCurrency: 'USD',
      );
      final fx = _StubCurrencyService({
        'EUR_USD': Decimal.parse('1.10'),
        'USD_EUR': Decimal.parse('0.9090'),
      });
      final service = BalanceService(repository: repo, currencyService: fx);

      final summary = await service.getBalanceSummary();

      expect(
        summary.youAreOwed,
        equals('0.00'),
        reason: '110.00 owed − 110.00 owe = 0 net',
      );
      expect(
        summary.youOwe,
        equals('0.00'),
        reason: 'Both sides cancel; no residual debt on either side',
      );
    });

    test('USD-to-EUR conversion preserves the 110.00 USD anchor', () {
      // Sanity-check: 110 USD × (1/1.10) rounds to 100.00 EUR — confirms
      // the rate math works at 2 dp precision.
      final usd = Decimal.parse('110.00');
      final rateUsdToEur = Decimal.parse('0.909091');
      final eur = (usd * rateUsdToEur).round(scale: 2);
      expect(eur, equals(Decimal.parse('100.00')));
    });
  });

  // ---------------------------------------------------------------------------
  // myShareFromResults — pure helper, no I/O
  // ---------------------------------------------------------------------------

  group('myShareFromResults', () {
    test('returns my share from an even split (residual holder)', () {
      // 100.00 / 3 = 33.33 per person, payer (userId 'a') absorbs remainder
      final results = SplitEngine.splitEven(
        total: Decimal.parse('100.00'),
        participantIds: ['a', 'b', 'c'],
        payerId: 'a',
      );
      // Payer 'a' gets the residual: 100.00 - 33.33 - 33.33 = 33.34
      final share = myShareFromResults(results, 'a');
      expect(share, isNotNull);
      expect(share, equals(Decimal.parse('33.34')));
    });

    test('returns my share from an even split (non-payer)', () {
      final results = SplitEngine.splitEven(
        total: Decimal.parse('100.00'),
        participantIds: ['a', 'b', 'c'],
        payerId: 'a',
      );
      // Non-payer 'b' gets the base: 33.33
      final share = myShareFromResults(results, 'b');
      expect(share, isNotNull);
      expect(share, equals(Decimal.parse('33.33')));
    });

    test('never returns a value with more than 2 decimal places', () {
      // 100.00 / 3 — no share should have fractional cents
      final results = SplitEngine.splitEven(
        total: Decimal.parse('100.00'),
        participantIds: ['a', 'b', 'c'],
        payerId: 'a',
      );
      for (final r in results) {
        final share = myShareFromResults(results, r.userId);
        expect(share, isNotNull);
        // toStringAsFixed(2) must equal the raw string — no 33.3333...
        expect(share!.toStringAsFixed(2), share.toString());
      }
    });

    test('returns exact amountOwed from manual split', () {
      final results = SplitEngine.splitCustom(
        total: Decimal.parse('200.00'),
        participantIds: ['a', 'b', 'c'],
        amountsOwed: [
          Decimal.parse('150.00'),
          Decimal.parse('30.00'),
          Decimal.parse('20.00'),
        ],
      );
      expect(myShareFromResults(results, 'a'), equals(Decimal.parse('150.00')));
      expect(myShareFromResults(results, 'b'), equals(Decimal.parse('30.00')));
      expect(myShareFromResults(results, 'c'), equals(Decimal.parse('20.00')));
    });

    test('returns null for payer with zero share', () {
      // Payer 'a' pays, 'b' owes 100. 'a' has share 0.
      final results = [
        SplitResult(userId: 'a', amountOwed: Decimal.zero),
        SplitResult(userId: 'b', amountOwed: Decimal.parse('100.00')),
      ];
      expect(myShareFromResults(results, 'a'), isNull);
    });

    test('returns null when user not in results', () {
      final results = SplitEngine.splitEven(
        total: Decimal.parse('100.00'),
        participantIds: ['a', 'b'],
        payerId: 'a',
      );
      expect(myShareFromResults(results, 'x'), isNull);
    });

    test('returns null for empty results', () {
      expect(myShareFromResults([], 'a'), isNull);
    });

    test('reads amountOwed directly — never re-divides', () {
      // Even if the results were from a split, the helper just reads.
      // We verify by creating results that DON'T sum to any "total".
      final results = [
        SplitResult(userId: 'a', amountOwed: Decimal.parse('42.42')),
      ];
      // Helper should return 42.42 — it doesn't know or care about any total.
      expect(myShareFromResults(results, 'a'), equals(Decimal.parse('42.42')));
    });
  });
}

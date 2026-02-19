import 'package:decimal/decimal.dart';

import '../../data/repositories/setall_repository.dart';
import 'currency_service.dart';

/// Multi-currency balance: all amounts converted to user's base currency before summing.
/// Manual overrides are used per-expense via stored exchange_rate_applied.
class BalanceService {
  BalanceService({
    required SetAllRepository repository,
    required CurrencyService currencyService,
  })  : _repo = repository,
        _currency = currencyService;

  final SetAllRepository _repo;
  final CurrencyService _currency;

  static const String _defaultBaseCurrency = 'USD';

  /// Base currency for the current user (from profile). Default USD.
  Future<String> getBaseCurrency() async {
    final profile = await _repo.getCurrentUserProfile();
    return profile?.defaultCurrency ?? _defaultBaseCurrency;
  }

  /// Global net balance: you are owed and you owe, both in [baseCurrency].
  /// Converts every split to base using expense's exchange_rate_applied or live rate.
  Future<BalanceSummary> getBalanceSummary() async {
    final uid = await _repo.ensureUser();
    if (uid == null) return const BalanceSummary();

    await _repo.syncIfOnline();
    final baseCurrency = await getBaseCurrency();
    final raw = await _repo.getBalanceRawData(uid);

    var youOwe = Decimal.zero;
    var youAreOwed = Decimal.zero;

    for (final e in raw.youOwe) {
      youOwe += await _toBase(e, baseCurrency);
    }
    for (final e in raw.youAreOwed) {
      youAreOwed += await _toBase(e, baseCurrency);
    }

    return BalanceSummary(
      youOwe: youOwe.toStringAsFixed(2),
      youAreOwed: youAreOwed.toStringAsFixed(2),
      currency: baseCurrency,
    );
  }

  /// Group-scoped balance in base currency.
  Future<BalanceSummary> getGroupBalanceSummary(String groupId) async {
    final uid = await _repo.ensureUser();
    if (uid == null) return const BalanceSummary();

    await _repo.syncIfOnline();
    final baseCurrency = await getBaseCurrency();
    final raw = await _repo.getGroupBalanceRawData(uid, groupId);
    if (raw == null) return BalanceSummary(currency: baseCurrency);

    var youOwe = Decimal.zero;
    var youAreOwed = Decimal.zero;
    for (final e in raw.youOwe) {
      youOwe += await _toBase(e, baseCurrency);
    }
    for (final e in raw.youAreOwed) {
      youAreOwed += await _toBase(e, baseCurrency);
    }

    return BalanceSummary(
      youOwe: youOwe.toStringAsFixed(2),
      youAreOwed: youAreOwed.toStringAsFixed(2),
      currency: baseCurrency,
    );
  }

  /// Convert entry to base: if exchange_rate_applied is set, amount is already in base; else convert.
  Future<Decimal> _toBase(BalanceEntry e, String baseCurrency) async {
    if (e.exchangeRateApplied != null) {
      return e.amount;
    }
    if (e.currency == baseCurrency) return e.amount;
    final rate = await _currency.getRate(e.currency, baseCurrency);
    return (e.amount * rate).round(scale: 2);
  }
}

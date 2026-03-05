import 'package:decimal/decimal.dart';
import '../../data/repositories/setall_repository.dart';
import 'currency_service.dart';

class BalanceService {
  BalanceService({
    required SetAllRepository repository,
    required CurrencyService currencyService,
  })  : _repo = repository,
        _fx = currencyService;

  final SetAllRepository _repo;
  final CurrencyService _fx;

  Future<String> getBaseCurrency() async {
    final profile = await _repo.getCurrentUserProfile();
    return profile?.defaultCurrency ?? 'USD';
  }

  /// Convert a list of [BalanceEntry] amounts (stored in USD) into [baseCurrency].
  Future<Decimal> _sumInBase(
    List<BalanceEntry> entries,
    String baseCurrency,
  ) async {
    var total = Decimal.zero;
    for (final e in entries) {
      final amountUsd = e.amount;
      if (amountUsd == Decimal.zero) continue;
      if (baseCurrency == 'USD') {
        total += amountUsd;
      } else {
        final rate = await _fx.getRate('USD', baseCurrency);
        total += (amountUsd * rate).round(scale: 2);
      }
    }
    return total;
  }

  Future<BalanceSummary> getBalanceSummary() async {
    final uid = await _repo.ensureUser();
    if (uid == null) return const BalanceSummary();

    final baseCurrency = await getBaseCurrency();
    final raw = await _repo.getBalanceRawData(uid);

    final rawOwed = await _sumInBase(raw.youAreOwed, baseCurrency);
    final rawOwe  = await _sumInBase(raw.youOwe,     baseCurrency);

    // Net mutual debts: only the larger side survives; the other becomes zero.
    final net = rawOwed - rawOwe;
    final youAreOwed = net > Decimal.zero ? net  : Decimal.zero;
    final youOwe     = net < Decimal.zero ? -net : Decimal.zero;

    return BalanceSummary(
      youOwe:      youOwe.toStringAsFixed(2),
      youAreOwed:  youAreOwed.toStringAsFixed(2),
      currency:    baseCurrency,
    );
  }

  Future<BalanceSummary> getGroupBalanceSummary(String groupId, {String? targetCurrency}) async {
    final uid = await _repo.ensureUser();
    if (uid == null) return const BalanceSummary();

    final baseCurrency = targetCurrency ?? await getBaseCurrency();
    final raw = await _repo.getGroupBalanceRawData(uid, groupId);
    if (raw == null) return BalanceSummary(currency: baseCurrency);

    final rawOwed = await _sumInBase(raw.youAreOwed, baseCurrency);
    final rawOwe  = await _sumInBase(raw.youOwe,     baseCurrency);

    // Net mutual debts within this group.
    final net = rawOwed - rawOwe;
    final youAreOwed = net > Decimal.zero ? net  : Decimal.zero;
    final youOwe     = net < Decimal.zero ? -net : Decimal.zero;

    return BalanceSummary(
      youOwe:      youOwe.toStringAsFixed(2),
      youAreOwed:  youAreOwed.toStringAsFixed(2),
      currency:    baseCurrency,
    );
  }
}
    

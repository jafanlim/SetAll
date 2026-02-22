import 'package:decimal/decimal.dart';
import '../../data/repositories/setall_repository.dart';
import 'currency_service.dart';

class BalanceService {
  BalanceService({
    required SetAllRepository repository,
    required CurrencyService currencyService, // Kept for DI compatibility
  })  : _repo = repository,
        _currency = currencyService;

  final SetAllRepository _repo;
  final CurrencyService _currency;

  Future<String> getBaseCurrency() async {
    final profile = await _repo.getCurrentUserProfile();
    return profile?.defaultCurrency ?? 'USD';
  }

  Future<BalanceSummary> getBalanceSummary() async {
    final uid = await _repo.ensureUser();
    if (uid == null) return const BalanceSummary();

    try { await _repo.syncIfOnline(); } catch (_) {}
    
    final baseCurrency = await getBaseCurrency();
    final raw = await _repo.getBalanceRawData(uid);
    var youOwe = Decimal.zero;
    var youAreOwed = Decimal.zero;

    // Splits are natively in USD! Sum them, then convert to base currency.
    for (final e in raw.youOwe) {
      youOwe += e.amount;
    }
    for (final e in raw.youAreOwed) {
      youAreOwed += e.amount;
    }

    // Convert final totals from USD to user's base currency.
    Decimal rateToBase = Decimal.one;
    if (baseCurrency != 'USD') {
      rateToBase = await _currency.getRate('USD', baseCurrency);
    }
    
    final youOweConverted = (youOwe * rateToBase).round(scale: 2);
    final youAreOwedConverted = (youAreOwed * rateToBase).round(scale: 2);

    return BalanceSummary(
      youOwe: youOweConverted.toStringAsFixed(2),
      youAreOwed: youAreOwedConverted.toStringAsFixed(2),
      currency: baseCurrency,
    );
  }

  Future<BalanceSummary> getGroupBalanceSummary(String groupId) async {
    final uid = await _repo.ensureUser();
    if (uid == null) return const BalanceSummary();

    try { await _repo.syncIfOnline(); } catch (_) {}

    final baseCurrency = await getBaseCurrency();
    final raw = await _repo.getGroupBalanceRawData(uid, groupId);
    if (raw == null) return BalanceSummary(currency: baseCurrency);

    var youOwe = Decimal.zero;
    var youAreOwed = Decimal.zero;
    
    for (final e in raw.youOwe) {
      youOwe += e.amount;
    }
    for (final e in raw.youAreOwed) {
      youAreOwed += e.amount;
    }

    // Convert final totals from USD to user's base currency.
    Decimal rateToBase = Decimal.one;
    if (baseCurrency != 'USD') {
      rateToBase = await _currency.getRate('USD', baseCurrency);
    }

    final youOweConverted = (youOwe * rateToBase).round(scale: 2);
    final youAreOwedConverted = (youAreOwed * rateToBase).round(scale: 2);

    return BalanceSummary(
      youOwe: youOweConverted.toStringAsFixed(2),
      youAreOwed: youAreOwedConverted.toStringAsFixed(2),
      currency: baseCurrency,
    );
  }
} 

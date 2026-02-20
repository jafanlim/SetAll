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
    
    final raw = await _repo.getBalanceRawData(uid);
    var youOwe = Decimal.zero;
    var youAreOwed = Decimal.zero;

    // Splits are already in USD natively from the DB. Just sum them.
    for (final e in raw.youOwe) youOwe += e.amount;
    for (final e in raw.youAreOwed) youAreOwed += e.amount;

    return BalanceSummary(
      youOwe: youOwe.toStringAsFixed(2),
      youAreOwed: youAreOwed.toStringAsFixed(2),
      currency: 'USD', // The raw balance is ALWAYS USD now.
    );
  }

  Future<BalanceSummary> getGroupBalanceSummary(String groupId) async {
    final uid = await _repo.ensureUser();
    if (uid == null) return const BalanceSummary();

    try { await _repo.syncIfOnline(); } catch (_) {}

    final raw = await _repo.getGroupBalanceRawData(uid, groupId);
    if (raw == null) return const BalanceSummary(currency: 'USD');

    var youOwe = Decimal.zero;
    var youAreOwed = Decimal.zero;
    
    for (final e in raw.youOwe) youOwe += e.amount;
    for (final e in raw.youAreOwed) youAreOwed += e.amount;

    return BalanceSummary(
      youOwe: youOwe.toStringAsFixed(2),
      youAreOwed: youAreOwed.toStringAsFixed(2),
      currency: 'USD',
    );
  }
} 

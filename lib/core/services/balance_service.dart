import 'package:decimal/decimal.dart';

import '../../data/repositories/setall_repository.dart';
import 'currency_service.dart';

/// Multi-currency balance: all split amounts converted to the user's base
/// currency before summing.
///
/// Conversion priority per [BalanceEntry]:
///  1. [BalanceEntry.baseAmountAtEntry] – frozen value written at entry time
///     (schema v4+). Fastest path: no API call, immune to rate drift, works
///     fully offline. Eliminates the "$104 bug".
///  2. Currency match – if the expense currency equals the user's base currency
///     the split amount is already correct.
///  3. [BalanceEntry.exchangeRateApplied] – rate persisted at entry (v3+ data).
///     Avoids live-rate drift for historical expenses.
///  4. Live rate from [CurrencyService] – last resort for v1-v2 legacy data.
class BalanceService {
  BalanceService({
    required SetAllRepository repository,
    required CurrencyService currencyService,
  })  : _repo = repository,
        _currency = currencyService;

  final SetAllRepository _repo;
  final CurrencyService _currency;

  static const String _defaultBaseCurrency = 'USD';

  Future<String> getBaseCurrency() async {
    final profile = await _repo.getCurrentUserProfile();
    return profile?.defaultCurrency ?? _defaultBaseCurrency;
  }

  /// Global net balance (you are owed / you owe), in user's base currency.
  Future<BalanceSummary> getBalanceSummary() async {
    final uid = await _repo.ensureUser();
    if (uid == null) return const BalanceSummary();

    try {
      await _repo.syncIfOnline();
    } catch (_) {
      // Sync failure is non-fatal — continue with cached/local data.
    }
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

    try {
      await _repo.syncIfOnline();
    } catch (_) {
      // Sync failure is non-fatal — continue with cached/local data.
    }
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

  /// Convert a split entry to [baseCurrency] using Decimal arithmetic.
  Future<Decimal> _toBase(BalanceEntry e, String baseCurrency) async {
    // Priority 1: pre-computed base amount (schema v4+, zero API calls needed)
    if (e.baseAmountAtEntry != null) return e.baseAmountAtEntry!;

    // Priority 2: split already in base currency (new data, v1-v3)
    if (e.currency == baseCurrency) return e.amount;

    // Priority 3: use the rate persisted at entry time (v3 legacy data)
    if (e.exchangeRateApplied != null) {
      final stored = Decimal.tryParse(e.exchangeRateApplied!);
      if (stored != null && stored > Decimal.zero) {
        return (e.amount * stored).round(scale: 2);
      }
    }

    // Priority 4: live rate lookup (v1-v2 legacy data, last resort)
    try {
      final rate = await _currency.getRate(e.currency, baseCurrency);
      return (e.amount * rate).round(scale: 2);
    } catch (_) {
      // Priority 5: graceful degradation — return raw amount and surface it
      // as-is so balance still renders rather than crashing. Mis-currency data
      // will be off until rates are available, but the dashboard stays usable.
      return e.amount.round(scale: 2);
    }
  }
}

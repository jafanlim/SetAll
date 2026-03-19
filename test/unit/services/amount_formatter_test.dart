import 'package:flutter_test/flutter_test.dart';
import 'package:setall/core/utils/amount_formatter.dart';

void main() {
  group('decimalPlacesFor', () {
    test('USD → 2', () => expect(decimalPlacesFor('USD'), 2));
    test('EUR → 2', () => expect(decimalPlacesFor('EUR'), 2));
    test('GBP → 2', () => expect(decimalPlacesFor('GBP'), 2));
    test('JPY → 0', () => expect(decimalPlacesFor('JPY'), 0));
    test('KRW → 0', () => expect(decimalPlacesFor('KRW'), 0));
    test('VND → 0', () => expect(decimalPlacesFor('VND'), 0));
    test('IDR → 0', () => expect(decimalPlacesFor('IDR'), 0));
    test('BTC → 6', () => expect(decimalPlacesFor('BTC'), 6));
    test('ETH → 6', () => expect(decimalPlacesFor('ETH'), 6));
    test('case insensitive', () => expect(decimalPlacesFor('jpy'), 0));
  });

  group('formatAmount (always 2dp)', () {
    test('null → 0.00',           () => expect(formatAmount(null),    '0.00'));
    test('empty → 0.00',          () => expect(formatAmount(''),      '0.00'));
    test('100 → 100.00',          () => expect(formatAmount('100'),   '100.00'));
    test('99.5 → 99.50',          () => expect(formatAmount('99.5'),  '99.50'));
    test('0.001 → 0.00',          () => expect(formatAmount('0.001'), '0.00'));
    test('not a number → raw',    () => expect(formatAmount('abc'),   'abc'));
  });

  group('formatAmountForCurrency', () {
    test('USD 12.5 → 12.50',      () => expect(formatAmountForCurrency('12.5',     'USD'), '12.50'));
    test('JPY 1500 → 1500',       () => expect(formatAmountForCurrency('1500',     'JPY'), '1500'));
    test('JPY 1500.9 → 1501',     () => expect(formatAmountForCurrency('1500.9',   'JPY'), '1501'));
    test('KRW null → 0',          () => expect(formatAmountForCurrency(null,       'KRW'), '0'));
    test('BTC 0.00045 → 0.00045', () => expect(formatAmountForCurrency('0.00045',  'BTC'), '0.00045'));
    test('BTC 1.0 → 1.00',        () => expect(formatAmountForCurrency('1.0',      'BTC'), '1.00'));
    test('ETH 0.000001 → 0.000001', () => expect(formatAmountForCurrency('0.000001', 'ETH'), '0.000001'));
    test('USD null → 0.00',       () => expect(formatAmountForCurrency(null,       'USD'), '0.00'));
    test('non-parseable → raw',   () => expect(formatAmountForCurrency('abc',      'USD'), 'abc'));
  });
}

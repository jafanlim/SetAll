// Unit tests for CsvAdapter — pure Dart, no DB, no Flutter.
// Covers SetAll wallet export format and Splitwise format parsing.

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:setall/core/services/csv_adapter.dart';

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 1 — SetAll wallet export format
  // ──────────────────────────────────────────────────────────────────────────
  group('CsvAdapter: SetAll wallet format', () {
    const setAllCsv = '''Date,Description,Category,Amount,Currency,Type
2026-05-01,Grocery run,Food & drink,45.50,USD,expense
2026-05-03,Coffee shop,Food & drink,8.20,EUR,expense
2026-05-05,Freelance payment,Income,1200.00,GBP,income
''';

    test('parses all rows', () {
      final result = CsvAdapter.parse(setAllCsv);
      expect(result.errors, isEmpty);
      expect(result.rows, hasLength(3));
    });

    test('parses date correctly', () {
      final result = CsvAdapter.parse(setAllCsv);
      expect(result.rows.first.date, DateTime(2026, 5, 1));
    });

    test('parses description', () {
      final result = CsvAdapter.parse(setAllCsv);
      expect(result.rows.first.description, 'Grocery run');
    });

    test('parses category', () {
      final result = CsvAdapter.parse(setAllCsv);
      expect(result.rows.first.category, 'Food & drink');
    });

    test('parses amount as absolute Decimal', () {
      final result = CsvAdapter.parse(setAllCsv);
      expect(result.rows.first.cost, Decimal.parse('45.50'));
    });

    test('parses currency uppercased', () {
      final result = CsvAdapter.parse(setAllCsv);
      expect(result.rows[1].currency, 'EUR');
    });

    test('isIncome false for expense rows', () {
      final result = CsvAdapter.parse(setAllCsv);
      expect(result.rows[0].isIncome, isFalse);
      expect(result.rows[1].isIncome, isFalse);
    });

    test('isIncome true for income rows', () {
      final result = CsvAdapter.parse(setAllCsv);
      expect(result.rows[2].isIncome, isTrue);
    });

    test('csvNames and personAmounts empty for SetAll format', () {
      final result = CsvAdapter.parse(setAllCsv);
      for (final row in result.rows) {
        expect(row.csvNames, isEmpty);
        expect(row.personAmounts, isEmpty);
        expect(row.payerCsvName, isNull);
      }
    });

    test('skips zero-amount rows', () {
      const csv = '''Date,Description,Category,Amount,Currency,Type
2026-05-01,Zero,General,0.00,USD,expense
2026-05-02,Real,General,10.00,USD,expense
''';
      final result = CsvAdapter.parse(csv);
      expect(result.rows, hasLength(1));
      expect(result.rows.first.description, 'Real');
    });

    test('skips total/summary rows', () {
      const csv = '''Date,Description,Category,Amount,Currency,Type
Total,,,,USD,
2026-05-01,Rent,General,500.00,USD,expense
''';
      final result = CsvAdapter.parse(csv);
      expect(result.rows, hasLength(1));
    });

    test('records error for unparseable date', () {
      const csv = '''Date,Description,Category,Amount,Currency,Type
not-a-date,Bad row,General,10.00,USD,expense
2026-05-01,Good row,General,5.00,USD,expense
''';
      final result = CsvAdapter.parse(csv);
      expect(result.errors, hasLength(1));
      expect(result.rows, hasLength(1));
    });

    test('records error for unparseable amount', () {
      const csv = '''Date,Description,Category,Amount,Currency,Type
2026-05-01,Bad amount,General,abc,USD,expense
2026-05-02,Good,General,5.00,USD,expense
''';
      final result = CsvAdapter.parse(csv);
      expect(result.errors, hasLength(1));
      expect(result.rows, hasLength(1));
    });

    test('cost is absolute value (negative amounts stored positive)', () {
      const csv = '''Date,Description,Category,Amount,Currency,Type
2026-05-01,Expense,-45.50,USD,expense
''';
      final result = CsvAdapter.parse(csv);
      if (result.rows.isNotEmpty) {
        expect(result.rows.first.cost, greaterThan(Decimal.zero));
      }
    });

    test('missing header returns error', () {
      const csv = 'foo,bar,baz\n1,2,3\n';
      final result = CsvAdapter.parse(csv);
      expect(result.rows, isEmpty);
      expect(result.errors, isNotEmpty);
    });

    test('empty string returns error', () {
      final result = CsvAdapter.parse('');
      expect(result.rows, isEmpty);
      expect(result.errors, isNotEmpty);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 2 — Splitwise format
  // ──────────────────────────────────────────────────────────────────────────
  group('CsvAdapter: Splitwise format', () {
    const splitwiseCsv = '''Date,Description,Category,Cost,Currency,Alice,Bob
2026-05-01,Dinner,Food,60.00,USD,40.00,-20.00
2026-05-10,Taxi,Transport,30.00,EUR,30.00,-15.00
''';

    test('parses rows', () {
      final result = CsvAdapter.parse(splitwiseCsv);
      expect(result.errors, isEmpty);
      expect(result.rows, hasLength(2));
    });

    test('parses cost', () {
      final result = CsvAdapter.parse(splitwiseCsv);
      expect(result.rows.first.cost, Decimal.parse('60.00'));
    });

    test('detects payer (positive person column)', () {
      final result = CsvAdapter.parse(splitwiseCsv);
      expect(result.rows.first.payerCsvName, 'Alice');
    });

    test('collects csvNames for all participants', () {
      final result = CsvAdapter.parse(splitwiseCsv);
      expect(result.rows.first.csvNames, containsAll(['Alice', 'Bob']));
    });

    test('personAmounts has signed values', () {
      final result = CsvAdapter.parse(splitwiseCsv);
      final amounts = result.rows.first.personAmounts;
      expect(amounts['Alice'], Decimal.parse('40.00'));
      expect(amounts['Bob'],   Decimal.parse('-20.00'));
    });

    test('isIncome defaults to false for Splitwise rows', () {
      final result = CsvAdapter.parse(splitwiseCsv);
      expect(result.rows.first.isIncome, isFalse);
    });

    test('currency uppercased', () {
      final result = CsvAdapter.parse(splitwiseCsv);
      expect(result.rows[1].currency, 'EUR');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 3 — Quoted CSV fields
  // ──────────────────────────────────────────────────────────────────────────
  group('CsvAdapter: quoted fields', () {
    test('handles quoted description with comma', () {
      const csv = '''Date,Description,Category,Amount,Currency,Type
2026-05-01,"Coffee, large",Food & drink,4.50,USD,expense
''';
      final result = CsvAdapter.parse(csv);
      expect(result.rows, hasLength(1));
      expect(result.rows.first.description, 'Coffee, large');
    });

    test('handles escaped double-quote inside field', () {
      const csv = 'Date,Description,Category,Amount,Currency,Type\n'
          '2026-05-01,"Say ""hi""",General,1.00,USD,expense\n';
      final result = CsvAdapter.parse(csv);
      expect(result.rows, hasLength(1));
      expect(result.rows.first.description, 'Say "hi"');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 4 — Multi-currency correctness (regression for import-parity fix)
  // ──────────────────────────────────────────────────────────────────────────
  group('CsvAdapter: multi-currency import parity', () {
    const multiCurrencyCsv = '''Date,Description,Category,Amount,Currency,Type
2026-05-01,USD entry,General,100.00,USD,expense
2026-05-02,EUR entry,General,200.00,EUR,expense
2026-05-03,GBP entry,General,300.00,GBP,expense
2026-05-04,Income GBP,General,500.00,GBP,income
''';

    test('all four rows parsed without errors', () {
      final result = CsvAdapter.parse(multiCurrencyCsv);
      expect(result.errors, isEmpty);
      expect(result.rows, hasLength(4));
    });

    test('currencies preserved exactly', () {
      final result = CsvAdapter.parse(multiCurrencyCsv);
      final currencies = result.rows.map((r) => r.currency).toList();
      expect(currencies, ['USD', 'EUR', 'GBP', 'GBP']);
    });

    test('amounts preserved exactly', () {
      final result = CsvAdapter.parse(multiCurrencyCsv);
      expect(result.rows[0].cost, Decimal.parse('100.00'));
      expect(result.rows[1].cost, Decimal.parse('200.00'));
      expect(result.rows[2].cost, Decimal.parse('300.00'));
      expect(result.rows[3].cost, Decimal.parse('500.00'));
    });

    test('isIncome correct per row', () {
      final result = CsvAdapter.parse(multiCurrencyCsv);
      expect(result.rows[0].isIncome, isFalse);
      expect(result.rows[3].isIncome, isTrue);
    });
  });
}

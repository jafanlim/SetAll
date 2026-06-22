import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';

// ---------------------------------------------------------------------------
// Public row type (formerly _SplitwiseRow in splitwise_import_screen.dart)
// ---------------------------------------------------------------------------
class SplitwiseRow {
  const SplitwiseRow({
    required this.date,
    required this.description,
    required this.category,
    required this.cost,
    required this.currency,
    required this.csvNames,
    required this.payerCsvName,
    required this.personAmounts,
    this.isIncome = false,
  });

  final DateTime             date;
  final String               description;
  final String               category;
  final Decimal              cost;
  final String               currency;
  final bool                 isIncome;      // SetAll export: true for income rows
  final List<String>         csvNames;      // all participants (non-zero amount)
  final String?              payerCsvName;  // CSV column name of whoever paid (positive value)
  final Map<String, Decimal> personAmounts; // csvName → signed amount (+payer credit, -owes)
}

// ---------------------------------------------------------------------------
// CsvAdapter
// Parses a Splitwise CSV or SetAll wallet export into SplitwiseRow list.
// Pure Dart — no Flutter deps, no Riverpod.
// ---------------------------------------------------------------------------
class CsvAdapter {
  CsvAdapter._();

  /// Returns `({rows, errors})`.
  /// Supports two CSV formats:
  ///   Splitwise: Date, Description, [Category], Cost, Currency, [person cols…]
  ///   SetAll:    Date, Description, Category, Amount, Currency, Type
  static ({List<SplitwiseRow> rows, List<String> errors}) parse(String raw) {
    final lines = raw.split(RegExp(r'\r?\n'));
    if (lines.isEmpty) return (rows: [], errors: ['Empty file']);

    int headerIdx = -1;
    List<String> headers         = [];
    List<String> originalHeaders = [];
    bool isSetAllFormat = false;

    for (int i = 0; i < lines.length; i++) {
      final cols = _splitCsvLine(lines[i]);
      if (cols.length >= 4) {
        final lower = cols.map((c) => c.toLowerCase().trim()).toList();
        // SetAll wallet export format
        if (lower.contains('date') && lower.contains('description') &&
            lower.contains('amount') && lower.contains('currency') &&
            lower.contains('type')) {
          headerIdx       = i;
          headers         = lower;
          originalHeaders = cols.map((c) => c.trim()).toList();
          isSetAllFormat  = true;
          break;
        }
        // Splitwise format
        if (lower.contains('date') && lower.contains('description') &&
            lower.contains('cost') && lower.contains('currency')) {
          headerIdx       = i;
          headers         = lower;
          originalHeaders = cols.map((c) => c.trim()).toList();
          break;
        }
      }
    }
    if (headerIdx < 0) {
      return (rows: [], errors: [
        'Could not find a header row.\n'
        'Expected Splitwise format: Date, Description, Cost, Currency\n'
        'or SetAll export format: Date, Description, Category, Amount, Currency, Type',
      ]);
    }

    final dateIdx     = headers.indexOf('date');
    final descIdx     = headers.indexOf('description');
    final catIdx      = headers.indexWhere((h) => h.contains('category'));
    final currencyIdx = headers.indexOf('currency');

    if (isSetAllFormat) {
      return _parseSetAll(
        lines:        lines,
        headers:      headers,
        headerIdx:    headerIdx,
        dateIdx:      dateIdx,
        descIdx:      descIdx,
        catIdx:       catIdx,
        currencyIdx:  currencyIdx,
      );
    }

    return _parseSplitwise(
      lines:           lines,
      headers:         headers,
      originalHeaders: originalHeaders,
      headerIdx:       headerIdx,
      dateIdx:         dateIdx,
      descIdx:         descIdx,
      catIdx:          catIdx,
      currencyIdx:     currencyIdx,
    );
  }

  // ── SetAll wallet CSV ──────────────────────────────────────────────────────
  static ({List<SplitwiseRow> rows, List<String> errors}) _parseSetAll({
    required List<String> lines,
    required List<String> headers,
    required int headerIdx,
    required int dateIdx,
    required int descIdx,
    required int catIdx,
    required int currencyIdx,
  }) {
    final amountIdx = headers.indexOf('amount');
    final typeIdx   = headers.indexOf('type');
    final rows   = <SplitwiseRow>[];
    final errors = <String>[];

    for (int i = headerIdx + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;
      final cols = _splitCsvLine(line);
      if (cols.length <= amountIdx || cols.length <= currencyIdx) continue;

      final rawDate = _col(cols, dateIdx);
      if (rawDate.toLowerCase().contains('total') || rawDate.isEmpty) continue;

      DateTime? date;
      for (final fmt in ['yyyy-MM-dd', 'MM/dd/yyyy', 'dd/MM/yyyy', 'yyyy/MM/dd']) {
        try { date = DateFormat(fmt).parseStrict(rawDate.trim()); break; } catch (_) {}
      }
      if (date == null) {
        errors.add('Row ${i + 1}: unrecognised date "$rawDate" — skipped');
        continue;
      }

      final rawAmt = _col(cols, amountIdx).replaceAll(RegExp(r'[,\s]'), '');
      Decimal? amt;
      try {
        amt = Decimal.parse(rawAmt.isEmpty ? '0' : rawAmt);
      } catch (_) {
        errors.add('Row ${i + 1}: invalid amount "$rawAmt" — skipped');
        continue;
      }
      if (amt == Decimal.zero) continue;

      final typeStr  = typeIdx >= 0 ? _col(cols, typeIdx).toLowerCase() : '';
      final isIncome = typeStr == 'income';
      final description = _col(cols, descIdx).isEmpty ? 'Imported entry' : _col(cols, descIdx);
      final category    = catIdx >= 0 ? _col(cols, catIdx) : 'General';
      final currency    = _col(cols, currencyIdx).isEmpty ? 'USD' : _col(cols, currencyIdx).toUpperCase();

      rows.add(SplitwiseRow(
        date:          date,
        description:   description,
        category:      category.isEmpty ? 'General' : category,
        cost:          amt.abs(),
        currency:      currency,
        isIncome:      isIncome,
        csvNames:      [],
        payerCsvName:  null,
        personAmounts: {},
      ));
    }
    return (rows: rows, errors: errors);
  }

  // ── Splitwise CSV ──────────────────────────────────────────────────────────
  static ({List<SplitwiseRow> rows, List<String> errors}) _parseSplitwise({
    required List<String> lines,
    required List<String> headers,
    required List<String> originalHeaders,
    required int headerIdx,
    required int dateIdx,
    required int descIdx,
    required int catIdx,
    required int currencyIdx,
  }) {
    final costIdx = headers.indexOf('cost');

    const fixedCols = {
      'date', 'description', 'category', 'cost', 'currency',
      'balance', 'id', 'notes', 'for you', 'your share', 'net balance',
    };
    final personCols = <int, String>{};
    for (int i = 0; i < headers.length; i++) {
      final h = headers[i].trim();
      if (h.isNotEmpty && !fixedCols.any((f) => h.contains(f))) {
        personCols[i] = originalHeaders[i];
      }
    }

    final rows   = <SplitwiseRow>[];
    final errors = <String>[];

    for (int i = headerIdx + 1; i < lines.length; i++) {
      final line = lines[i].trim();
      if (line.isEmpty) continue;

      final cols = _splitCsvLine(line);
      if (cols.length <= costIdx || cols.length <= currencyIdx) continue;

      final rawDate = _col(cols, dateIdx);
      if (rawDate.toLowerCase().contains('total') || rawDate.isEmpty) continue;

      DateTime? date;
      for (final fmt in ['yyyy-MM-dd', 'MM/dd/yyyy', 'dd/MM/yyyy', 'yyyy/MM/dd']) {
        try { date = DateFormat(fmt).parseStrict(rawDate.trim()); break; } catch (_) {}
      }
      if (date == null) {
        errors.add('Row ${i + 1}: unrecognised date "$rawDate" — skipped');
        continue;
      }

      final rawCost = _col(cols, costIdx).replaceAll(RegExp(r'[,\s]'), '');
      Decimal? cost;
      try {
        cost = Decimal.parse(rawCost.isEmpty ? '0' : rawCost);
      } catch (_) {
        errors.add('Row ${i + 1}: invalid cost "$rawCost" — skipped');
        continue;
      }
      if (cost == Decimal.zero) continue;

      final description = _col(cols, descIdx).isEmpty ? 'Imported expense' : _col(cols, descIdx);
      final category    = catIdx >= 0 ? _col(cols, catIdx) : 'General';
      final currency    = _col(cols, currencyIdx).isEmpty ? 'USD' : _col(cols, currencyIdx).toUpperCase();

      final rowNames      = <String>[];
      final personAmounts = <String, Decimal>{};
      String? payerCsvName;
      for (final entry in personCols.entries) {
        final rawVal = _col(cols, entry.key).replaceAll(RegExp(r'[,\s]'), '');
        if (rawVal.isEmpty || rawVal == '0' || rawVal == '0.00') continue;
        Decimal? parsed;
        try { parsed = Decimal.parse(rawVal); } catch (_) { continue; }
        final name = entry.value;
        rowNames.add(name);
        personAmounts[name] = parsed;
        if (parsed > Decimal.zero) payerCsvName = name;
      }

      rows.add(SplitwiseRow(
        date:          date,
        description:   description,
        category:      category.isEmpty ? 'General' : category,
        cost:          cost.abs(),
        currency:      currency,
        csvNames:      rowNames,
        payerCsvName:  payerCsvName,
        personAmounts: personAmounts,
      ));
    }

    return (rows: rows, errors: errors);
  }

  // ── Helpers ────────────────────────────────────────────────────────────────
  static String _col(List<String> cols, int idx) =>
      idx >= 0 && idx < cols.length ? cols[idx].trim() : '';

  static List<String> _splitCsvLine(String line) {
    final result  = <String>[];
    final buffer  = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (ch == ',' && !inQuotes) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(ch);
      }
    }
    result.add(buffer.toString());
    return result;
  }
}

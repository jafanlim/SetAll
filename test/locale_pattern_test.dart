import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  await initializeDateFormatting();
  test('Georgia region locale candidates', () {
    // macOS Locale.current.identifier with English language + Georgia region
    // can return various forms — test all candidates
    for (final loc in ['en_GE', 'ka_GE', 'ka', 'en_001', 'en_GE@calendar=gregorian']) {
      try {
        final pattern = DateFormat.yMd(loc).pattern ?? 'null';
        print('$loc → $pattern');
      } catch (e) {
        print('$loc → ERROR: $e');
      }
    }
  });
}

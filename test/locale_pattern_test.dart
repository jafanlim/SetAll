import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() async {
  await initializeDateFormatting();
  test('Intl.systemLocale and yMd pattern', () {
    print('Intl.systemLocale = ${Intl.systemLocale}');
    final sysPattern = DateFormat.yMd(Intl.systemLocale).pattern ?? 'null';
    print('yMd(systemLocale) = $sysPattern');
    for (final loc in ['en_US', 'ka_GE', 'ka', 'en_NZ', 'en_AU']) {
      final pattern = DateFormat.yMd(loc).pattern ?? 'null';
      print('$loc: $pattern');
    }
  });
}

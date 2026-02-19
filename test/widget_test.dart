// Basic Flutter widget test for SetAll app.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:setall/app.dart';

void main() {
  testWidgets('App loads and shows SetAll', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: SetAllApp(),
      ),
    );

    expect(find.text('SetAll'), findsOneWidget);
  });
}

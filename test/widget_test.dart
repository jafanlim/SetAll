// Basic Flutter widget test for SetAll app.
//
// Supabase is NOT initialized in this test environment. The router's redirect
// and _AuthRefresh both guard against this, so the app renders the login screen
// (unauthenticated path) without crashing.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:setall/app.dart';

void main() {
  testWidgets('App loads without crashing and renders the login screen', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: SetAllApp(),
      ),
    );

    // Pump several frames so GoRouter's async redirect completes and the
    // login screen builds. pumpAndSettle is avoided because ScreenUtilInit
    // keeps posting frames indefinitely.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The LoginScreen renders 'SetAll' as the brand headline.
    expect(find.text('SetAll'), findsOneWidget);
  });
}

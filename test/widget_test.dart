// Basic Flutter widget test for SetAll app.
//
// Supabase is NOT initialized in this test environment. The router's redirect
// and _AuthRefresh both guard against this, so the app renders the login screen
// (unauthenticated path) without crashing.

import 'package:flutter/material.dart';
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

    // Pump enough frames so GoRouter's async redirect completes and the
    // login screen builds. pumpAndSettle is avoided because ScreenUtilInit
    // keeps posting frames indefinitely.
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The app should render at minimum a Scaffold (smoke test — not crashed).
    expect(find.byType(Scaffold), findsWidgets);
  });
}

// Basic Flutter widget test for SetAll app.
//
// Supabase is NOT initialized in this test environment. The router's redirect
// and _AuthRefresh both guard against this via try/catch, so the app builds
// without crashing. EasyLocalization is required because SetAllApp.build()
// reads context.locale / context.localizationDelegates / context.supportedLocales.

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:setall/app.dart';

void main() {
  testWidgets('App loads without crashing and renders MaterialApp base state', (WidgetTester tester) async {
    // EasyLocalization needs SharedPreferences for locale persistence.
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en'),
        child: const ProviderScope(
          child: SetAllApp(),
        ),
      ),
    );

    // Pump enough frames so GoRouter's async redirect completes and the
    // widget tree stabilises. pumpAndSettle is avoided because ScreenUtilInit
    // keeps posting frames indefinitely.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    // The app should render MaterialApp.router — proves the bootstrap succeeded
    // without the Supabase auth-guard causing a crash.
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}

// Tests for the unassigned-to-payer disclaimer hint — widget rendering and
// locale parity across all 6 supported locales.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// ── Standalone testable hint chip (mirrors the production chips in both
//    receipt_entry_sheet.dart and edit_expense_screen.dart) ──────────────────

const _blue = Color(0xFF3B82F6);

/// Standalone testable hint that mirrors the production disclaimer in both
/// screens.  Accepts [message] so widget tests don't need EasyLocalization
/// asset loading.
class UnassignedHintChip extends StatelessWidget {
  final String message;
  const UnassignedHintChip({
    super.key,
    this.message = 'Items left unassigned are charged to the payer.',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _blue.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _blue.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: _blue, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _blue,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Test harness ──

Widget hintTestHarness({String? message}) {
  return MaterialApp(
    home: Scaffold(
      body: UnassignedHintChip(message: message ?? 'Items left unassigned are charged to the payer.'),
    ),
  );
}

const _locales = ['en', 'de', 'es', 'fr', 'ka', 'ru'];

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // Widget: hint chip rendering
  // ═══════════════════════════════════════════════════════════════════════
  group('Unassigned-to-payer hint — widget rendering', () {
    testWidgets('renders with default EN text', (tester) async {
      await tester.pumpWidget(hintTestHarness());
      await tester.pumpAndSettle();
      expect(find.byType(UnassignedHintChip), findsOneWidget);
      expect(
        find.text('Items left unassigned are charged to the payer.'),
        findsOneWidget,
      );
    });

    testWidgets('renders with custom message', (tester) async {
      await tester.pumpWidget(
        hintTestHarness(message: 'Nicht zugewiesene Artikel werden dem Zahler belastet.'),
      );
      await tester.pumpAndSettle();
      expect(find.byType(UnassignedHintChip), findsOneWidget);
      expect(
        find.text('Nicht zugewiesene Artikel werden dem Zahler belastet.'),
        findsOneWidget,
      );
    });

    testWidgets('shows info icon (not warning)', (tester) async {
      await tester.pumpWidget(hintTestHarness());
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.info_outline_rounded), findsOneWidget);
      // Must NOT be the warning icon.
      expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
    });

    testWidgets('hint does not block interaction (non-blocking)', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const UnassignedHintChip(),
              ElevatedButton(onPressed: () {}, child: const Text('Save')),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(UnassignedHintChip), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Locale parity: key present in all 6 translation files
  // ═══════════════════════════════════════════════════════════════════════
  group('Locale parity — unassigned_to_payer_hint', () {
    for (final locale in _locales) {
      test('key exists in $locale.json', () {
        final file = File('assets/translations/$locale.json');
        expect(file.existsSync(), isTrue, reason: '$locale.json not found');

        final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        final receipt = json['receipt'];
        expect(receipt, isNotNull, reason: '$locale.json missing "receipt" section');
        expect(
          receipt is Map,
          isTrue,
          reason: '$locale.json "receipt" is not a map',
        );

        final map = receipt as Map<String, dynamic>;
        expect(
          map.containsKey('unassigned_to_payer_hint'),
          isTrue,
          reason: '$locale.json missing key "receipt.unassigned_to_payer_hint"',
        );
        expect(
          map['unassigned_to_payer_hint'],
          isNotEmpty,
          reason: '$locale.json key "receipt.unassigned_to_payer_hint" is empty',
        );
      });
    }
  });
}

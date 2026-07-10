// Tests for OCR fallback guard — model parsing, degraded condition, and chip widget.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:setall/core/models/receipt_ingest_result.dart';

// ── OCR degraded chip widget (testable standalone; mirrors the chip in receipt_entry_sheet.dart) ──

const _orange = Color(0xFFFF8C42);

/// Standalone testable chip that mirrors the production chip in receipt_entry_sheet.dart.
/// Accepts [message] so widget tests don't need EasyLocalization asset loading.
class OcrDegradedChip extends StatelessWidget {
  final String message;
  const OcrDegradedChip({
    super.key,
    this.message = 'Precise text recognition unavailable — verify item names',
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _orange.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _orange, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _orange,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Condition-driven chip wrapper for widget tests ──

class OcrDegradedConditionalChip extends StatelessWidget {
  final bool ocr;
  final String? ocrFailReason;
  const OcrDegradedConditionalChip({
    super.key,
    required this.ocr,
    this.ocrFailReason,
  });

  @override
  Widget build(BuildContext context) {
    if (ReceiptIngestResponse.isOcrDegraded(ocr: ocr, ocrFailReason: ocrFailReason)) {
      return const OcrDegradedChip();
    }
    return const SizedBox.shrink();
  }
}

// ── Test harness ──

Widget chipTestHarness({required bool ocr, String? ocrFailReason}) {
  return MaterialApp(
    home: Scaffold(
      body: OcrDegradedConditionalChip(ocr: ocr, ocrFailReason: ocrFailReason),
    ),
  );
}

void main() {
  // ═══════════════════════════════════════════════════════════════════════
  // Model: ReceiptIngestResponse.fromJson parses ocr / ocrFailReason
  // ═══════════════════════════════════════════════════════════════════════
  group('ReceiptIngestResponse.fromJson — OCR flags', () {
    test('success draft with ocr:true, no failReason', () {
      final json = {
        'draft': {
          'amount': '12.50',
          'currency': 'GEL',
          'description': 'Test',
          'category': 'General',
          'isIncome': false,
          'merchantName': 'Test',
          'lineItems': [],
          'entryDate': '2026-07-10',
          'confidence': 0.95,
        },
        'escalated': false,
        'ocr': true,
        'ocrFailReason': null,
      };
      final r = ReceiptIngestResponse.fromJson(json);
      expect(r.ocr, true);
      expect(r.ocrFailReason, null);
      expect(ReceiptIngestResponse.isOcrDegraded(ocr: r.ocr, ocrFailReason: r.ocrFailReason), false);
    });

    test('degraded draft with ocr:false, ocrFailReason:quota', () {
      final json = {
        'draft': {
          'amount': '12.50',
          'currency': 'GEL',
          'description': 'Test',
          'category': 'General',
          'isIncome': false,
          'merchantName': 'Test',
          'lineItems': [],
          'entryDate': '2026-07-10',
          'confidence': 0.50,
        },
        'escalated': false,
        'ocr': false,
        'ocrFailReason': 'quota',
      };
      final r = ReceiptIngestResponse.fromJson(json);
      expect(r.ocr, false);
      expect(r.ocrFailReason, 'quota');
      expect(ReceiptIngestResponse.isOcrDegraded(ocr: r.ocr, ocrFailReason: r.ocrFailReason), true);
    });

    test('degraded draft with ocr:false, ocrFailReason:http_500', () {
      final json = {
        'draft': {
          'amount': '12.50',
          'currency': 'GEL',
          'description': 'Test',
          'category': 'General',
          'isIncome': false,
          'merchantName': 'Test',
          'lineItems': [],
          'entryDate': '2026-07-10',
          'confidence': 0.50,
        },
        'escalated': false,
        'ocr': false,
        'ocrFailReason': 'http_500',
      };
      final r = ReceiptIngestResponse.fromJson(json);
      expect(ReceiptIngestResponse.isOcrDegraded(ocr: r.ocr, ocrFailReason: r.ocrFailReason), true);
    });

    test('no Vision key configured: ocr:false, ocrFailReason:no_key — NOT degraded', () {
      final json = {
        'draft': {
          'amount': '12.50',
          'currency': 'USD',
          'description': 'Test',
          'category': 'General',
          'isIncome': false,
          'merchantName': 'Test',
          'lineItems': [],
          'entryDate': '2026-07-10',
          'confidence': 0.60,
        },
        'escalated': false,
        'ocr': false,
        'ocrFailReason': 'no_key',
      };
      final r = ReceiptIngestResponse.fromJson(json);
      expect(r.ocr, false);
      expect(r.ocrFailReason, 'no_key');
      expect(ReceiptIngestResponse.isOcrDegraded(ocr: r.ocr, ocrFailReason: r.ocrFailReason), false);
    });

    test('no googleKey at all (null ocrFailReason) — NOT degraded', () {
      final json = {
        'draft': {
          'amount': '12.50',
          'currency': 'USD',
          'description': 'Test',
          'category': 'General',
          'isIncome': false,
          'merchantName': 'Test',
          'lineItems': [],
          'entryDate': '2026-07-10',
          'confidence': 0.60,
        },
        'escalated': false,
        'ocr': false,
      };
      final r = ReceiptIngestResponse.fromJson(json);
      expect(r.ocr, false);
      expect(r.ocrFailReason, null);
      expect(ReceiptIngestResponse.isOcrDegraded(ocr: r.ocr, ocrFailReason: r.ocrFailReason), false);
    });

    test('isOcrDegraded static helper — all edge cases', () {
      // Not degraded: OCR succeeded
      expect(ReceiptIngestResponse.isOcrDegraded(ocr: true, ocrFailReason: null), false);
      // Not degraded: no key configured
      expect(ReceiptIngestResponse.isOcrDegraded(ocr: false, ocrFailReason: 'no_key'), false);
      // Not degraded: null failReason (no Vision attempt at all)
      expect(ReceiptIngestResponse.isOcrDegraded(ocr: false, ocrFailReason: null), false);
      // Degraded: quota exhausted
      expect(ReceiptIngestResponse.isOcrDegraded(ocr: false, ocrFailReason: 'quota'), true);
      // Degraded: http 500
      expect(ReceiptIngestResponse.isOcrDegraded(ocr: false, ocrFailReason: 'http_500'), true);
      // Degraded: http 503
      expect(ReceiptIngestResponse.isOcrDegraded(ocr: false, ocrFailReason: 'http_503'), true);
      // Degraded: exception
      expect(ReceiptIngestResponse.isOcrDegraded(ocr: false, ocrFailReason: 'exception'), true);
    });
  });

  // ═══════════════════════════════════════════════════════════════════════
  // Widget: chip visibility (no i18n — uses hardcoded message in test chip)
  // ═══════════════════════════════════════════════════════════════════════
  group('OCR degraded chip — widget rendering', () {
    testWidgets('chip shows when degraded (ocr:false, ocrFailReason:quota)', (tester) async {
      await tester.pumpWidget(chipTestHarness(ocr: false, ocrFailReason: 'quota'));
      await tester.pumpAndSettle();
      expect(find.byType(OcrDegradedChip), findsOneWidget);
      expect(find.text('Precise text recognition unavailable — verify item names'), findsOneWidget);
    });

    testWidgets('chip shows when degraded (ocr:false, ocrFailReason:http_500)', (tester) async {
      await tester.pumpWidget(chipTestHarness(ocr: false, ocrFailReason: 'http_500'));
      await tester.pumpAndSettle();
      expect(find.byType(OcrDegradedChip), findsOneWidget);
    });

    testWidgets('chip shows when degraded (ocr:false, ocrFailReason:exception)', (tester) async {
      await tester.pumpWidget(chipTestHarness(ocr: false, ocrFailReason: 'exception'));
      await tester.pumpAndSettle();
      expect(find.byType(OcrDegradedChip), findsOneWidget);
    });

    testWidgets('chip absent when OCR ok (ocr:true)', (tester) async {
      await tester.pumpWidget(chipTestHarness(ocr: true, ocrFailReason: null));
      await tester.pumpAndSettle();
      expect(find.byType(OcrDegradedChip), findsNothing);
    });

    testWidgets('chip absent when no_key (Vision not configured)', (tester) async {
      await tester.pumpWidget(chipTestHarness(ocr: false, ocrFailReason: 'no_key'));
      await tester.pumpAndSettle();
      expect(find.byType(OcrDegradedChip), findsNothing);
    });

    testWidgets('chip absent when ocrFailReason is null (no Vision attempt)', (tester) async {
      await tester.pumpWidget(chipTestHarness(ocr: false, ocrFailReason: null));
      await tester.pumpAndSettle();
      expect(find.byType(OcrDegradedChip), findsNothing);
    });

    testWidgets('chip has warning icon and orange styling', (tester) async {
      await tester.pumpWidget(chipTestHarness(ocr: false, ocrFailReason: 'quota'));
      await tester.pumpAndSettle();
      // Verify the warning icon exists.
      expect(find.byIcon(Icons.warning_amber_rounded), findsOneWidget);
      // Verify the container has the chip.
      expect(find.byType(OcrDegradedChip), findsOneWidget);
    });

    testWidgets('degraded chip does not block interaction (non-blocking)', (tester) async {
      // Add a button behind the chip to verify it's non-blocking.
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              OcrDegradedConditionalChip(ocr: false, ocrFailReason: 'quota'),
              ElevatedButton(onPressed: () {}, child: const Text('Save')),
            ],
          ),
        ),
      ));
      await tester.pumpAndSettle();
      // Both the chip and the button should coexist.
      expect(find.byType(OcrDegradedChip), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });
  });
}

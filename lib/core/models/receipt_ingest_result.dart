// ── Receipt ingest models (FEAT-RECEIPT) ────────────────────────────────────
// Mirror of netlify/functions/receipt-ingest.js response shapes.
// Every money field is Decimal — never double.

import 'package:decimal/decimal.dart';

// ── Line item ───────────────────────────────────────────────────────────────

class LineItem {
  final String name;
  final String? originalName;
  final Decimal amount;
  final int quantity;

  const LineItem({
    required this.name,
    this.originalName,
    required this.amount,
    required this.quantity,
  });

  factory LineItem.fromJson(Map<String, dynamic> json) {
    return LineItem(
      name: json['name'] as String? ?? '',
      originalName: json['originalName'] as String?,
      amount: Decimal.parse(json['amount'] as String? ?? '0'),
      quantity: json['quantity'] as int? ?? 1,
    );
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        'originalName': originalName,
        'amount': amount.toString(),
        'quantity': quantity,
      };
}

// ── Receipt draft (server-validated, user-editable) ─────────────────────────

class ReceiptDraft {
  final Decimal amount;
  final String currency;
  final String description;
  final String? originalDescription;
  final String category;
  final bool isIncome;
  final String merchantName;
  final String? last4;
  final String? payerLabel;
  final String? payerProfileId;
  final List<LineItem> lineItems;
  final DateTime entryDate;
  final double confidence;

  const ReceiptDraft({
    required this.amount,
    required this.currency,
    required this.description,
    this.originalDescription,
    required this.category,
    required this.isIncome,
    required this.merchantName,
    this.last4,
    this.payerLabel,
    this.payerProfileId,
    required this.lineItems,
    required this.entryDate,
    required this.confidence,
  });

  factory ReceiptDraft.fromJson(Map<String, dynamic> json) {
    return ReceiptDraft(
      amount: Decimal.parse(json['amount'] as String? ?? '0'),
      currency: json['currency'] as String? ?? 'USD',
      description: json['description'] as String? ?? '',
      originalDescription: json['originalDescription'] as String?,
      category: json['category'] as String? ?? 'General',
      isIncome: json['isIncome'] as bool? ?? false,
      merchantName: json['merchantName'] as String? ?? '',
      last4: json['last4'] as String?,
      payerLabel: json['payerLabel'] as String?,
      payerProfileId: json['payerProfileId'] as String?,
      lineItems: (json['lineItems'] as List<dynamic>?)
              ?.map((e) => LineItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
      entryDate: DateTime.parse(
        json['entryDate'] as String? ??
            DateTime.now().toIso8601String().split('T')[0],
      ),
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'amount': amount.toString(),
        'currency': currency,
        'description': description,
        'originalDescription': originalDescription,
        'category': category,
        'isIncome': isIncome,
        'merchantName': merchantName,
        'last4': last4,
        'payerLabel': payerLabel,
        'payerProfileId': payerProfileId,
        'lineItems': lineItems.map((e) => e.toJson()).toList(),
        'entryDate':
            '${entryDate.year}-${entryDate.month.toString().padLeft(2, '0')}-${entryDate.day.toString().padLeft(2, '0')}',
        'confidence': confidence,
      };
}

// ── Top-level ingest response ───────────────────────────────────────────────

class ReceiptIngestResponse {
  /// Present on successful parse.
  final ReceiptDraft? draft;

  /// True if the model was escalated (confidence < 0.7 → gpt-4.1 retry).
  final bool escalated;

  /// One of 'amount', 'currency', 'date' — model/server needs user input.
  final String? needsClarification;

  /// Partial draft when clarification is needed.
  final ReceiptDraft? partial;

  const ReceiptIngestResponse({
    this.draft,
    this.escalated = false,
    this.needsClarification,
    this.partial,
  });

  factory ReceiptIngestResponse.fromJson(Map<String, dynamic> json) {
    // Clarification shape: { needsClarification, partial }
    if (json.containsKey('needsClarification') && !json.containsKey('draft')) {
      return ReceiptIngestResponse(
        needsClarification: json['needsClarification'] as String?,
        partial: json['partial'] != null
            ? ReceiptDraft.fromJson(json['partial'] as Map<String, dynamic>)
            : null,
      );
    }

    // Success shape: { draft, escalated }
    return ReceiptIngestResponse(
      draft: json['draft'] != null
          ? ReceiptDraft.fromJson(json['draft'] as Map<String, dynamic>)
          : null,
      escalated: json['escalated'] as bool? ?? false,
    );
  }

  /// Convenience: true when the server returned a valid draft (no clarification needed).
  bool get hasDraft => draft != null;

  /// Convenience: true when the server needs user clarification before proceeding.
  bool get hasClarification => needsClarification != null;
}

// setall-ingestion-pipeline: normalized row produced by ingest.js or CsvAdapter.
// Pending rows live only in Riverpod state — nothing writes to DB until approved.

import 'package:uuid/uuid.dart';

enum IngestRowStatus { pending, approved, rejected }

class IngestRow {
  IngestRow({
    String? id,
    required this.date,
    required this.amount,
    required this.currency,
    required this.rawDescription,
    required this.description,
    required this.category,
    required this.isIncome,
    this.status = IngestRowStatus.pending,
  }) : id = id ?? const Uuid().v4();

  final String id;
  final String date;         // ISO-8601 yyyy-MM-dd
  final String amount;       // decimal string, always positive
  final String currency;
  final String rawDescription;
  String description;
  String category;
  bool isIncome;
  IngestRowStatus status;

  IngestRow copyWith({
    String? description,
    String? category,
    bool? isIncome,
    IngestRowStatus? status,
    String? date,
    String? amount,
    String? currency,
  }) => IngestRow(
    id:             id,
    date:           date            ?? this.date,
    amount:         amount          ?? this.amount,
    currency:       currency        ?? this.currency,
    rawDescription: rawDescription,
    description:    description     ?? this.description,
    category:       category        ?? this.category,
    isIncome:       isIncome        ?? this.isIncome,
    status:         status          ?? this.status,
  );

  factory IngestRow.fromJson(Map<String, dynamic> j) => IngestRow(
    date:            j['date']            as String? ?? '',
    amount:          j['amount']?.toString()          ?? '0',
    currency:        (j['currency']        as String? ?? 'USD').toUpperCase(),
    rawDescription:  j['raw_description']  as String? ?? '',
    description:     j['description']      as String? ?? '',
    category:        j['category']         as String? ?? 'General',
    isIncome:        j['is_income']        == true,
  );
}

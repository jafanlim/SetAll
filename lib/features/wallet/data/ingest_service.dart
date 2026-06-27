// setall-ingestion-pipeline: service layer that calls ingest.js and converts
// approved IngestRows → WalletEntryModel via upsertWalletEntry.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import 'package:decimal/decimal.dart';

import '../../../core/config/auth_config.dart';
import '../../../core/services/csv_adapter.dart';
import '../../../core/utils/import_dedup.dart';
import '../../../data/models/wallet_entry_model.dart';
import '../../../data/repositories/setall_repository.dart';
import 'ingest_row.dart';

class IngestService {
  IngestService({required this.repository});

  final SetAllRepository repository;

  // ── Auth header helper ────────────────────────────────────────────────────
  Map<String, String> get _authHeaders {
    final token = Supabase.instance.client.auth.currentSession?.accessToken ?? '';
    return {
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  // ── CSV ingest ────────────────────────────────────────────────────────────
  // Parses locally via CsvAdapter, then sends normalized rows to ingest.js for
  // Groq classification. Returns classified IngestRows.
  Future<List<IngestRow>> ingestCsv(String csvText) async {
    final parsed = CsvAdapter.parse(csvText);
    if (parsed.rows.isEmpty) {
      throw IngestException(
        'No rows parsed from CSV. ${parsed.errors.isNotEmpty ? parsed.errors.first : ''}',
      );
    }

    // Map SplitwiseRow → wire format expected by ingest.js
    final csvRows = parsed.rows.map((r) => {
      'date':            _formatDate(r.date),
      'amount':          r.cost.toString(),
      'currency':        r.currency,
      'raw_description': r.description,
      'is_income':       r.isIncome,
    }).toList();

    final userCats = await repository.getUserCategories();

    final resp = await http.post(
      Uri.parse(AuthConfig.netlifyIngestUrl),
      headers: _authHeaders,
      body: jsonEncode({
        'format':         'csv',
        'csvRows':        csvRows,
        'userCategories': userCats,
      }),
    );

    return _parseResponse(resp);
  }

  // ── PDF ingest (web: Uint8List bytes from file picker) ────────────────────
  Future<List<IngestRow>> ingestPdf(Uint8List bytes) async {
    if (bytes.lengthInBytes > 5 * 1024 * 1024) {
      throw IngestException('PDF too large (max 5 MB)');
    }
    final base64Data = base64Encode(bytes);
    final userCats   = await repository.getUserCategories();

    final resp = await http.post(
      Uri.parse(AuthConfig.netlifyIngestUrl),
      headers: _authHeaders,
      body: jsonEncode({
        'format':         'pdf',
        'pdfBase64':      base64Data,
        'userCategories': userCats,
      }),
    );

    return _parseResponse(resp);
  }

  /// Builds a [Set] of [importDedupSig] signatures from every existing wallet
  /// entry and returns a copy of [rows] where any row whose signature collides
  /// is flagged `isDuplicate: true` and its status set to [IngestRowStatus.rejected].
  /// Callers should call this **after** ingestion but **before** the review UI so
  /// duplicate rows are pre-unchecked and badged.
  Future<List<IngestRow>> flagDuplicates(List<IngestRow> rows) async {
    if (rows.isEmpty) return rows;

    final existing = await repository.getWalletEntries();
    final seen = <String>{};
    for (final e in existing) {
      final createdAt = e.createdAt;
      if (createdAt == null) continue;
      final dt = DateTime.tryParse(createdAt);
      if (dt == null) continue;
      final amt = Decimal.tryParse(e.amount) ?? Decimal.zero;
      seen.add(importDedupSig(dt, e.description, amt, e.currency));
    }

    return rows.map((r) {
      final rowDate = DateTime.tryParse(r.date);
      if (rowDate == null) return r;
      final rowAmt = Decimal.tryParse(r.amount) ?? Decimal.zero;
      final sig = importDedupSig(rowDate, r.description, rowAmt, r.currency);
      if (seen.contains(sig)) {
        return r.copyWith(isDuplicate: true, status: IngestRowStatus.rejected);
      }
      return r;
    }).toList();
  }

  // ── Commit approved rows → upsertWalletEntry ─────────────────────────────
  /// Commits every approved row. `isDuplicate` is advisory only: flagDuplicates
  /// pre-rejects + badges suspected duplicates, but if the user deliberately
  /// re-approves one (e.g. a genuine second identical purchase the same day that
  /// the heuristic flagged as a dup of an existing entry), it must still commit.
  Future<int> commitApproved(List<IngestRow> rows) async {
    final approved = rows.where((r) => r.status == IngestRowStatus.approved).toList();
    int committed = 0;
    for (final row in approved) {
      try {
        final entry = WalletEntryModel(
          id:          const Uuid().v4(),
          userId:      '',
          amount:      row.amount,
          isIncome:    row.isIncome,
          description: row.description,
          category:    row.category,
          currency:    row.currency,
          createdAt:   '${row.date}T00:00:00.000Z',
        );
        await repository.upsertWalletEntry(entry);
        committed++;
      } catch (e) {
        debugPrint('[IngestService] commit failed for row ${row.id}: $e');
      }
    }
    return committed;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  List<IngestRow> _parseResponse(http.Response resp) {
    if (resp.statusCode == 401) throw IngestException('Authentication required — please log in again.');
    if (resp.statusCode == 429) throw IngestException('Too many requests. Wait a minute and try again.');
    if (resp.statusCode == 413) throw IngestException('File too large for processing.');
    if (resp.statusCode == 422) {
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      throw IngestException(body['error'] as String? ?? 'Could not extract transactions.');
    }
    if (resp.statusCode != 200) {
      final body = _safeDecodeBody(resp.body);
      throw IngestException('Server error ${resp.statusCode}: ${body['error'] ?? resp.body.substring(0, 200)}');
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    final rawRows = body['rows'] as List<dynamic>? ?? [];
    return rawRows.map((r) => IngestRow.fromJson(r as Map<String, dynamic>)).toList();
  }

  Map<String, dynamic> _safeDecodeBody(String body) {
    try { return jsonDecode(body) as Map<String, dynamic>; } catch (_) { return {}; }
  }

  String _formatDate(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
}

class IngestException implements Exception {
  IngestException(this.message);
  final String message;
  @override
  String toString() => message;
}

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart' show XFile;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/share_utils.dart';
import '../../../data/repositories/setall_repository.dart';
import '../../../features/analytics/presentation/screens/analytics_screen.dart';

const _brandTeal   = PdfColor.fromInt(0xFF14B8A6);
const _brandDark   = PdfColor.fromInt(0xFF0F172A);
const _brandSlate  = PdfColor.fromInt(0xFF64748B);
const _green       = PdfColor.fromInt(0xFF22C55E);
const _red         = PdfColor.fromInt(0xFFF43F5E);

String _fmtDate(String? raw) {
  if (raw == null) return '—';
  final d = DateTime.tryParse(raw);
  if (d == null) { return raw; }
  return DateFormat('d MMM yyyy').format(d.toLocal());
}

String _fmtAmount(String currency, String amount, {bool isIncome = false}) {
  final sign = isIncome ? '+' : '-';
  return '$sign$currency ${double.tryParse(amount)?.toStringAsFixed(2) ?? amount}';
}

// ── Isolate payload types ─────────────────────────────────────────────────

class _WalletPdfPayload {
  const _WalletPdfPayload({
    required this.entries,
    required this.email,
    required this.now,
  });
  final List<Map<String, dynamic>> entries;
  final String email;
  final String now;
}

class _GroupPdfPayload {
  const _GroupPdfPayload({
    required this.groupName,
    required this.now,
    required this.members,
    required this.expenses,
    required this.settlements,
  });
  final String groupName;
  final String now;
  final List<Map<String, dynamic>> members;
  final List<Map<String, dynamic>> expenses;
  final List<Map<String, dynamic>> settlements;
}

class _AnalyticsPdfPayload {
  const _AnalyticsPdfPayload({
    required this.income,
    required this.expenses,
    required this.currency,
    required this.now,
    required this.entries,
  });
  final double income;
  final double expenses;
  final String currency;
  final String now;
  final List<Map<String, dynamic>> entries;
}

// ── Top-level isolate workers (must be top-level for compute()) ────────────

Future<Uint8List> _buildWalletPdf(_WalletPdfPayload p) async {
  double totalIncome   = 0;
  double totalExpenses = 0;
  // Always sum the USD anchor so multi-currency entries produce correct totals.
  const currency = 'USD';
  for (final e in p.entries) {
    final usd = double.tryParse(
            (e['universal_usd_amount'] as String?) ??
            (e['amount']              as String?) ?? '0') ?? 0;
    if (e['is_income'] == true || e['is_income'] == 1) {
      totalIncome += usd;
    } else {
      totalExpenses += usd;
    }
  }
  final net = totalIncome - totalExpenses;

  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(0),
    build: (ctx) => [
      _header('Wallet Report', 'Generated ${p.now}  •  ${p.email}'),
      pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: pw.Container(
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _brandTeal, width: 0.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
          ),
          child: pw.Column(
            children: [
              _summaryRow('Total income',   '+$currency ${totalIncome.toStringAsFixed(2)}',  valueColor: _green),
              pw.SizedBox(height: 4),
              _summaryRow('Total expenses', '-$currency ${totalExpenses.toStringAsFixed(2)}', valueColor: _red),
              pw.Divider(color: _brandSlate),
              _summaryRow('Net balance',    '${net >= 0 ? '+' : ''}$currency ${net.toStringAsFixed(2)}',
                  valueColor: net >= 0 ? _green : _red),
            ],
          ),
        ),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(20, 8, 20, 4),
        child: pw.Text('Entries', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 20),
        child: pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
          headerDecoration: const pw.BoxDecoration(color: _brandDark),
          headerStyle: pw.TextStyle(color: PdfColors.white, fontSize: 9, fontWeight: pw.FontWeight.bold),
          cellStyle: const pw.TextStyle(fontSize: 9),
          cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          columnWidths: {
            0: const pw.FlexColumnWidth(2),
            1: const pw.FlexColumnWidth(3),
            2: const pw.FlexColumnWidth(2),
            3: const pw.FlexColumnWidth(2),
            4: const pw.FlexColumnWidth(1.2),
          },
          headers: ['Date', 'Description', 'Category', 'Amount', 'Type'],
          data: p.entries.map((e) {
            final isIncome = e['is_income'] == true || e['is_income'] == 1;
            final origCur  = e['original_currency'] as String?;
            final origAmt  = e['original_amount']   as String?;
            final cur      = (origCur != null && origCur.isNotEmpty)
                ? origCur
                : (e['currency'] as String? ?? 'USD');
            final amt      = (origAmt != null && origAmt.isNotEmpty)
                ? origAmt
                : (e['amount'] as String? ?? '0');
            final cat      = (e['category'] as String?)?.trim();
            return [
              _fmtDate(e['created_at'] as String?),
              (e['description'] as String?)?.isNotEmpty == true
                  ? e['description'] as String
                  : 'Wallet entry',
              (cat == null || cat.isEmpty) ? 'Other' : cat,
              _fmtAmount(cur, amt, isIncome: isIncome),
              isIncome ? 'Income' : 'Expense',
            ];
          }).toList(),
        ),
      ),
    ],
  ));
  return doc.save();
}

Future<Uint8List> _buildGroupPdf(_GroupPdfPayload p) async {
  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(0),
    build: (ctx) => [
      _header('${p.groupName} Report', 'Generated ${p.now}'),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 20),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text('Members', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Wrap(
              spacing: 8, runSpacing: 4,
              children: p.members.map<pw.Widget>((m) {
                final prof = m['profiles'] as Map? ?? {};
                final name = prof['display_name'] as String? ?? prof['email'] as String? ?? '—';
                return pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: _brandTeal, width: 0.5),
                    borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
                  ),
                  child: pw.Text(name, style: const pw.TextStyle(fontSize: 9)),
                );
              }).toList(),
            ),
            pw.SizedBox(height: 14),
            pw.Text('Expenses', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 6),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(2),
                1: const pw.FlexColumnWidth(3),
                2: const pw.FlexColumnWidth(2),
                3: const pw.FlexColumnWidth(2),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: _brandDark),
                  children: ['Date', 'Description', 'Amount', 'Paid by']
                      .map((h) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                            child: pw.Text(h, style: pw.TextStyle(
                              color: PdfColors.white, fontSize: 9,
                              fontWeight: pw.FontWeight.bold)),
                          ))
                      .toList(),
                ),
                ...p.expenses.map((e) {
                  final payer = (e['profiles'] as Map?)?['display_name'] as String? ?? '—';
                  return pw.TableRow(children: [
                    _cell(_fmtDate(e['created_at'] as String?)),
                    _cell(e['description'] as String? ?? ''),
                    _cell('${e['currency'] ?? ''} ${e['amount'] ?? ''}'),
                    _cell(payer),
                  ]);
                }),
              ],
            ),
            pw.SizedBox(height: 14),
            if (p.settlements.isNotEmpty) ..._buildSettlementsSection(p.settlements),
          ],
        ),
      ),
    ],
  ));
  return doc.save();
}

List<pw.Widget> _buildSettlementsSection(List<Map<String, dynamic>> settlements) => [
  pw.Text('Settlements', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
  pw.SizedBox(height: 6),
  pw.Table(
    border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
    columnWidths: {
      0: const pw.FlexColumnWidth(2.5),
      1: const pw.FlexColumnWidth(2.5),
      2: const pw.FlexColumnWidth(2),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: _brandDark),
        children: ['From', 'To', 'Amount']
            .map((h) => pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  child: pw.Text(h, style: pw.TextStyle(
                    color: PdfColors.white, fontSize: 9,
                    fontWeight: pw.FontWeight.bold)),
                ))
            .toList(),
      ),
      ...settlements.map((s) => pw.TableRow(children: [
        _cell((s['from'] as Map?)?['display_name'] as String? ?? '—'),
        _cell((s['to']   as Map?)?['display_name'] as String? ?? '—'),
        _cell('${s['currency'] ?? ''} ${s['amount'] ?? ''}'),
      ])),
    ],
  ),
];

Future<Uint8List> _buildAnalyticsPdf(_AnalyticsPdfPayload p) async {
  final net = p.income - p.expenses;
  final catMap = <String, double>{};
  for (final e in p.entries) {
    if (e['is_income'] == true || e['is_income'] == 1) continue;
    final amt = double.tryParse(e['amount'] as String? ?? '0') ?? 0;
    final cat = ((e['category'] as String?)?.trim().isNotEmpty ?? false)
        ? e['category'] as String
        : 'Other';
    catMap[cat] = (catMap[cat] ?? 0) + amt;
  }
  final catSorted = catMap.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  final totalExp  = catSorted.fold<double>(0, (s, e) => s + e.value);

  final doc = pw.Document();
  doc.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.all(0),
    build: (ctx) => [
      _header('Analytics Report', 'Generated ${p.now}'),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 20),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: _brandTeal, width: 0.5),
                borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
              ),
              child: pw.Column(children: [
                _summaryRow('Total income',   '+${p.currency} ${p.income.toStringAsFixed(2)}',   valueColor: _green),
                pw.SizedBox(height: 4),
                _summaryRow('Total expenses', '-${p.currency} ${p.expenses.toStringAsFixed(2)}', valueColor: _red),
                pw.Divider(color: _brandSlate),
                _summaryRow('Net', '${net >= 0 ? '+' : ''}${p.currency} ${net.toStringAsFixed(2)}',
                    valueColor: net >= 0 ? _green : _red),
              ]),
            ),
            pw.SizedBox(height: 16),
            pw.Text('Category Breakdown', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(2),
                2: const pw.FlexColumnWidth(1.5),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: _brandDark),
                  children: ['Category', 'Amount', '% of total']
                      .map((h) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                            child: pw.Text(h, style: pw.TextStyle(
                              color: PdfColors.white, fontSize: 9,
                              fontWeight: pw.FontWeight.bold)),
                          ))
                      .toList(),
                ),
                ...catSorted.map((e) => pw.TableRow(children: [
                  _cell(e.key),
                  _cell('${p.currency} ${e.value.toStringAsFixed(2)}'),
                  _cell(totalExp > 0
                      ? '${(e.value / totalExp * 100).toStringAsFixed(1)}%'
                      : '0%'),
                ])),
              ],
            ),
          ],
        ),
      ),
    ],
  ));
  return doc.save();
}

pw.Widget _header(String title, String subtitle) => pw.Column(
  crossAxisAlignment: pw.CrossAxisAlignment.start,
  children: [
    pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: const pw.BoxDecoration(color: _brandDark),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('SetAll', style: pw.TextStyle(
            color: PdfColors.white, fontSize: 10,
            fontWeight: pw.FontWeight.bold, letterSpacing: 2)),
          pw.SizedBox(height: 4),
          pw.Text(title, style: pw.TextStyle(
            color: _brandTeal, fontSize: 18, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 2),
          pw.Text(subtitle, style: pw.TextStyle(
            color: _brandSlate, fontSize: 9)),
        ],
      ),
    ),
    pw.SizedBox(height: 16),
  ],
);

pw.Widget _summaryRow(String label, String value, {PdfColor? valueColor}) =>
  pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(label, style: pw.TextStyle(fontSize: 10, color: _brandSlate)),
      pw.Text(value, style: pw.TextStyle(
        fontSize: 11, fontWeight: pw.FontWeight.bold,
        color: valueColor ?? _brandDark)),
    ],
  );

class PdfExportService {
  // ── Wallet PDF ─────────────────────────────────────────────────────────────
  Future<void> exportWalletAsPdf({
    BuildContext? context,
    GlobalKey? originKey,
    SetAllRepository? repository,
  }) async {
    final email   = Supabase.instance.client.auth.currentUser?.email ?? '';
    final repo    = repository ?? SetAllRepository();
    final entries = await repo.getPersonalExpenses();
    final now     = DateFormat('d MMM yyyy, HH:mm').format(DateTime.now());

    final pdfBytes = await compute(
      _buildWalletPdf,
      _WalletPdfPayload(
        entries: entries.map((e) => e.toJson()).toList(),
        email:   email,
        now:     now,
      ),
    );

    if (context == null) return;
    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/setall_wallet_report.pdf');
    await file.writeAsBytes(pdfBytes, flush: true);
    // ignore: use_build_context_synchronously
    await shareFiles([XFile(file.path)], context: context,
        subject: 'setall_wallet_report.pdf', originKey: originKey);
  }

  // ── Group PDF ──────────────────────────────────────────────────────────────
  Future<void> exportGroupAsPdf(
    String groupId,
    String groupName, {
    BuildContext? context,
    GlobalKey? originKey,
  }) async {
    final client = Supabase.instance.client;
    final now    = DateFormat('d MMM yyyy, HH:mm').format(DateTime.now());

    final List membersRaw     = await client
        .from('group_members')
        .select('user_id, profiles(display_name, email)')
        .eq('group_id', groupId);
    final List expensesRaw    = await client
        .from('expenses')
        .select('*, profiles!payer_id(display_name)')
        .eq('group_id', groupId)
        .order('created_at', ascending: false);
    final List settlementsRaw = await client
        .from('settlements')
        .select('*, from:profiles!from_user_id(display_name), to:profiles!to_user_id(display_name)')
        .eq('group_id', groupId);

    final pdfBytes = await compute(
      _buildGroupPdf,
      _GroupPdfPayload(
        groupName:   groupName,
        now:         now,
        members:     membersRaw.cast<Map<String, dynamic>>(),
        expenses:    expensesRaw.cast<Map<String, dynamic>>(),
        settlements: settlementsRaw.cast<Map<String, dynamic>>(),
      ),
    );

    if (context == null) return;
    final dir  = await getTemporaryDirectory();
    final filename = 'setall_${groupName.replaceAll(' ', '_')}_report.pdf';
    final file = File('${dir.path}/$filename');
    await file.writeAsBytes(pdfBytes, flush: true);
    // ignore: use_build_context_synchronously
    await shareFiles([XFile(file.path)], context: context,
        subject: filename, originKey: originKey);
  }

  // ── Analytics PDF ──────────────────────────────────────────────────────────
  Future<void> exportAnalyticsPdf({
    BuildContext? context,
    GlobalKey? originKey,
    required double income,
    required double expenses,
    required List<AnalyticsRow> entries,
    String currency = 'USD',
  }) async {
    final now = DateFormat('d MMM yyyy, HH:mm').format(DateTime.now());

    final pdfBytes = await compute(
      _buildAnalyticsPdf,
      _AnalyticsPdfPayload(
        income:   income,
        expenses: expenses,
        currency: currency,
        now:      now,
        entries:  entries.map((e) => {
          'is_income': e.isIncome,
          'amount':    e.amount,
          'category':  e.category,
        }).toList(),
      ),
    );

    if (context == null) return;
    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/setall_analytics_report.pdf');
    await file.writeAsBytes(pdfBytes, flush: true);
    // ignore: use_build_context_synchronously
    await shareFiles([XFile(file.path)], context: context,
        subject: 'setall_analytics_report.pdf', originKey: originKey);
  }
}

// ── Cell helper (top-level so isolates can use it) ────────────────────────
pw.Widget _cell(String text, {PdfColor? color}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
  child: pw.Text(text,
      style: pw.TextStyle(fontSize: 9, color: color ?? _brandDark),
      overflow: pw.TextOverflow.clip),
);

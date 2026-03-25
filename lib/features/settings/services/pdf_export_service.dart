import 'dart:io';

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

Future<void> _shareFile(
  pw.Document pdf,
  String filename,
  BuildContext context, {
  GlobalKey? originKey,
}) async {
  final bytes = await pdf.save();
  final dir   = await getTemporaryDirectory();
  final file  = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);
  // ignore: use_build_context_synchronously
  await shareFiles([XFile(file.path)], context: context,
      subject: filename, originKey: originKey);
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
    final client = Supabase.instance.client;
    final email  = client.auth.currentUser?.email ?? '';

    final repo    = repository ?? SetAllRepository();
    final entries = await repo.getPersonalExpenses();

    double totalIncome   = 0;
    double totalExpenses = 0;
    for (final e in entries) {
      final amt = double.tryParse(e.amount) ?? 0;
      if (e.isIncome) { totalIncome += amt; } else { totalExpenses += amt; }
    }
    final net = totalIncome - totalExpenses;

    final pdf = pw.Document();
    final now = DateFormat('d MMM yyyy, HH:mm').format(DateTime.now());
    final currency = entries.isNotEmpty ? entries.first.currency : 'USD';

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(0),
      build: (ctx) => [
        _header('Wallet Report', 'Generated $now  •  $email'),
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
              pw.SizedBox(height: 16),
              pw.Text('Entries', style: pw.TextStyle(
                fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 8),
              pw.Table(
                border: pw.TableBorder.all(color: PdfColor.fromInt(0xFFE2E8F0), width: 0.5),
                columnWidths: {
                  0: const pw.FlexColumnWidth(2),
                  1: const pw.FlexColumnWidth(3),
                  2: const pw.FlexColumnWidth(2),
                  3: const pw.FlexColumnWidth(2),
                  4: const pw.FlexColumnWidth(1.2),
                },
                children: [
                  pw.TableRow(
                    decoration: const pw.BoxDecoration(color: _brandDark),
                    children: ['Date', 'Description', 'Category', 'Amount', 'Type']
                        .map((h) => pw.Padding(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                              child: pw.Text(h, style: pw.TextStyle(
                                color: PdfColors.white, fontSize: 9,
                                fontWeight: pw.FontWeight.bold)),
                            ))
                        .toList(),
                  ),
                  ...entries.map((e) => pw.TableRow(children: [
                    _cell(_fmtDate(e.createdAt)),
                    _cell(e.description),
                    _cell(e.category.isEmpty ? 'Other' : e.category),
                    _cell(_fmtAmount(e.currency, e.amount, isIncome: e.isIncome),
                        color: e.isIncome ? _green : _red),
                    _cell(e.isIncome ? 'Income' : 'Expense',
                        color: e.isIncome ? _green : _red),
                  ])),
                ],
              ),
            ],
          ),
        ),
      ],
    ));

    if (context == null) return;
    // ignore: use_build_context_synchronously
    await _shareFile(pdf, 'setall_wallet_report.pdf', context,
        originKey: originKey);
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

    final List membersRaw = await client
        .from('group_members')
        .select('user_id, profiles(display_name, email)')
        .eq('group_id', groupId);
    final List expensesRaw = await client
        .from('expenses')
        .select('*, profiles!payer_id(display_name)')
        .eq('group_id', groupId)
        .order('created_at', ascending: false);
    final List settlementsRaw = await client
        .from('settlements')
        .select('*, from:profiles!from_user_id(display_name), to:profiles!to_user_id(display_name)')
        .eq('group_id', groupId);

    final pdf = pw.Document();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(0),
      build: (ctx) => [
        _header('$groupName Report', 'Generated $now'),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 20),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Members
              pw.Text('Members', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              pw.Wrap(
                spacing: 8, runSpacing: 4,
                children: membersRaw.map<pw.Widget>((m) {
                  final p = m['profiles'] as Map? ?? {};
                  final name = p['display_name'] as String? ?? p['email'] as String? ?? '—';
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

              // Expenses
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
                  ...expensesRaw.map((e) {
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

              // Settlements
              if (settlementsRaw.isNotEmpty) ...[
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
                    ...settlementsRaw.map((s) => pw.TableRow(children: [
                      _cell((s['from'] as Map?)?['display_name'] as String? ?? '—'),
                      _cell((s['to']   as Map?)?['display_name'] as String? ?? '—'),
                      _cell('${s['currency'] ?? ''} ${s['amount'] ?? ''}'),
                    ])),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    ));

    if (context == null) return;
    // ignore: use_build_context_synchronously
    await _shareFile(pdf, 'setall_${groupName.replaceAll(' ', '_')}_report.pdf', context,
        originKey: originKey);
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
    final net = income - expenses;

    // Category breakdown
    final catMap = <String, double>{};
    for (final e in entries) {
      if (e.isIncome) continue;
      final amt = double.tryParse(e.amount) ?? 0;
      final cat = e.category.isEmpty ? 'Other' : e.category;
      catMap[cat] = (catMap[cat] ?? 0) + amt;
    }
    final catSorted = catMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final totalExp = catSorted.fold<double>(0, (s, e) => s + e.value);

    final pdf = pw.Document();

    pdf.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(0),
      build: (ctx) => [
        _header('Analytics Report', 'Generated $now'),
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 20),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Summary
              pw.Container(
                padding: const pw.EdgeInsets.all(12),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(color: _brandTeal, width: 0.5),
                  borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
                ),
                child: pw.Column(children: [
                  _summaryRow('Total income',   '+$currency ${income.toStringAsFixed(2)}',   valueColor: _green),
                  pw.SizedBox(height: 4),
                  _summaryRow('Total expenses', '-$currency ${expenses.toStringAsFixed(2)}',  valueColor: _red),
                  pw.Divider(color: _brandSlate),
                  _summaryRow('Net',            '${net >= 0 ? '+' : ''}$currency ${net.toStringAsFixed(2)}',
                      valueColor: net >= 0 ? _green : _red),
                ]),
              ),
              pw.SizedBox(height: 16),

              // Category breakdown
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
                    _cell('$currency ${e.value.toStringAsFixed(2)}'),
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

    if (context == null) return;
    // ignore: use_build_context_synchronously
    await _shareFile(pdf, 'setall_analytics_report.pdf', context,
        originKey: originKey);
  }
}

pw.Widget _cell(String text, {PdfColor? color}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
  child: pw.Text(text,
      style: pw.TextStyle(fontSize: 9, color: color ?? _brandDark),
      overflow: pw.TextOverflow.clip),
);

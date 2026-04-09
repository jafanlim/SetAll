import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

const _teal = Color(0xFF14B8A6);

// ---------------------------------------------------------------------------
// Ring-buffer breadcrumb service — call BugReportService.addBreadcrumb()
// at key user actions to populate "recent logs" in the bug report.
// ---------------------------------------------------------------------------
class BugReportService {
  BugReportService._();

  static final List<String> _breadcrumbs = [];
  static const int _maxCrumbs = 20;

  static void addBreadcrumb(String message) {
    _breadcrumbs.add('[${DateTime.now().toIso8601String()}] $message');
    if (_breadcrumbs.length > _maxCrumbs) _breadcrumbs.removeAt(0);
  }

  static List<String> get breadcrumbs => List.unmodifiable(_breadcrumbs);
}

// ---------------------------------------------------------------------------
// Bug report bottom sheet
// ---------------------------------------------------------------------------
class BugReportScreen extends StatefulWidget {
  const BugReportScreen({super.key});

  @override
  State<BugReportScreen> createState() => _BugReportScreenState();
}

class _BugReportScreenState extends State<BugReportScreen> {
  final _descCtrl     = TextEditingController();
  final _expectedCtrl = TextEditingController();

  String _severity       = 'medium';
  bool   _includeDevice  = true;
  bool   _includeLogs    = true;
  bool   _submitting     = false;

  static const _severities = ['low', 'medium', 'high', 'crash'];

  @override
  void dispose() {
    _descCtrl.dispose();
    _expectedCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('bug_report.describe_first'.tr())),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      String deviceInfo = '';
      String appVersion = '';

      if (_includeDevice && !kIsWeb) {
        deviceInfo = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
      }

      try {
        final info = await PackageInfo.fromPlatform();
        appVersion = '${info.version}+${info.buildNumber}';
      } catch (_) {}

      final logs = _includeLogs
          ? BugReportService.breadcrumbs.join('\n')
          : '';

      // 1. PRIMARY: open mail app with pre-filled bug report
      final expected = _expectedCtrl.text.trim();
      final bodyLines = [
        'Version: $appVersion',
        if (_includeDevice && deviceInfo.isNotEmpty) 'Device: $deviceInfo',
        '',
        'Severity: $_severity',
        '',
        'What happened:',
        desc,
        if (expected.isNotEmpty) ...['' ,'Expected:', expected],
        if (_includeLogs && logs.isNotEmpty) ...['' , 'Recent logs:', logs],
      ];
      final subject = Uri.encodeComponent('Bug Report — SetAll $appVersion');
      final body    = Uri.encodeComponent(bodyLines.join('\n'));
      final mailUri = Uri.parse('mailto:contact@setall.app?subject=$subject&body=$body');
      if (await canLaunchUrl(mailUri)) {
        await launchUrl(mailUri);
      }

      // 2. SECONDARY: Crashlytics non-fatal
      if (!kIsWeb) {
        await FirebaseCrashlytics.instance.recordError(
          Exception('Bug report: $desc'),
          StackTrace.current,
          reason: 'user_bug_report',
          information: [
            DiagnosticsNode.message('severity: $_severity'),
            DiagnosticsNode.message('expected: $expected'),
            DiagnosticsNode.message('device: $deviceInfo'),
            DiagnosticsNode.message('version: $appVersion'),
          ],
          fatal: false,
        );
      }

      // 3. SECONDARY: Supabase bug_reports table (best-effort backup)
      try {
        final client = Supabase.instance.client;
        final uid    = client.auth.currentUser?.id;
        await client.from('bug_reports').insert({
          'user_id':     uid,
          'description': desc,
          'expected':    expected.isEmpty ? null : expected,
          'severity':    _severity,
          'device_info': _includeDevice ? deviceInfo : null,
          'logs':        _includeLogs   ? logs        : null,
          'app_version': appVersion,
          'created_at':  DateTime.now().toUtc().toIso8601String(),
        });
      } catch (_) {}

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('bug_report.sent_thanks'.tr()),
            backgroundColor: _teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${'bug_report.failed_prefix'.tr()}$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Title
          Text('bug_report.title'.tr(),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),

          // Description
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: 'bug_report.what_happened_label'.tr(),
              hintText: 'bug_report.what_happened_hint'.tr(),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _teal),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Expected
          TextField(
            controller: _expectedCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'bug_report.expected_label'.tr(),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _teal),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Severity
          Row(
            children: [
              Text('bug_report.severity_label'.tr(), style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              )),
              const SizedBox(width: 16),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _severity,
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: _severities.map((s) => DropdownMenuItem(
                    value: s,
                    child: Text('bug_report.severity_$s'.tr()),
                  )).toList(),
                  onChanged: (v) { if (v != null) setState(() => _severity = v); },
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Checkboxes
          CheckboxListTile(
            value: _includeDevice,
            onChanged: (v) => setState(() => _includeDevice = v ?? true),
            title: Text('bug_report.include_device'.tr(), style: const TextStyle(fontSize: 13)),
            activeColor: _teal,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: _includeLogs,
            onChanged: (v) => setState(() => _includeLogs = v ?? true),
            title: Text('bug_report.include_logs'.tr(), style: const TextStyle(fontSize: 13)),
            activeColor: _teal,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          const SizedBox(height: 12),

          // Submit
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _submitting ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: _submitting
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : Text('bug_report.submit_btn'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

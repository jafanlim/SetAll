import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
        const SnackBar(content: Text('Please describe what happened.')),
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

      // 1. Crashlytics non-fatal
      if (!kIsWeb) {
        await FirebaseCrashlytics.instance.recordError(
          Exception('Bug report: $desc'),
          null,
          reason: desc,
          information: [
            DiagnosticsNode.message('severity: $_severity'),
            DiagnosticsNode.message('expected: ${_expectedCtrl.text.trim()}'),
            DiagnosticsNode.message('device: $deviceInfo'),
            DiagnosticsNode.message('version: $appVersion'),
          ],
          fatal: false,
        );
      }

      // 2. Supabase bug_reports table
      final client = Supabase.instance.client;
      final uid    = client.auth.currentUser?.id;
      await client.from('bug_reports').insert({
        'user_id':     uid,
        'description': desc,
        'expected':    _expectedCtrl.text.trim().isEmpty ? null : _expectedCtrl.text.trim(),
        'severity':    _severity,
        'device_info': _includeDevice ? deviceInfo : null,
        'logs':        _includeLogs   ? logs        : null,
        'app_version': appVersion,
        'created_at':  DateTime.now().toUtc().toIso8601String(),
      });

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bug report sent. Thank you!'),
            backgroundColor: _teal,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e'), backgroundColor: Colors.red),
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
          const Text('Report a Bug',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),

          // Description
          TextField(
            controller: _descCtrl,
            maxLines: 3,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: 'What were you doing?',
              hintText: 'Describe the issue…',
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
              labelText: 'What did you expect? (optional)',
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
              Text('Severity', style: TextStyle(
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
                    child: Text(s[0].toUpperCase() + s.substring(1)),
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
            title: const Text('Include device info', style: TextStyle(fontSize: 13)),
            activeColor: _teal,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
          CheckboxListTile(
            value: _includeLogs,
            onChanged: (v) => setState(() => _includeLogs = v ?? true),
            title: const Text('Include recent logs', style: TextStyle(fontSize: 13)),
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
                  : const Text('Submit', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

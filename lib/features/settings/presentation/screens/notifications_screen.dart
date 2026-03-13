import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';

const _teal  = Color(0xFF00D9B0);
const _slate = Color(0xFF94A3B8);

// ---------------------------------------------------------------------------
// Prefs keys
// ---------------------------------------------------------------------------
const _kPushExpense    = 'notif_push_expense';
const _kPushSettlement = 'notif_push_settlement';
const _kPushGroupEvent = 'notif_push_group_event';
const _kEmailDigest    = 'notif_email_digest';
const _kEmailSettlement = 'notif_email_settlement';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // Push (default ON)
  bool _pushExpense    = true;
  bool _pushSettlement = true;
  bool _pushGroupEvent = true;

  // Email (default OFF)
  bool _emailDigest     = false;
  bool _emailSettlement = false;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (mounted) {
      setState(() {
        _pushExpense    = p.getBool(_kPushExpense)    ?? true;
        _pushSettlement = p.getBool(_kPushSettlement) ?? true;
        _pushGroupEvent = p.getBool(_kPushGroupEvent) ?? true;
        _emailDigest    = p.getBool(_kEmailDigest)    ?? false;
        _emailSettlement = p.getBool(_kEmailSettlement) ?? false;
        _loading        = false;
      });
    }
  }

  Future<void> _set(String key, bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(key, value);
    HapticUtils.selection();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Notifications', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // ── Push ────────────────────────────────────────────────
                _SectionLabel('Push Notifications'),
                Text(
                  'Receive alerts directly on your device.',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      _Toggle(
                        icon: Icons.receipt_long_outlined,
                        iconColor: _teal,
                        title: 'New expenses & income',
                        subtitle: 'Alert when a new expense or income is added.',
                        value: _pushExpense,
                        onChanged: (v) {
                          setState(() => _pushExpense = v);
                          _set(_kPushExpense, v);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 0),
                      _Toggle(
                        icon: Icons.check_circle_outline,
                        iconColor: _teal,
                        title: 'Settlements',
                        subtitle: 'Alert when a balance is settled.',
                        value: _pushSettlement,
                        onChanged: (v) {
                          setState(() => _pushSettlement = v);
                          _set(_kPushSettlement, v);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 0),
                      _Toggle(
                        icon: Icons.group_outlined,
                        iconColor: _teal,
                        title: 'Group events',
                        subtitle: 'Alert for group creation, member additions.',
                        value: _pushGroupEvent,
                        onChanged: (v) {
                          setState(() => _pushGroupEvent = v);
                          _set(_kPushGroupEvent, v);
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Email ───────────────────────────────────────────────
                _SectionLabel('Email Notifications'),
                Text(
                  'Email updates are off by default.',
                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 8),
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      _Toggle(
                        icon: Icons.email_outlined,
                        iconColor: _slate,
                        title: 'Weekly digest',
                        subtitle: 'Summary of your activity sent every Monday.',
                        value: _emailDigest,
                        onChanged: (v) {
                          setState(() => _emailDigest = v);
                          _set(_kEmailDigest, v);
                        },
                      ),
                      const Divider(height: 1, indent: 16, endIndent: 0),
                      _Toggle(
                        icon: Icons.attach_money_rounded,
                        iconColor: _slate,
                        title: 'Settlement reminders',
                        subtitle: 'Email when you have pending balances.',
                        value: _emailSettlement,
                        onChanged: (v) {
                          setState(() => _emailSettlement = v);
                          _set(_kEmailSettlement, v);
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reusable toggle row
// ---------------------------------------------------------------------------
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      secondary: Icon(icon, color: iconColor, size: 20),
      title: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
      ),
      value: value,
      activeColor: _teal,
      onChanged: onChanged,
    );
  }
}

// ---------------------------------------------------------------------------
// Section label
// ---------------------------------------------------------------------------
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
}

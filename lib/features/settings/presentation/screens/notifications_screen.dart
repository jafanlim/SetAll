import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';

const _teal  = Color(0xFF00D9B0);
const _slate = Color(0xFF94A3B8);
const _amber = Color(0xFFF59E0B);

// ---------------------------------------------------------------------------
// Prefs keys — push mirrors every notification type; email does the same.
// ---------------------------------------------------------------------------
const _kPushExpense      = 'notif_push_expense';
const _kPushSettlement   = 'notif_push_settlement';
const _kPushGroupEvent   = 'notif_push_group_event';
const _kPushDigest          = 'notif_push_digest';
const _kPushGroupActivity   = 'notif_push_group_activity';

const _kEmailExpense     = 'notif_email_expense';
const _kEmailSettlement  = 'notif_email_settlement';
const _kEmailGroupEvent  = 'notif_email_group_event';
const _kEmailDigest      = 'notif_email_digest';

// ---------------------------------------------------------------------------
// NotificationsScreen
// ---------------------------------------------------------------------------
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // Push defaults: ON
  bool _pushExpense    = true;
  bool _pushSettlement = true;
  bool _pushGroupEvent = true;
  bool _pushDigest        = false;
  bool _pushGroupActivity  = true;

  // Email defaults: OFF
  bool _emailExpense    = false;
  bool _emailSettlement = false;
  bool _emailGroupEvent = false;
  bool _emailDigest     = false;

  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _pushExpense    = p.getBool(_kPushExpense)    ?? true;
      _pushSettlement = p.getBool(_kPushSettlement) ?? true;
      _pushGroupEvent = p.getBool(_kPushGroupEvent) ?? true;
      _pushDigest        = p.getBool(_kPushDigest)        ?? false;
      _pushGroupActivity = p.getBool(_kPushGroupActivity) ?? true;
      _emailExpense    = p.getBool(_kEmailExpense)    ?? false;
      _emailSettlement = p.getBool(_kEmailSettlement) ?? false;
      _emailGroupEvent = p.getBool(_kEmailGroupEvent) ?? false;
      _emailDigest     = p.getBool(_kEmailDigest)     ?? false;
      _loading = false;
    });
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
        title: const Text('Notifications',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // ── FCM/APNs wiring note ─────────────────────────────────
                _InfoBanner(
                  icon: LucideIcons.info,
                  text: 'Push delivery requires Firebase Cloud Messaging (FCM) or APNs '
                      'to be configured in the server. Preferences below are saved and '
                      'will take effect once the push service is wired up.',
                ),
                const SizedBox(height: 20),

                // ── Column headers ───────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      const Expanded(flex: 5, child: SizedBox()),
                      Expanded(
                        flex: 2,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.smartphone, size: 12, color: _teal),
                              const SizedBox(width: 4),
                              Text('Push',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(LucideIcons.mail, size: 12, color: _slate),
                              const SizedBox(width: 4),
                              Text('Email',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),

                // ── Notification rows ────────────────────────────────────
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      _NotifRow(
                        icon: LucideIcons.receipt,
                        iconColor: _teal,
                        title: 'New expenses',
                        subtitle: 'When an expense or income is added',
                        pushValue: _pushExpense,
                        emailValue: _emailExpense,
                        onPushChanged: (v) { setState(() => _pushExpense = v);    _set(_kPushExpense, v); },
                        onEmailChanged: (v) { setState(() => _emailExpense = v);  _set(_kEmailExpense, v); },
                      ),
                      const Divider(height: 1, indent: 52, endIndent: 0),
                      _NotifRow(
                        icon: LucideIcons.handCoins,
                        iconColor: _teal,
                        title: 'Settlements',
                        subtitle: 'When a balance is settled',
                        pushValue: _pushSettlement,
                        emailValue: _emailSettlement,
                        onPushChanged: (v) { setState(() => _pushSettlement = v);  _set(_kPushSettlement, v); },
                        onEmailChanged: (v) { setState(() => _emailSettlement = v); _set(_kEmailSettlement, v); },
                      ),
                      const Divider(height: 1, indent: 52, endIndent: 0),
                      _NotifRow(
                        icon: LucideIcons.users,
                        iconColor: _teal,
                        title: 'Group events',
                        subtitle: 'New members, group creation',
                        pushValue: _pushGroupEvent,
                        emailValue: _emailGroupEvent,
                        onPushChanged: (v) { setState(() => _pushGroupEvent = v);  _set(_kPushGroupEvent, v); },
                        onEmailChanged: (v) { setState(() => _emailGroupEvent = v); _set(_kEmailGroupEvent, v); },
                      ),
                      const Divider(height: 1, indent: 52, endIndent: 0),
                      _NotifRow(
                        icon: LucideIcons.bell,
                        iconColor: _teal,
                        title: 'Group activity',
                        subtitle: 'When members add or change expenses',
                        pushValue: _pushGroupActivity,
                        emailValue: false,
                        onPushChanged: (v) { setState(() => _pushGroupActivity = v); _set(_kPushGroupActivity, v); },
                        onEmailChanged: (_) {},
                      ),
                      const Divider(height: 1, indent: 52, endIndent: 0),
                      _NotifRow(
                        icon: LucideIcons.calendarDays,
                        iconColor: _amber,
                        title: 'Weekly digest',
                        subtitle: 'Activity summary every Monday',
                        pushValue: _pushDigest,
                        emailValue: _emailDigest,
                        onPushChanged: (v) { setState(() => _pushDigest = v);  _set(_kPushDigest, v); },
                        onEmailChanged: (v) { setState(() => _emailDigest = v); _set(_kEmailDigest, v); },
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
// Single notification row: title + push toggle + email toggle
// ---------------------------------------------------------------------------
class _NotifRow extends StatelessWidget {
  const _NotifRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.pushValue,
    required this.emailValue,
    required this.onPushChanged,
    required this.onEmailChanged,
  });

  final IconData icon;
  final Color    iconColor;
  final String   title;
  final String   subtitle;
  final bool     pushValue;
  final bool     emailValue;
  final ValueChanged<bool> onPushChanged;
  final ValueChanged<bool> onEmailChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          // Icon
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 12),
          // Text
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                Text(subtitle,
                    style: TextStyle(
                        fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          // Push toggle
          Expanded(
            flex: 2,
            child: Center(
              child: Switch(
                value: pushValue,
                activeThumbColor: _teal,
                onChanged: onPushChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          // Email toggle
          Expanded(
            flex: 2,
            child: Center(
              child: Switch(
                value: emailValue,
                activeThumbColor: _slate,
                onChanged: onEmailChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info banner
// ---------------------------------------------------------------------------
class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.icon, required this.text});
  final IconData icon;
  final String   text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _teal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _teal.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: _teal),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                  fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}


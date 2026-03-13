import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/services/biometric_service.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';

// ---------------------------------------------------------------------------
// Keys
// ---------------------------------------------------------------------------
const String _kGracePeriodKey = 'setall_biometric_grace_seconds';
const String _kPinKey         = 'setall_user_pin';

const _teal   = Color(0xFF00D9B0);
const _tealDim = Color(0x2600D9B0);
const _slate  = Color(0xFF94A3B8);

const List<({int seconds, String label})> kGracePeriodOptions = [
  (seconds: 0,   label: 'Immediately'),
  (seconds: 30,  label: '30 seconds'),
  (seconds: 60,  label: '1 minute'),
  (seconds: 300, label: '5 minutes'),
];

// ---------------------------------------------------------------------------
// SecurityScreen
// ---------------------------------------------------------------------------
class SecurityScreen extends ConsumerStatefulWidget {
  const SecurityScreen({super.key});

  @override
  ConsumerState<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends ConsumerState<SecurityScreen> {
  bool _biometricAvailable = false;
  bool _biometricEnabled   = false;
  int  _gracePeriodSeconds = 30;
  bool _loading            = true;
  bool _pinSet             = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bio     = BiometricService.instance;
    final avail   = await bio.canUseBiometrics();
    final enabled = await bio.getUseBiometric();
    final prefs   = await SharedPreferences.getInstance();
    final grace   = prefs.getInt(_kGracePeriodKey) ?? 30;
    final pin     = prefs.getString(_kPinKey);
    if (mounted) {
      setState(() {
        _biometricAvailable  = avail;
        _biometricEnabled    = enabled;
        _gracePeriodSeconds  = grace;
        _pinSet              = pin != null && pin.isNotEmpty;
        _loading             = false;
      });
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    final bio = BiometricService.instance;
    if (value) {
      final ok = await bio.authenticate(reason: 'Confirm to enable biometric lock');
      if (!ok) return;
    }
    await bio.setUseBiometric(value);
    if (mounted) setState(() => _biometricEnabled = value);
    HapticUtils.success();
  }

  Future<void> _setGracePeriod(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kGracePeriodKey, seconds);
    if (mounted) setState(() => _gracePeriodSeconds = seconds);
    HapticUtils.selection();
  }

  Future<void> _showSetPinDialog() async {
    final pinCtrl1 = TextEditingController();
    final pinCtrl2 = TextEditingController();
    String? error;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(_pinSet ? 'Change PIN' : 'Set PIN'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Your PIN is the secondary fallback when biometrics fail.',
                style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl1,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'PIN (4–8 digits)',
                  prefixIcon: Icon(Icons.pin_outlined),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl2,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Confirm PIN',
                  prefixIcon: Icon(Icons.pin_outlined),
                  counterText: '',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: 8),
                Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
              onPressed: () {
                final p1 = pinCtrl1.text.trim();
                final p2 = pinCtrl2.text.trim();
                if (p1.length < 4) {
                  setDlg(() => error = 'PIN must be at least 4 digits');
                  return;
                }
                if (p1 != p2) {
                  setDlg(() => error = 'PINs do not match');
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('Save PIN'),
            ),
          ],
        ),
      ),
    );

    final pin1 = pinCtrl1.text.trim();
    pinCtrl1.dispose();
    pinCtrl2.dispose();
    if (confirmed != true || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPinKey, pin1);
    if (mounted) {
      setState(() => _pinSet = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN saved'),
          backgroundColor: _teal,
        ),
      );
    }
    HapticUtils.success();
  }

  Future<void> _removePin() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove PIN?'),
        content: const Text(
          'Without a PIN, account password becomes your only fallback if biometrics fail.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPinKey);
    if (mounted) setState(() => _pinSet = false);
    HapticUtils.success();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('Security', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // ── Auth fallback explainer ─────────────────────────────
                _Banner(
                  icon: Icons.security_rounded,
                  title: 'Multi-tier authentication',
                  body: 'Face ID / Fingerprint → PIN → Account Password → Email Recovery',
                ),
                const SizedBox(height: 20),

                // ── Biometrics ──────────────────────────────────────────
                _SectionLabel('Biometrics'),
                const SizedBox(height: 8),
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      if (!_biometricAvailable)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Row(
                            children: [
                              const Icon(Icons.fingerprint, color: _slate),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'Biometrics not available on this device.',
                                  style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.face_retouching_natural_rounded, color: _teal),
                          title: const Text('Face ID / Fingerprint',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            'Require biometric unlock on app open.',
                            style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                          ),
                          value: _biometricEnabled,
                          activeColor: _teal,
                          onChanged: _toggleBiometric,
                        ),
                        if (_biometricEnabled) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Grace Period',
                                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                Text(
                                  'Skip biometric if the app was closed less than this long ago.',
                                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: kGracePeriodOptions.map((opt) {
                                    final active = _gracePeriodSeconds == opt.seconds;
                                    return ChoiceChip(
                                      label: Text(opt.label),
                                      selected: active,
                                      selectedColor: _tealDim,
                                      labelStyle: TextStyle(
                                        color: active ? _teal : theme.colorScheme.onSurface,
                                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                                        fontSize: 12,
                                      ),
                                      onSelected: (_) => _setGracePeriod(opt.seconds),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── PIN ─────────────────────────────────────────────────
                _SectionLabel('PIN Code  (Fallback tier 2)'),
                const SizedBox(height: 8),
                GlassCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.pin_rounded, color: _teal),
                        title: Text(
                          _pinSet ? 'Change PIN' : 'Set PIN',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          _pinSet
                              ? 'A PIN is set. Used when biometrics fail.'
                              : 'No PIN set. Add one as a biometric fallback.',
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                        ),
                        trailing: Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
                        onTap: _showSetPinDialog,
                      ),
                      if (_pinSet) ...[
                        const Divider(height: 1, indent: 16, endIndent: 16),
                        ListTile(
                          leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          title: const Text('Remove PIN',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.redAccent)),
                          onTap: _removePin,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Password / Email recovery ────────────────────────────
                _SectionLabel('Account Password  (Fallback tier 3)'),
                const SizedBox(height: 8),
                GlassCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline, color: _slate),
                    title: const Text('Manage Password',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Change or set your account password in Settings → Account.',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    trailing: Icon(Icons.open_in_new, size: 16, color: theme.colorScheme.onSurfaceVariant),
                    onTap: () => Navigator.of(context).pop(),
                  ),
                ),

                const SizedBox(height: 20),

                // ── Email recovery ───────────────────────────────────────
                _SectionLabel('Email Recovery  (Final tier)'),
                const SizedBox(height: 8),
                GlassCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.email_outlined, color: _slate),
                    title: const Text('Send Recovery Email',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Sends a password reset to your registered email address.',
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                    ),
                    trailing: Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    onTap: _sendRecoveryEmail,
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Future<void> _sendRecoveryEmail() async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null || !mounted) return;
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Recovery email sent to $email'),
          backgroundColor: _teal.withValues(alpha: 0.9),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0x1400D9B0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x3300D9B0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _teal, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _teal)),
                const SizedBox(height: 3),
                Text(body,
                    style: const TextStyle(fontSize: 11, color: _slate)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

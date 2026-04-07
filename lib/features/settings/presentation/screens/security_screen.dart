import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/router/app_router.dart';
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
    // Controllers are created here and disposed after the dialog's exit
    // animation completes (post-frame), so Flutter never references a
    // disposed controller during the close animation (root cause of the freeze).
    final pinCtrl1 = TextEditingController();
    final pinCtrl2 = TextEditingController();

    // The dialog returns the validated PIN string on success, or null on cancel.
    final savedPin = await showDialog<String>(
      context: context,
      builder: (ctx) {
        String? error;
        return StatefulBuilder(
          builder: (ctx, setDlg) => AlertDialog(
            title: Text(_pinSet ? 'security_screen.dialog_change_pin_title'.tr() : 'security_screen.dialog_set_pin_title'.tr()),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'security_screen.dialog_pin_fallback'.tr(),
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
                  decoration: InputDecoration(
                    labelText: 'security_screen.dialog_pin_label'.tr(),
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
                  decoration: InputDecoration(
                    labelText: 'security_screen.dialog_confirm_pin'.tr(),
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
                onPressed: () => Navigator.pop(ctx),
                child: Text('security_screen.dialog_cancel'.tr()),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
                onPressed: () {
                  final p1 = pinCtrl1.text.trim();
                  final p2 = pinCtrl2.text.trim();
                  if (p1.length < 4) {
                    setDlg(() => error = 'security_screen.dialog_pin_min'.tr());
                    return;
                  }
                  if (p1 != p2) {
                    setDlg(() => error = 'security_screen.dialog_pin_mismatch'.tr());
                    return;
                  }
                  // Pass the pin as result BEFORE the dialog closes so we
                  // never read a potentially-disposed controller after close.
                  Navigator.pop(ctx, p1);
                },
                child: Text('security_screen.dialog_save_pin'.tr()),
              ),
            ],
          ),
        );
      },
    );

    // Dispose controllers after the dialog exit animation has finished.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      pinCtrl1.dispose();
      pinCtrl2.dispose();
    });

    if (savedPin == null || savedPin.isEmpty || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPinKey, savedPin);
    if (mounted) {
      setState(() => _pinSet = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('security_screen.pin_saved'.tr()),
          backgroundColor: _teal,
        ),
      );
    }
    HapticUtils.success();
  }

  Future<void> _removePin() async {
    final pinCtrl = TextEditingController();
    String? errorMsg;
    final prefs = await SharedPreferences.getInstance();
    final savedPin = prefs.getString(_kPinKey) ?? '';
    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text('security_screen.dialog_remove_pin_title'.tr()),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('security_screen.dialog_remove_pin_body'.tr()),
              const SizedBox(height: 12),
              TextField(
                controller: pinCtrl,
                autofocus: true,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 8,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: 'security_screen.dialog_current_pin'.tr(),
                  prefixIcon: const Icon(Icons.pin_outlined),
                  counterText: '',
                  errorText: errorMsg,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('security_screen.dialog_cancel'.tr())),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
              onPressed: () {
                if (pinCtrl.text.trim() != savedPin) {
                  setDlg(() => errorMsg = 'security_screen.dialog_incorrect_pin'.tr());
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text('security_screen.dialog_remove'.tr()),
            ),
          ],
        ),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => pinCtrl.dispose());
    if (confirmed != true || !mounted) return;
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
        title: Text('security_screen.title'.tr(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // ── Biometrics ──────────────────────────────────────────
                _SectionLabel('security_screen.biometrics'.tr()),
                const SizedBox(height: 8),
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Column(
                    children: [
                      if (!_biometricAvailable)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          child: Text(
                            'security_screen.biometrics_unavailable'.tr(),
                            style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                          ),
                        )
                      else ...[
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: const Icon(Icons.face_retouching_natural_rounded, color: _teal),
                          title: Text('security_screen.face_id'.tr(),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          subtitle: Text('security_screen.require_on_open'.tr(),
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                          value: _biometricEnabled,
                          activeThumbColor: _teal,
                          onChanged: _toggleBiometric,
                        ),
                        if (_biometricEnabled) ...[
                          const Divider(height: 1),
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('security_screen.grace_period'.tr(),
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                        color: theme.colorScheme.onSurfaceVariant)),
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
                _SectionLabel('security_screen.pin_section'.tr()),
                const SizedBox(height: 8),
                GlassCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.pin_rounded, color: _teal),
                        title: Text(
                          _pinSet ? 'security_screen.change_pin'.tr() : 'security_screen.set_pin'.tr(),
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          _pinSet ? 'security_screen.pin_active'.tr() : 'security_screen.no_pin'.tr(),
                          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                        ),
                        trailing: Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
                        onTap: _showSetPinDialog,
                      ),
                      if (_pinSet) ...[
                        const Divider(height: 1, indent: 56, endIndent: 16),
                        ListTile(
                          leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                          title: Text('security_screen.remove_pin'.tr(),
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.redAccent)),
                          onTap: _removePin,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // ── Account Password ────────────────────────────────────
                _SectionLabel('security_screen.account_password'.tr()),
                const SizedBox(height: 8),
                GlassCard(
                  padding: EdgeInsets.zero,
                  child: ListTile(
                    leading: const Icon(Icons.lock_outline_rounded, color: _slate),
                    title: Text('security_screen.change_password'.tr(),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    subtitle: Text('security_screen.change_password_sub'.tr(),
                        style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
                    trailing: Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
                    onTap: () => context.push(AppRouter.settingsChangePassword),
                  ),
                ),

                const SizedBox(height: 32),
              ],
            ),
    );
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


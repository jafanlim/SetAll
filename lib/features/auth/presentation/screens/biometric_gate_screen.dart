import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/services/biometric_service.dart';
import '../../../../core/utils/haptic_utils.dart';

const String _kGracePeriodKey    = 'setall_biometric_grace_seconds';
const String _kLastForegroundKey = 'setall_last_foreground_ts';
const String _kPinKey            = 'setall_user_pin';
const _teal = Color(0xFF00D9B0);

enum _GateStep { biometric, pin, password, recovery }

/// Full-screen lock gate with silent multi-tier fallback:
///   Biometrics → PIN (if set) → Account Password → Email recovery / re-login
class BiometricGateScreen extends StatefulWidget {
  const BiometricGateScreen({super.key});

  @override
  State<BiometricGateScreen> createState() => _BiometricGateScreenState();
}

class _BiometricGateScreenState extends State<BiometricGateScreen>
    with WidgetsBindingObserver {
  final _bio = BiometricService.instance;

  _GateStep _step     = _GateStep.biometric;
  bool      _checking = true;
  bool      _bioFailed = false;
  String    _bioLabel  = 'Face ID';
  bool      _pinSet    = false;

  // Password step
  final _pwCtrl    = TextEditingController();
  bool  _pwHidden  = true;
  bool  _pwChecking = false;
  String? _pwError;

  // PIN step
  final _pinCtrl   = TextEditingController();
  bool  _pinHidden = true;
  String? _pinError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pwCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _recordForegroundTime();
  }

  Future<void> _recordForegroundTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastForegroundKey, DateTime.now().millisecondsSinceEpoch);
  }

  Future<bool> _isWithinGracePeriod() async {
    final prefs = await SharedPreferences.getInstance();
    final graceSecs = prefs.getInt(_kGracePeriodKey) ?? 30;
    if (graceSecs == 0) return false;
    final lastTs = prefs.getInt(_kLastForegroundKey);
    if (lastTs == null) return false;
    return DateTime.now().millisecondsSinceEpoch - lastTs < (graceSecs * 1000);
  }

  Future<void> _start() async {
    setState(() { _checking = true; _bioFailed = false; });

    if (await _isWithinGracePeriod()) {
      _unlock();
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final pin   = prefs.getString(_kPinKey);
    if (mounted) setState(() => _pinSet = pin != null && pin.isNotEmpty);

    final available = await _bio.getAvailableBiometrics();
    if (mounted) {
      setState(() {
        _bioLabel = available.contains(BiometricType.face) ? 'Face ID' : 'Touch ID';
        _checking = false;
      });
    }

    final ok = await _bio.authenticate(reason: 'Unlock SetAll');
    if (!mounted) return;
    if (ok) {
      _unlock();
    } else {
      // Silently advance to next tier
      setState(() {
        _bioFailed = true;
        _step = _pinSet ? _GateStep.pin : _GateStep.password;
      });
    }
  }

  void _unlock() {
    _recordForegroundTime();
    _bio.markSessionUnlocked();
    if (mounted) context.go(AppRouter.dashboard);
  }

  Future<void> _submitPin() async {
    final entered = _pinCtrl.text.trim();
    final prefs   = await SharedPreferences.getInstance();
    final stored  = prefs.getString(_kPinKey) ?? '';
    if (entered == stored) {
      _unlock();
    } else {
      setState(() => _pinError = 'Incorrect PIN');
      HapticUtils.error();
    }
  }

  Future<void> _submitPassword() async {
    final pw = _pwCtrl.text.trim();
    if (pw.isEmpty) return;
    setState(() { _pwChecking = true; _pwError = null; });
    try {
      final email = Supabase.instance.client.auth.currentUser?.email ?? '';
      await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: pw,
      );
      _unlock();
    } on AuthException catch (e) {
      if (mounted) setState(() { _pwChecking = false; _pwError = e.message; });
      HapticUtils.error();
    } catch (_) {
      if (mounted) setState(() { _pwChecking = false; _pwError = 'Incorrect password'; });
      HapticUtils.error();
    }
  }

  Future<void> _sendRecoveryEmail() async {
    final email = Supabase.instance.client.auth.currentUser?.email;
    if (email == null) return;
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(email);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Recovery email sent to $email'),
          backgroundColor: _teal.withValues(alpha: 0.9),
        ));
      }
    } catch (_) {}
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              child: switch (_step) {
                _GateStep.biometric => _buildBioStep(theme),
                _GateStep.pin       => _buildPinStep(theme),
                _GateStep.password  => _buildPasswordStep(theme),
                _GateStep.recovery  => _buildRecoveryStep(theme),
              },
            ),
          ),
        ),
      ),
    );
  }

  // ── Step 1: Biometrics ────────────────────────────────────────────────────
  Widget _buildBioStep(ThemeData theme) {
    return Column(
      key: const ValueKey('bio'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.fingerprint, size: 72,
            color: _bioFailed ? theme.colorScheme.error : _teal),
        const SizedBox(height: 20),
        Text(
          _checking ? 'Checking…' : 'Unlock with $_bioLabel',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        if (_bioFailed) ...[
          const SizedBox(height: 8),
          Text('Biometric failed.',
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
              textAlign: TextAlign.center),
        ],
        const SizedBox(height: 24),
        if (_checking)
          const CircularProgressIndicator(color: _teal, strokeWidth: 2)
        else ...[
          FilledButton.icon(
            onPressed: _start,
            icon: const Icon(Icons.fingerprint, size: 18),
            label: Text('Try $_bioLabel again'),
            style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: () => setState(() =>
                _step = _pinSet ? _GateStep.pin : _GateStep.password),
            child: const Text('Use another method'),
          ),
        ],
      ],
    );
  }

  // ── Step 2: PIN ───────────────────────────────────────────────────────────
  Widget _buildPinStep(ThemeData theme) {
    return Column(
      key: const ValueKey('pin'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.pin_rounded, size: 56, color: _teal),
        const SizedBox(height: 20),
        Text('Enter your PIN',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 24),
        TextField(
          controller: _pinCtrl,
          autofocus: true,
          obscureText: _pinHidden,
          keyboardType: TextInputType.number,
          maxLength: 8,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          onSubmitted: (_) => _submitPin(),
          decoration: InputDecoration(
            labelText: 'PIN',
            counterText: '',
            errorText: _pinError,
            suffixIcon: IconButton(
              icon: Icon(_pinHidden ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _pinHidden = !_pinHidden),
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _submitPin,
            style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
            child: const Text('Unlock'),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() { _pinError = null; _step = _GateStep.password; }),
          child: const Text("Can't remember PIN?"),
        ),
      ],
    );
  }

  // ── Step 3: Password ──────────────────────────────────────────────────────
  Widget _buildPasswordStep(ThemeData theme) {
    return Column(
      key: const ValueKey('pw'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.lock_outline_rounded, size: 56, color: _teal),
        const SizedBox(height: 20),
        Text('Enter your password',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          Supabase.instance.client.auth.currentUser?.email ?? '',
          style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _pwCtrl,
          autofocus: true,
          obscureText: _pwHidden,
          onSubmitted: (_) => _submitPassword(),
          decoration: InputDecoration(
            labelText: 'Account password',
            errorText: _pwError,
            suffixIcon: IconButton(
              icon: Icon(_pwHidden ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _pwHidden = !_pwHidden),
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: _pwChecking
              ? const Center(child: CircularProgressIndicator(color: _teal, strokeWidth: 2))
              : FilledButton(
                  onPressed: _submitPassword,
                  style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
                  child: const Text('Unlock'),
                ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _step = _GateStep.recovery),
          child: const Text("Forgot password?"),
        ),
      ],
    );
  }

  // ── Step 4: Recovery ──────────────────────────────────────────────────────
  Widget _buildRecoveryStep(ThemeData theme) {
    return Column(
      key: const ValueKey('recovery'),
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.email_outlined, size: 56, color: _teal),
        const SizedBox(height: 20),
        Text('Account Recovery',
            style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Text(
          'We will send a reset link to\n${Supabase.instance.client.auth.currentUser?.email ?? 'your email'}',
          style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _sendRecoveryEmail,
            icon: const Icon(Icons.send_rounded, size: 18),
            label: const Text('Send recovery email'),
            style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              await Supabase.instance.client.auth.signOut();
            },
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign out and re-login'),
            style: OutlinedButton.styleFrom(side: const BorderSide(color: _teal)),
          ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() => _step = _GateStep.password),
          child: const Text('Back'),
        ),
      ],
    );
  }
}

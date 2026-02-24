import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/services/biometric_service.dart';

const String _kGracePeriodKey       = 'setall_biometric_grace_seconds';
const String _kLastForegroundKey    = 'setall_last_foreground_ts';

/// Full-screen gate: requires Face ID / Touch ID before continuing to the app.
/// Respects the "grace period" setting – if the app was backgrounded for less
/// than [gracePeriodSeconds] seconds, the gate is skipped automatically.
class BiometricGateScreen extends StatefulWidget {
  const BiometricGateScreen({super.key});

  @override
  State<BiometricGateScreen> createState() => _BiometricGateScreenState();
}

class _BiometricGateScreenState extends State<BiometricGateScreen>
    with WidgetsBindingObserver {
  final _bio = BiometricService.instance;
  bool _checking = true;
  bool _failed = false;
  String _biometricLabel = 'Face ID';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resolveAndAuthenticate();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _recordForegroundTime();
    }
  }

  Future<void> _recordForegroundTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      _kLastForegroundKey,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<bool> _isWithinGracePeriod() async {
    final prefs = await SharedPreferences.getInstance();
    final graceSecs = prefs.getInt(_kGracePeriodKey) ?? 30;
    if (graceSecs == 0) return false;

    final lastTs = prefs.getInt(_kLastForegroundKey);
    if (lastTs == null) return false;

    final elapsed = DateTime.now().millisecondsSinceEpoch - lastTs;
    return elapsed < (graceSecs * 1000);
  }

  Future<void> _resolveAndAuthenticate() async {
    setState(() { _checking = true; _failed = false; });

    // Check grace period first — skip biometric if within window
    if (await _isWithinGracePeriod()) {
      if (mounted) context.go(AppRouter.dashboard);
      return;
    }

    final available = await _bio.getAvailableBiometrics();
    if (mounted) {
      setState(() {
        _biometricLabel = available.contains(BiometricType.face)
            ? 'Face ID'
            : 'Touch ID';
        _checking = false;
      });
    }

    final ok = await _bio.authenticate(reason: 'Unlock SetAll');
    if (!mounted) return;
    if (ok) {
      await _recordForegroundTime(); // reset grace period clock on successful auth
      if (!mounted) return;
      context.go(AppRouter.dashboard);
    } else {
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.fingerprint,
                  size: 80,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Text(
                  'Unlock with $_biometricLabel',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                if (_failed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Text(
                      'Authentication failed or was cancelled.',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                if (_checking)
                  const SizedBox(
                    height: 28,
                    width: 28,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  FilledButton.icon(
                    onPressed: _failed ? _resolveAndAuthenticate : null,
                    icon: const Icon(Icons.fingerprint),
                    label: Text('Try $_biometricLabel again'),
                  ),
                const SizedBox(height: 24),
                                                    TextButton(
                                                      onPressed: () async {
                                                        final navigator = Navigator.of(context);
                                                        await _bio.setUseBiometric(false);
                                                        if (!mounted) return;
                                                        navigator.pushNamedAndRemoveUntil(AppRouter.dashboard, (route) => false);
                                                      },
                                                    child: const Text('Skip and use app without biometric'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

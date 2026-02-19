import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/services/biometric_service.dart';

/// Full-screen gate: requires Face ID / Touch ID before continuing to the app.
class BiometricGateScreen extends StatefulWidget {
  const BiometricGateScreen({super.key});

  @override
  State<BiometricGateScreen> createState() => _BiometricGateScreenState();
}

class _BiometricGateScreenState extends State<BiometricGateScreen> {
  final _bio = BiometricService.instance;
  bool _checking = true;
  bool _failed = false;
  String _biometricLabel = 'Face ID';

  @override
  void initState() {
    super.initState();
    _resolveAndAuthenticate();
  }

  Future<void> _resolveAndAuthenticate() async {
    setState(() {
      _checking = true;
      _failed = false;
    });
    final available = await _bio.getAvailableBiometrics();
    if (mounted) {
      setState(() {
        _biometricLabel = available.contains(BiometricType.face) ? 'Face ID' : 'Touch ID';
        _checking = false;
      });
    }
    final ok = await _bio.authenticate(reason: 'Unlock SetAll');
    if (!mounted) return;
    if (ok) {
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
                    await _bio.setUseBiometric(false);
                    if (mounted) context.go(AppRouter.dashboard);
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

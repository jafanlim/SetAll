import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'biometric_platform_stub.dart'
    if (dart.library.io) 'biometric_platform_io.dart' as platform;

/// Manages Face ID / Touch ID and the "use biometric to unlock" preference.
class BiometricService {
  BiometricService._();
  static final BiometricService _instance = BiometricService._();
  static BiometricService get instance => _instance;

  static const _keyUseBiometric = 'setall_use_biometric';
  final LocalAuthentication _auth = LocalAuthentication();
  final FlutterSecureStorage _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  bool get _isMobile => platform.kBiometricPlatformMobile;

  /// Whether we can use biometrics on this device (Face ID / Touch ID).
  Future<bool> canUseBiometrics() async {
    if (!_isMobile) return false;
    try {
      return await _auth.canCheckBiometrics && await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  /// Whether the user has opted in to unlock the app with Face ID.
  Future<bool> getUseBiometric() async {
    if (!_isMobile) return false;
    try {
      final v = await _storage.read(key: _keyUseBiometric);
      return v == 'true';
    } catch (_) {
      return false;
    }
  }

  /// Set whether to require Face ID on next app open.
  Future<void> setUseBiometric(bool value) async {
    if (!_isMobile) return;
    try {
      if (value) {
        await _storage.write(key: _keyUseBiometric, value: 'true');
      } else {
        await _storage.delete(key: _keyUseBiometric);
      }
    } catch (_) {}
  }

  /// Perform biometric authentication. Returns true on success.
  Future<bool> authenticate({String? reason}) async {
    if (!_isMobile) return false;
    try {
      return await _auth.authenticate(
        localizedReason: reason ?? 'Unlock SetAll',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );
    } catch (_) {
      return false;
    }
  }

  /// List of available biometric types (e.g. face, fingerprint).
  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (!_isMobile) return [];
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }
}

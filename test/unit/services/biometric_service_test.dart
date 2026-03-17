// Tests for BiometricService — session gate, non-mobile safe defaults,
// and preference flag logic.
//
// BiometricService._isMobile = kBiometricPlatformMobile which on a macOS
// test runner = !kIsWeb && (Platform.isIOS || Platform.isAndroid) = false.
// This means all hardware-dependent paths return safe defaults, letting us
// test the logic gates and session state machine without a real device.

import 'package:flutter_test/flutter_test.dart';
import 'package:setall/core/services/biometric_service.dart';

void main() {
  final svc = BiometricService.instance;

  setUp(() {
    // Reset session state before each test.
    svc.resetSession();
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 1. Session state machine
  // ─────────────────────────────────────────────────────────────────────────
  group('Session state machine', () {
    test('initial state: sessionUnlocked is false', () {
      expect(svc.sessionUnlocked, isFalse);
    });

    test('markSessionUnlocked() sets sessionUnlocked to true', () {
      svc.markSessionUnlocked();
      expect(svc.sessionUnlocked, isTrue);
    });

    test('resetSession() clears sessionUnlocked back to false', () {
      svc.markSessionUnlocked();
      expect(svc.sessionUnlocked, isTrue);
      svc.resetSession();
      expect(svc.sessionUnlocked, isFalse);
    });

    test('multiple markSessionUnlocked() calls are idempotent', () {
      svc.markSessionUnlocked();
      svc.markSessionUnlocked();
      expect(svc.sessionUnlocked, isTrue);
    });

    test('multiple resetSession() calls are idempotent', () {
      svc.resetSession();
      svc.resetSession();
      expect(svc.sessionUnlocked, isFalse);
    });

    test('unlock → reset → unlock cycle works', () {
      svc.markSessionUnlocked();
      expect(svc.sessionUnlocked, isTrue);
      svc.resetSession();
      expect(svc.sessionUnlocked, isFalse);
      svc.markSessionUnlocked();
      expect(svc.sessionUnlocked, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. Non-mobile safe defaults
  // ─────────────────────────────────────────────────────────────────────────
  // On macOS/desktop test runner, _isMobile = false, so all hardware-
  // dependent methods must return their safe defaults without throwing.
  group('Non-mobile platform safe defaults', () {
    test('canUseBiometrics() returns false on non-mobile', () async {
      final result = await svc.canUseBiometrics();
      expect(result, isFalse,
          reason: 'Biometrics unavailable on non-mobile platforms');
    });

    test('getUseBiometric() returns false on non-mobile', () async {
      final result = await svc.getUseBiometric();
      expect(result, isFalse,
          reason: 'Preference meaningless on non-mobile; must default false');
    });

    test('setUseBiometric(true) is a no-op on non-mobile (no throw)', () async {
      await expectLater(svc.setUseBiometric(true), completes);
    });

    test('setUseBiometric(false) is a no-op on non-mobile (no throw)',
        () async {
      await expectLater(svc.setUseBiometric(false), completes);
    });

    test('authenticate() returns false on non-mobile', () async {
      final result = await svc.authenticate(reason: 'Test unlock');
      expect(result, isFalse,
          reason: 'Hardware auth not available on non-mobile');
    });

    test('getAvailableBiometrics() returns empty list on non-mobile', () async {
      final result = await svc.getAvailableBiometrics();
      expect(result, isEmpty,
          reason: 'No biometric hardware on non-mobile platforms');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 3. Router gate integration logic
  // ─────────────────────────────────────────────────────────────────────────
  // Mirrors the gate logic in AppRouter.create() lines 109-118.
  group('Router biometric gate logic', () {
    test('gate not triggered when biometric disabled', () async {
      // getUseBiometric() returns false on non-mobile — gate skipped.
      final useBio = await svc.getUseBiometric();
      expect(useBio, isFalse,
          reason: 'Gate must not activate on platforms with no biometrics');
    });

    test('gate skipped when session already unlocked', () async {
      svc.markSessionUnlocked();
      // Even if useBio were true, sessionUnlocked bypasses the gate.
      // Simulate the router guard: if (!bio.sessionUnlocked) checkBio()
      final needsCheck = !svc.sessionUnlocked;
      expect(needsCheck, isFalse,
          reason: 'Unlocked session must bypass the biometric gate');
    });

    test('gate would fire on locked session with biometric enabled', () {
      // sessionUnlocked is false (reset in setUp).
      // Simulate: useBio=true AND !sessionUnlocked → gate fires.
      const simulatedUseBio = true;
      final gateFiresCheck = simulatedUseBio && !svc.sessionUnlocked;
      expect(gateFiresCheck, isTrue,
          reason: 'Gate must fire when locked session + biometric enabled');
    });

    test('gate clears after markSessionUnlocked', () {
      const simulatedUseBio = true;
      expect(simulatedUseBio && !svc.sessionUnlocked, isTrue);
      svc.markSessionUnlocked();
      expect(simulatedUseBio && !svc.sessionUnlocked, isFalse);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 4. Singleton contract
  // ─────────────────────────────────────────────────────────────────────────
  group('Singleton contract', () {
    test('BiometricService.instance returns same object every time', () {
      final a = BiometricService.instance;
      final b = BiometricService.instance;
      expect(identical(a, b), isTrue);
    });

    test('session state is shared across references (singleton)', () {
      final ref1 = BiometricService.instance;
      final ref2 = BiometricService.instance;
      ref1.markSessionUnlocked();
      expect(ref2.sessionUnlocked, isTrue,
          reason: 'Both references point to the same singleton instance');
      ref1.resetSession();
    });
  });
}

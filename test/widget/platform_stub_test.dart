// Tests for platform-agnostic service stubs.
//
// Verifies that the web stubs for dart:io and window_manager do not crash
// when their APIs are invoked. These stubs are selected via conditional
// imports when compiling for web and must silently no-op.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:setall/core/stubs/io_stub.dart' as io_stub;
import 'package:setall/core/stubs/window_manager_stub.dart' as wm_stub;

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // 1. io_stub.dart
  // ─────────────────────────────────────────────────────────────────────────
  group('io_stub (web replacement for dart:io)', () {
    test('Platform properties return safe defaults', () {
      expect(io_stub.Platform.isMacOS, isFalse);
      expect(io_stub.Platform.isWindows, isFalse);
      expect(io_stub.Platform.isLinux, isFalse);
      expect(io_stub.Platform.pathSeparator, equals('/'));
    });

    test('File stub reads return empty data', () async {
      final file = io_stub.File('/tmp/nonexistent');
      expect(file.path, equals('/tmp/nonexistent'));
      expect(await file.readAsString(), equals(''));
      expect(await file.readAsBytes(), isEmpty);
    });

    test('File.openWrite returns a no-op sink', () async {
      final file = io_stub.File('/tmp/test');
      final sink = file.openWrite();
      // These must not throw
      sink.add([1, 2, 3]);
      await sink.flush();
      await sink.close();
    });

    test('Process.start completes without error', () async {
      final result = await io_stub.Process.start('echo', ['hello']);
      // Stub returns null/void — just verifying no crash
      expect(result, isNull);
    });

    test('exit() throws UnsupportedError on web', () {
      expect(() => io_stub.exit(0), throwsUnsupportedError);
    });

    test('ProcessStartMode.detached exists', () {
      expect(io_stub.ProcessStartMode.detached, isNotNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // 2. window_manager_stub.dart
  // ─────────────────────────────────────────────────────────────────────────
  group('window_manager_stub (web replacement for window_manager)', () {
    test('windowManager stub methods complete without error', () async {
      final wm = wm_stub.windowManager;
      await wm.ensureInitialized();
      await wm.waitUntilReadyToShow(const wm_stub.WindowOptions());
      await wm.show();
      await wm.minimize();
      await wm.maximize();
      await wm.unmaximize();
      expect(await wm.isMaximized(), isFalse);
      await wm.close();
    });

    test('WindowOptions accepts all named parameters', () {
      const opts = wm_stub.WindowOptions(
        minimumSize: null,
        size: null,
        center: true,
        titleBarStyle: wm_stub.TitleBarStyle.hidden,
        windowButtonVisibility: false,
      );
      expect(opts.center, isTrue);
      expect(opts.titleBarStyle, equals(wm_stub.TitleBarStyle.hidden));
    });

    test('TitleBarStyle enum has both values', () {
      expect(wm_stub.TitleBarStyle.values, hasLength(2));
      expect(wm_stub.TitleBarStyle.values,
          containsAll([wm_stub.TitleBarStyle.hidden, wm_stub.TitleBarStyle.normal]));
    });

    test('DragToMoveArea renders its child', () {
      // DragToMoveArea.build just returns child — verify constructor
      const widget = wm_stub.DragToMoveArea(child: SizedBox());
      expect(widget.child, isA<SizedBox>());
    });
  });
}

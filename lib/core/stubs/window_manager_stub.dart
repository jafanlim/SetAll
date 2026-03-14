// Stub for web builds — window_manager is not supported on web.
// The conditional import in main.dart selects this file on web
// so the window_manager channel is never registered.

import 'package:flutter/widgets.dart';

class WindowOptions {
  const WindowOptions({
    this.minimumSize,
    this.size,
    this.center,
    this.titleBarStyle,
    this.windowButtonVisibility,
  });
  final dynamic minimumSize;
  final dynamic size;
  final bool? center;
  final dynamic titleBarStyle;
  final bool? windowButtonVisibility;
}

enum TitleBarStyle { hidden, normal }

class _WindowManagerStub {
  Future<void> ensureInitialized() async {}
  Future<void> waitUntilReadyToShow(WindowOptions options) async {}
  Future<void> show() async {}
  Future<void> minimize() async {}
  Future<void> maximize() async {}
  Future<void> unmaximize() async {}
  Future<bool> isMaximized() async => false;
  Future<void> close() async {}
}

final windowManager = _WindowManagerStub();

// ignore: must_be_immutable
class DragToMoveArea extends StatelessWidget {
  const DragToMoveArea({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => child;
}

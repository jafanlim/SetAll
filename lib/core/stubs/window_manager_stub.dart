// Stub for web builds — window_manager is not supported on web.
// The conditional import in main.dart selects this file on web
// so the window_manager channel is never registered.

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
}

final windowManager = _WindowManagerStub();

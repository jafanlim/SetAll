import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// On desktop with a hidden title bar, pushes content down so it never sits
/// behind the OS window controls / traffic lights.
///
/// macOS: 28 px spacer is handled by [MediaQuery.padding.top] injected by the
///        OS when [TitleBarStyle.hidden] is used, so no extra padding needed
///        there — the [AppBar] already honours it.
///
/// Windows: We rendered a 36 px controls row inside the sidebar, but push
///          routes are full-screen and bypass the sidebar entirely. They need
///          an explicit 36 px top inset so the [AppBar] title clears the
///          custom min/max/close buttons that float in the top-right corner.
///
/// On mobile / web this widget is a no-op pass-through.
class DesktopInset extends StatelessWidget {
  const DesktopInset({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.windows) return child;

    // Increase MediaQuery.padding.top by the height of our custom title bar
    // row (36 px) so every Scaffold + AppBar inside this subtree automatically
    // reserves that space without any per-screen changes.
    final mq      = MediaQuery.of(context);
    final current = mq.padding;
    const kWinTitleBarHeight = 36.0;

    return MediaQuery(
      data: mq.copyWith(
        padding: current.copyWith(top: current.top + kWinTitleBarHeight),
      ),
      child: child,
    );
  }
}

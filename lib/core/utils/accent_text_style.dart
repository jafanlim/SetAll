import 'package:flutter/material.dart';

/// Returns a list of [Shadow]s that give accent-coloured text a subtle dark
/// edge so it reads clearly against light (Slate-100/300) backgrounds.
/// In dark mode the shadows are invisible (near-zero alpha) so they're
/// effectively a no-op there.
List<Shadow> accentShadows(BuildContext context, {double opacity = 0.22}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  if (isDark) return const [];
  return [
    Shadow(
      color: const Color(0xFF0F172A).withValues(alpha: opacity), // Slate-900
      offset: const Offset(0, 0.5),
      blurRadius: 3,
    ),
  ];
}

/// Convenience extension so you can write:
///   style: TextStyle(color: _teal, ...).withAccentShadow(context)
extension AccentTextStyleX on TextStyle {
  TextStyle withAccentShadow(BuildContext context, {double opacity = 0.22}) {
    return copyWith(shadows: accentShadows(context, opacity: opacity));
  }
}

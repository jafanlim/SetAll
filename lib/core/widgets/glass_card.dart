import 'dart:ui';

import 'package:flutter/material.dart';

/// Glassmorphism card: BackdropFilter with sigma 15 for 2026 fintech aesthetic.
/// Use for headers, bottom sheets, and expense cards.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius,
    this.padding,
    this.color,
    this.border,
  });

  final Widget child;
  final BorderRadius? borderRadius;
  final EdgeInsets? padding;
  final Color? color;
  final Border? border;

  // Slate-300 / Slate-400 for light mode clarity; glassmorphic in dark mode.
  static const _slate300 = Color(0xFFCBD5E1);
  static const _slate400 = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final radius = borderRadius ?? BorderRadius.circular(16);

    final surfaceColor = color ?? (isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)
        : _slate300);
    final borderColor = isDark
        ? theme.colorScheme.outline.withValues(alpha: 0.2)
        : _slate400;

    final container = Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: radius,
        border: border ?? Border.all(color: borderColor, width: 1),
      ),
      child: child,
    );

    if (!isDark) {
      // Skip backdrop blur in light mode — nothing to blur behind a solid card.
      return ClipRRect(borderRadius: radius, child: container);
    }

    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15.0, sigmaY: 15.0),
        child: container,
      ),
    );
  }
}

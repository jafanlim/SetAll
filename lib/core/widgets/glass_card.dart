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

  static const _slate50  = Color(0xFFF8FAFC); // mobile light card bg
  static const _slate200 = Color(0xFFE2E8F0); // mobile light border / desktop card bg
  static const _slate300 = Color(0xFFCBD5E1); // desktop light border

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final isDark   = theme.brightness == Brightness.dark;
    // Detect desktop by checking if the scaffold is close to Slate-300.
    // We key off surfaceContainerHighest being overridden in desktopLight.
    final scaffold = theme.scaffoldBackgroundColor;
    final isDesktopLight = !isDark &&
        scaffold.red   < 215 &&
        scaffold.green < 225 &&
        scaffold.blue  < 235;
    final radius = borderRadius ?? BorderRadius.circular(16);

    Color surfaceColor;
    Color borderColor;
    List<BoxShadow>? shadows;

    if (isDark) {
      surfaceColor = color ?? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35);
      borderColor  = theme.colorScheme.outline.withValues(alpha: 0.2);
      shadows      = null;
    } else if (isDesktopLight) {
      // Desktop light: card sits just above the Slate-300 scaffold via shadow,
      // not a stark white fill. Slate-200 bg + faint shadow = gentle lift.
      surfaceColor = color ?? _slate200;
      borderColor  = _slate300.withValues(alpha: 0.6);
      shadows      = [
        BoxShadow(
          color: const Color(0xFF64748B).withValues(alpha: 0.10), // Slate-500 10%
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];
    } else {
      // Mobile light: Slate-50 bg (near-white) on #F5F5F7 scaffold — subtle.
      surfaceColor = color ?? _slate50;
      borderColor  = _slate200;
      shadows      = null;
    }

    final container = Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: radius,
        border: border ?? Border.all(color: borderColor, width: 1),
        boxShadow: shadows,
      ),
      child: child,
    );

    if (!isDark) {
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

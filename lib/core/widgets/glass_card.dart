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

  static const _white    = Color(0xFFFFFFFF);
  static const _slate50  = Color(0xFFF8FAFC); // mobile light card bg
  static const _slate200 = Color(0xFFE2E8F0); // border

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final isDark   = theme.brightness == Brightness.dark;
    // Detect desktop light: scaffold overridden to Slate-300 in desktopLight.
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
      // White card on grey scaffold — macOS-native look, lifted by shadow.
      surfaceColor = color ?? _white;
      borderColor  = _slate200.withValues(alpha: 0.5);
      shadows      = [
        BoxShadow(
          color: const Color(0xFF475569).withValues(alpha: 0.08), // Slate-600 8%
          blurRadius: 12,
          spreadRadius: 0,
          offset: const Offset(0, 2),
        ),
        BoxShadow(
          color: const Color(0xFF475569).withValues(alpha: 0.04),
          blurRadius: 4,
          offset: const Offset(0, 1),
        ),
      ];
    } else {
      // Mobile light: Slate-50 bg on #F5F5F7 scaffold — subtle lift.
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

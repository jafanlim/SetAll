import 'package:flutter/material.dart';

/// Consistent top-bar icon button used across all screens.
/// Renders a semi-transparent pill/circle with a 32×32 tap target.
class AppTopButton extends StatelessWidget {
  const AppTopButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
  });

  final IconData    icon;
  final VoidCallback onPressed;
  final String?     tooltip;
  final Color?      color;

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fg     = color ?? theme.colorScheme.onSurface;

    final btn = GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.07),
            width: 1,
          ),
        ),
        child: Icon(icon, size: 18, color: fg),
      ),
    );

    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: btn);
    }
    return btn;
  }
}

/// Variant that wraps a PopupMenuButton with the same visual treatment.
class AppTopPopupButton<T> extends StatelessWidget {
  const AppTopPopupButton({
    super.key,
    required this.icon,
    required this.itemBuilder,
    required this.onSelected,
    this.tooltip,
    this.initialValue,
    this.color,
  });

  final IconData           icon;
  final List<PopupMenuEntry<T>> Function(BuildContext) itemBuilder;
  final void Function(T)   onSelected;
  final String?            tooltip;
  final T?                 initialValue;
  final Color?             color;

  @override
  Widget build(BuildContext context) {
    final theme  = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fg     = color ?? theme.colorScheme.onSurface;

    return PopupMenuButton<T>(
      tooltip:      tooltip ?? '',
      initialValue: initialValue,
      onSelected:   onSelected,
      itemBuilder:  itemBuilder,
      offset:       const Offset(0, 44),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.black.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.08)
                : Colors.black.withValues(alpha: 0.07),
            width: 1,
          ),
        ),
        child: Icon(icon, size: 18, color: fg),
      ),
    );
  }
}

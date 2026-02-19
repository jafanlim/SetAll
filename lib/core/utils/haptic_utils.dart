import 'package:flutter/services.dart';

/// Tactile feedback on primary actions and success states (2026 fintech UX).
class HapticUtils {
  HapticUtils._();

  /// Call on primary button press (e.g. Save, Add expense, Confirm).
  static void primaryTap() {
    HapticFeedback.mediumImpact();
  }

  /// Call on success (e.g. expense saved, delete confirmed).
  static void success() {
    HapticFeedback.heavyImpact();
  }

  /// Call on selection change (e.g. segment, chip).
  static void selection() {
    HapticFeedback.selectionClick();
  }

  /// Call on light tap (e.g. list item).
  static void lightTap() {
    HapticFeedback.lightImpact();
  }
}

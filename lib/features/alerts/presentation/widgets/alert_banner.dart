import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../data/models/wallet_entry_model.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../data/alert_service.dart';

// ---------------------------------------------------------------------------
// AlertBannerOverlay
//
// Wraps any screen with a banner that surfaces pending alerts from
// [alertQueueProvider]. Shows one banner at a time; the user dismisses it.
// Anomaly alerts are tappable — they navigate to the offending expense.
// ---------------------------------------------------------------------------
class AlertBannerOverlay extends ConsumerWidget {
  const AlertBannerOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(alertQueueProvider);
    if (queue.isEmpty) return child;

    final alert = queue.first;

    void onDismiss() {
      HapticUtils.selection();
      ref.read(alertQueueProvider.notifier).dismiss(alert.refKey);
    }

    void onTap() {
      if (alert.type != AlertType.anomaly) return;
      HapticUtils.lightTap();
      onDismiss(); // dismiss banner before navigating
      if (alert.expenseGroupId != null && alert.expenseGroupId!.isNotEmpty) {
        // Group expense: navigate to the group detail screen.
        context.push('/group/${alert.expenseGroupId}');
      } else if (alert.payload != null) {
        // Personal/wallet expense: navigate to the wallet entry detail screen.
        final model = WalletEntryModel.fromJson(alert.payload!);
        context.push('/wallet/entry', extra: model);
      } else {
        // Fallback: no payload, navigate to activity.
        context.push('/activity');
      }
    }

    return Stack(
      children: [
        child,
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
          child: _AlertBanner(
            alert: alert,
            onDismiss: onDismiss,
            onTap: onTap,
          ),
        ),
      ],
    );
  }
}

class _AlertBanner extends StatefulWidget {
  const _AlertBanner({
    required this.alert,
    required this.onDismiss,
    required this.onTap,
  });
  final ProactiveAlert alert;
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  @override
  State<_AlertBanner> createState() => _AlertBannerState();
}

class _AlertBannerState extends State<_AlertBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _slide = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Color get _accentColor {
    switch (widget.alert.type) {
      case AlertType.anomaly:
        return const Color(0xFFF59E0B);
      case AlertType.budget80:
        return const Color(0xFFF97316);
      case AlertType.budget100:
        return const Color(0xFFEF4444);
    }
  }

  IconData get _icon {
    switch (widget.alert.type) {
      case AlertType.anomaly:
        return Icons.trending_up_rounded;
      case AlertType.budget80:
        return Icons.warning_amber_rounded;
      case AlertType.budget100:
        return Icons.warning_rounded;
    }
  }

  bool get _isTappable => widget.alert.type == AlertType.anomaly;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -1.2),
        end: Offset.zero,
      ).animate(_slide),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: _isTappable ? widget.onTap : null,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
            decoration: BoxDecoration(
              color: isDark
                  ? theme.colorScheme.surfaceContainerHigh
                  : theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _accentColor.withAlpha(100)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _accentColor.withAlpha(30),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(_icon, size: 16, color: _accentColor),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.alert.title.tr(),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.alert.body.tr(),
                        style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: widget.onDismiss,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

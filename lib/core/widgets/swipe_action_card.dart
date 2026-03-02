import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// A card wrapper that slides left to reveal action buttons.
/// Unlike [Dismissible], the card stays open after release so the user
/// can tap the revealed buttons. Tap anywhere on the card (when closed)
/// or outside the actions (when open) to close it.
class SwipeActionCard extends StatefulWidget {
  const SwipeActionCard({
    super.key,
    required this.child,
    required this.actions,
    this.actionsPanelWidth = 160,
  });

  final Widget child;

  /// Buttons shown when the card is swiped open.
  final List<SwipeAction> actions;

  /// Total width of the revealed actions panel.
  final double actionsPanelWidth;

  @override
  State<SwipeActionCard> createState() => _SwipeActionCardState();
}

class _SwipeActionCardState extends State<SwipeActionCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<Offset> _slide;

  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _slide = Tween<Offset>(
      begin: Offset.zero,
      end: Offset(-widget.actionsPanelWidth / 400, 0),
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _open() {
    setState(() => _isOpen = true);
    _ctrl.forward();
  }

  void _close() {
    setState(() => _isOpen = false);
    _ctrl.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final panelW = widget.actionsPanelWidth.toDouble();

    return GestureDetector(
      // Close when tapping the main card while open.
      onTap: _isOpen ? _close : null,
      // Horizontal drag detection.
      onHorizontalDragUpdate: (d) {
        if (d.delta.dx < -4 && !_isOpen) _open();
        if (d.delta.dx > 4 && _isOpen) _close();
      },
      child: Stack(
        children: [
          // ── Action panel (behind the card) ──────────────────────────────
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: panelW,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: widget.actions.map((a) {
                    return GestureDetector(
                      onTap: () {
                        _close();
                        a.onTap();
                      },
                      child: Container(
                        width: panelW / widget.actions.length,
                        alignment: Alignment.center,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(a.icon, color: a.color, size: 22.sp),
                            SizedBox(height: 4.h),
                            Text(
                              a.label,
                              style: TextStyle(
                                color: a.color,
                                fontSize: 10.sp,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),

          // ── Sliding card ────────────────────────────────────────────────
          SlideTransition(
            position: _slide,
            child: widget.child,
          ),
        ],
      ),
    );
  }
}

/// One action button shown in the revealed panel.
class SwipeAction {
  const SwipeAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

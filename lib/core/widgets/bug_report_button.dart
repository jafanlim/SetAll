import 'dart:async';

import 'package:flutter/material.dart';

import '../../features/support/presentation/screens/bug_report_screen.dart';

class BugReportButton extends StatefulWidget {
  const BugReportButton({super.key});

  @override
  State<BugReportButton> createState() => _BugReportButtonState();
}

class _BugReportButtonState extends State<BugReportButton> {
  static const _buttonSize = 56.0;
  static const _peekOffset = 28.0;

  double _topFraction = 0.35;
  bool   _onLeftWall  = false;
  bool   _expanded    = false;
  Timer? _collapseTimer;

  void _resetCollapseTimer() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _expanded = false);
    });
  }

  void _openBugReport() {
    setState(() => _expanded = false);
    _collapseTimer?.cancel();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BugReportScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final top  = (_topFraction * size.height - _buttonSize / 2)
        .clamp(80.0, size.height - 120.0);
    final peek = _expanded ? 0.0 : _peekOffset;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      top:   top,
      left:  _onLeftWall  ? -peek : null,
      right: !_onLeftWall ? -peek : null,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (d) {
          setState(() {
            _topFraction = ((_topFraction * size.height + d.delta.dy) /
                size.height).clamp(0.1, 0.9);
          });
        },
        onVerticalDragEnd: (_) {
          // snap to closer wall on drag end
          // (horizontal position unchanged — stays on current wall)
        },
        onHorizontalDragEnd: (d) {
          setState(() {
            _onLeftWall = d.velocity.pixelsPerSecond.dx < 0;
          });
        },
        onTap: () {
          if (!_expanded) {
            setState(() => _expanded = true);
            _resetCollapseTimer();
          } else {
            _collapseTimer?.cancel();
            _openBugReport();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width:  _buttonSize,
          height: _buttonSize,
          decoration: BoxDecoration(
            color: Colors.red.withValues(alpha: 0.85),
            shape: BoxShape.circle,
            boxShadow: const [
              BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(-2, 2)),
            ],
          ),
          child: const Icon(Icons.bug_report_outlined, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    super.dispose();
  }
}

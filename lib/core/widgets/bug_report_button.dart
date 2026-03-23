import 'package:flutter/material.dart';

import '../../features/support/presentation/screens/bug_report_screen.dart';

class BugReportButton extends StatefulWidget {
  const BugReportButton({super.key});

  @override
  State<BugReportButton> createState() => _BugReportButtonState();
}

class _BugReportButtonState extends State<BugReportButton> {
  bool _isExpanded = false;

  void _openBugReport() {
    setState(() => _isExpanded = false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const BugReportScreen(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (!_isExpanded) {
          setState(() => _isExpanded = true);
        } else {
          _openBugReport();
        }
      },
      child: Transform.translate(
        offset: Offset(_isExpanded ? 0 : 28, 0),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          width: 56,
          height: 56,
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
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/theme_mode_provider.dart';
import '../utils/haptic_utils.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../router/app_router.dart';

/// Breakpoint for master-detail / rail: 600dp.
const double kAdaptiveBreakpoint = 600;

/// Adaptive shell: Bottom Nav on mobile (<600dp), Side Rail on tablet (>=600dp).
/// Wraps dashboard and provides navigation. Optional: Master-Detail for wide.
class AdaptiveShell extends ConsumerStatefulWidget {
  const AdaptiveShell({
    super.key,
    required this.child,
    this.currentPath = '/',
  });

  final Widget child;
  final String currentPath;

  @override
  ConsumerState<AdaptiveShell> createState() => _AdaptiveShellState();
}

class _AdaptiveShellState extends ConsumerState<AdaptiveShell> {
  int _selectedIndex = 0;

  @override
  void didUpdateWidget(AdaptiveShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPath.startsWith('/group/') && !widget.currentPath.contains('/expense/')) {
      _selectedIndex = 1;
    } else {
      _selectedIndex = 0;
    }
  }

  void _onTap(int index) {
    HapticUtils.selection();
    setState(() => _selectedIndex = index);
    if (index == 0) {
      context.go(AppRouter.dashboard);
    }
    if (index == 1) {
      context.go(AppRouter.dashboard);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= kAdaptiveBreakpoint;

    return Scaffold(
      body: Row(
        children: [
          if (useRail) _buildRail(context),
          Expanded(
            child: widget.child,
          ),
        ],
      ),
      bottomNavigationBar: useRail ? null : _buildBottomNav(context),
    );
  }

  Widget _buildRail(BuildContext context) {
    final theme = Theme.of(context);
    return NavigationRail(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _onTap,
      labelType: NavigationRailLabelType.all,
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: Text('Dashboard'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.group_outlined),
          selectedIcon: Icon(Icons.group),
          label: Text('Groups'),
        ),
      ],
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: _onTap,
      destinations: const [
        NavigationDestination(
          icon: Icon(Icons.dashboard_outlined),
          selectedIcon: Icon(Icons.dashboard),
          label: 'Dashboard',
        ),
        NavigationDestination(
          icon: Icon(Icons.group_outlined),
          selectedIcon: Icon(Icons.group),
          label: 'Groups',
        ),
      ],
    );
  }
}

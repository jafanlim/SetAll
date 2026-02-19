import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../utils/haptic_utils.dart';
import '../router/app_router.dart';

/// Breakpoint for master-detail / rail: 600dp.
const double kAdaptiveBreakpoint = 600;

/// Adaptive shell: Bottom Nav on mobile (<600dp), Side Rail on tablet (>=600dp).
/// Tabs: Dashboard (0), Friends (1), Groups (2 — navigates to dashboard).
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
    _selectedIndex = _indexForPath(widget.currentPath);
  }

  int _indexForPath(String path) {
    if (path.startsWith('/friends')) return 1;
    if (path.startsWith('/group/') && !path.contains('/expense/') && !path.contains('/invite')) {
      return 2;
    }
    return 0;
  }

  void _onTap(int index) {
    HapticUtils.selection();
    setState(() => _selectedIndex = index);
    switch (index) {
      case 0:
        context.go(AppRouter.dashboard);
      case 1:
        context.go(AppRouter.friends);
      case 2:
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
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: Text('Friends'),
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
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: 'Friends',
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

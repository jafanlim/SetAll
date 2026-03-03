import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../utils/haptic_utils.dart';
import '../router/app_router.dart';

/// Breakpoint for desktop navigation rail: 800dp.
const double kAdaptiveBreakpoint = 800;

/// Adaptive shell: Bottom Nav on mobile (<=800dp), Side Rail on desktop (>800dp).
/// Tabs: Dashboard (0), Friends (1), Groups (2), Settings (3 — desktop only).
/// Settings is accessed via the toolbar icon on the Dashboard on mobile.
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
    if (path.startsWith('/groups')) return 2;
    if (path.startsWith('/settings')) return 3;
    return 0;
  }

  void _onTap(int index) {
    HapticUtils.selection();
    switch (index) {
      case 0:
        setState(() => _selectedIndex = 0);
        context.go(AppRouter.dashboard);
      case 1:
        setState(() => _selectedIndex = 1);
        context.go(AppRouter.friends);
      case 2:
        setState(() => _selectedIndex = 2);
        context.go(AppRouter.groups);
      case 3:
        setState(() => _selectedIndex = 3);
        context.go(AppRouter.settings);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth > kAdaptiveBreakpoint;

        if (isDesktop) {
          return Scaffold(
            body: Row(
              children: [
                _buildRail(context),
                const VerticalDivider(thickness: 1, width: 1),
                Expanded(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 850),
                      child: widget.child,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Scaffold(
          body: widget.child,
          bottomNavigationBar: _buildBottomNav(context),
        );
      },
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
        NavigationRailDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: Text('Settings'),
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

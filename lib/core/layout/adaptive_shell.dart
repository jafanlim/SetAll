import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../utils/haptic_utils.dart';
import '../router/app_router.dart';
import '../providers/desktop_providers.dart';
import '../../features/dashboard/presentation/screens/group_detail_screen.dart';

/// Breakpoint: side rail replaces bottom nav (tablet / small desktop).
const double kAdaptiveBreakpoint = 600;

/// Breakpoint: full macOS-style sidebar with labels + settings at bottom.
const double kDesktopBreakpoint = 900;

/// Max width for content column on large screens so it stays readable.
const double kContentMaxWidth = 780;

/// Adaptive shell:
///   < 600dp  → BottomNavigationBar (mobile)
///  600–900dp → NavigationRail compact (tablet)
///  >= 900dp  → Full sidebar with text labels + Settings shortcut (macOS/desktop)
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
    return 0;
  }

  void _onTap(int index) {
    HapticUtils.selection();
    // Clear the detail pane when switching tabs on desktop.
    ref.read(selectedGroupProvider.notifier).clear();
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useDesktopSidebar = width >= kDesktopBreakpoint;
    final useRail = !useDesktopSidebar && width >= kAdaptiveBreakpoint;

    if (useDesktopSidebar) {
      return _buildDesktopLayout(context);
    }

    return Scaffold(
      body: Row(
        children: [
          if (useRail) _buildRail(context),
          Expanded(child: widget.child),
        ],
      ),
      bottomNavigationBar: !useRail ? _buildBottomNav(context) : null,
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    final selectedGroup = ref.watch(selectedGroupProvider);
    final hasDetail = selectedGroup.groupId != null;

    return Scaffold(
      body: Row(
        children: [
          _buildSidebar(context),
          // Master list — capped at kContentMaxWidth, never stretches wider
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
            child: SizedBox(
              width: hasDetail ? kContentMaxWidth : double.infinity,
              child: widget.child,
            ),
          ),
          // Detail pane — shown when a group is selected on desktop
          if (hasDetail) ...[
            VerticalDivider(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
            Expanded(
              child: GroupDetailScreen(
                key: ValueKey(selectedGroup.groupId),
                groupId: selectedGroup.groupId!,
                groupName: selectedGroup.groupName ?? 'Group',
              ),
            ),
          ] else
            const Expanded(child: _DetailPlaceholder()),
        ],
      ),
    );
  }

  // ── Full desktop sidebar ─────────────────────────────────────────────────
  Widget _buildSidebar(BuildContext context) {
    final theme = Theme.of(context);
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;

    const teal = Color(0xFF00D9B0);
    final bg = theme.colorScheme.surfaceContainerLow;
    final selectedBg = theme.colorScheme.primaryContainer.withValues(alpha: 0.45);
    final selectedFg = teal;
    final unselectedFg = theme.colorScheme.onSurfaceVariant;

    final items = [
      (icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard,       label: 'Dashboard', index: 0),
      (icon: Icons.people_outline,      selectedIcon: Icons.people,          label: 'Friends',   index: 1),
      (icon: Icons.group_outlined,      selectedIcon: Icons.group,           label: 'Groups',    index: 2),
    ];

    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          right: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Column(
        children: [
          // macOS traffic-light area spacer
          SizedBox(height: isMac ? 28 : 16),
          // App title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: teal.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.currency_exchange, size: 16, color: teal),
                ),
                const SizedBox(width: 10),
                Text(
                  'SetAll',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // Nav items
          ...items.map((item) {
            final isSelected = _selectedIndex == item.index;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _onTap(item.index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected ? selectedBg : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected ? item.selectedIcon : item.icon,
                          size: 18,
                          color: isSelected ? selectedFg : unselectedFg,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                            color: isSelected ? selectedFg : unselectedFg,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
          const Spacer(),
          // Settings at bottom
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () {
                  HapticUtils.primaryTap();
                  context.push(AppRouter.settings);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Row(
                    children: [
                      Icon(Icons.settings_outlined, size: 18, color: unselectedFg),
                      const SizedBox(width: 10),
                      Text(
                        'Settings',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: unselectedFg,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Compact navigation rail (tablet) ────────────────────────────────────
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

  // ── Bottom nav (mobile) ──────────────────────────────────────────────────
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

/// Shown in the detail pane on desktop when no group is selected yet.
class _DetailPlaceholder extends StatelessWidget {
  const _DetailPlaceholder();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.group_outlined,
            size: 48,
            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            'Select a group to view details',
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

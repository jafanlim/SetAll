import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../utils/haptic_utils.dart';
import '../router/app_router.dart';
import '../providers/desktop_providers.dart';

/// Breakpoint: side rail replaces bottom nav (tablet / small desktop).
const double kAdaptiveBreakpoint = 600;

/// Breakpoint: full macOS-style sidebar with labels + settings at bottom.
const double kDesktopBreakpoint = 900.0;

/// Max width for content column on large screens so it stays readable.
const double kContentMaxWidth = 850.0;

// ── Brand colours used by the desktop sidebar ────────────────────────────
const Color _kSidebarBg     = Color(0xFF0F172A);
const Color _kContentBg     = Color(0xFF020617);
const Color _kTeal          = Color(0xFF14B8A6);
const Color _kBorderColor   = Color(0x0DFFFFFF); // white @ 5 % opacity

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
    if (path.startsWith('/settings')) return 3;
    return 0;
  }

  void _onTap(int index) {
    HapticUtils.selection();
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
      case 3:
        setState(() => _selectedIndex = 3);
        context.go(AppRouter.settings);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final useDesktopSidebar = width >= kDesktopBreakpoint;
    final useRail = !useDesktopSidebar && width >= kAdaptiveBreakpoint;

    if (useDesktopSidebar) {
      return _DesktopLayout(
        selectedIndex: _selectedIndex,
        onTap: _onTap,
        child: widget.child,
      );
    }

    return _MobileLayout(
      selectedIndex: _selectedIndex,
      onTap: _onTap,
      useRail: useRail,
      child: widget.child,
    );
  }
}

// ── Desktop layout ────────────────────────────────────────────────────────

class _DesktopLayout extends ConsumerWidget {
  const _DesktopLayout({
    required this.selectedIndex,
    required this.onTap,
    required this.child,
  });

  final int selectedIndex;
  final void Function(int) onTap;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: _kContentBg,
      body: Row(
        children: [
          _PremiumSidebar(
            selectedIndex: selectedIndex,
            onTap: onTap,
          ),
          Expanded(
            child: Container(
              color: _kContentBg,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
                  child: child,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Premium sidebar ───────────────────────────────────────────────────────

class _PremiumSidebar extends StatelessWidget {
  const _PremiumSidebar({
    required this.selectedIndex,
    required this.onTap,
  });

  final int selectedIndex;
  final void Function(int) onTap;

  static const _navItems = [
    (icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Dashboard', index: 0),
    (icon: Icons.group_outlined,     selectedIcon: Icons.group,     label: 'Groups',    index: 2),
    (icon: Icons.people_outline,     selectedIcon: Icons.people,    label: 'Friends',   index: 1),
  ];

  @override
  Widget build(BuildContext context) {
    final isMac = defaultTargetPlatform == TargetPlatform.macOS;
    const unselectedFg = Color(0xFF94A3B8);

    return Container(
      width: 260,
      decoration: const BoxDecoration(
        color: _kSidebarBg,
        border: Border(
          right: BorderSide(color: _kBorderColor),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // macOS traffic-light area spacer
          SizedBox(height: isMac ? 28 : 20),

          // ── Brand header ─────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: _kTeal,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance_wallet_outlined, size: 20, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Flexible(
                  child: Text(
                    'SetAll',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                      color: Colors.white,
                      letterSpacing: -0.4,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Navigation items ─────────────────────────────────────────
          ..._navItems.map((item) {
            final isSelected = selectedIndex == item.index;
            return _SidebarNavItem(
              icon: item.icon,
              selectedIcon: item.selectedIcon,
              label: item.label,
              isSelected: isSelected,
              onTap: () => onTap(item.index),
            );
          }),

          const Spacer(),

          // ── Settings (pinned at bottom) ───────────────────────────────
          _SidebarNavItem(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            label: 'Settings',
            isSelected: selectedIndex == 3,
            onTap: () => onTap(3),
            unselectedColor: unselectedFg,
          ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ── Individual sidebar nav item with hover state ──────────────────────────

class _SidebarNavItem extends StatefulWidget {
  const _SidebarNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    this.unselectedColor,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final Color? unselectedColor;

  @override
  State<_SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<_SidebarNavItem> {
  bool _hovered = false;

  static const _tealHoverBg  = Color(0x1A14B8A6); // teal @ 10 % opacity
  static const _unselectedFg = Color(0xFF94A3B8);

  @override
  Widget build(BuildContext context) {
    final fg = widget.isSelected
        ? _kTeal
        : (widget.unselectedColor ?? _unselectedFg);

    Color bgColor = Colors.transparent;
    if (widget.isSelected) {
      bgColor = _tealHoverBg;
    } else if (_hovered) {
      bgColor = _tealHoverBg;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  widget.isSelected ? widget.selectedIcon : widget.icon,
                  size: 18,
                  color: fg,
                ),
                const SizedBox(width: 12),
                Text(
                  widget.label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: widget.isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Mobile layout (< 900 dp) ──────────────────────────────────────────────

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({
    required this.selectedIndex,
    required this.onTap,
    required this.useRail,
    required this.child,
  });

  final int selectedIndex;
  final void Function(int) onTap;
  final bool useRail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          if (useRail) _buildRail(context),
          Expanded(child: child),
        ],
      ),
      bottomNavigationBar: !useRail ? _buildBottomNav(context) : null,
    );
  }

  Widget _buildRail(BuildContext context) {
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onTap,
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
      selectedIndex: selectedIndex,
      onDestinationSelected: onTap,
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


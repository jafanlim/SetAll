import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:window_manager/window_manager.dart' if (dart.library.html) '../stubs/window_manager_stub.dart';

import '../utils/haptic_utils.dart';
import '../router/app_router.dart';
import '../providers/desktop_providers.dart';
import '../widgets/bug_report_button.dart';

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

  static const _langs = [
    (code: 'en', label: 'English'),
    (code: 'ru', label: 'Русский'),
    (code: 'ka', label: 'ქართული'),
    (code: 'de', label: 'Deutsch'),
    (code: 'es', label: 'Español'),
    (code: 'fr', label: 'Français'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkLangPrompt());
  }

  Future<void> _checkLangPrompt() async {
    if (!mounted) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('lang_prompt_shown') == true) return;
    await prefs.setBool('lang_prompt_shown', true);
    if (!mounted) return;
    final langCode = context.locale.languageCode;
    final langLabel = _langs
        .firstWhere((l) => l.code == langCode, orElse: () => _langs.first)
        .label;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _LangPromptSheet(
        langLabel: langLabel,
        langs: _langs,
        currentCode: langCode,
      ),
    );
  }

  @override
  void didUpdateWidget(AdaptiveShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selectedIndex = _indexForPath(widget.currentPath);
  }

  int _indexForPath(String path) {
    if (path.startsWith('/wallet'))    return 1;
    if (path.startsWith('/groups'))    return 2;
    if (path.startsWith('/activity'))  return 3;
    if (path.startsWith('/settings'))  return 4;
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
        context.go(AppRouter.wallet);
      case 2:
        setState(() => _selectedIndex = 2);
        context.go(AppRouter.groups);
      case 3:
        setState(() => _selectedIndex = 3);
        context.go(AppRouter.activity);
      case 4:
        setState(() => _selectedIndex = 4);
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
      body: Stack(
        fit: StackFit.expand,
        children: [
          Row(
            children: [
              _PremiumSidebar(
                selectedIndex: selectedIndex,
                onTap: onTap,
              ),
              Expanded(
                child: Container(
                  color: _kContentBg,
                  child: SafeArea(
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: kContentMaxWidth),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const BugReportButton(),
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
    (icon: Icons.dashboard_outlined,               selectedIcon: Icons.dashboard,               label: 'nav.dashboard', index: 0),
    (icon: Icons.account_balance_wallet_outlined,  selectedIcon: Icons.account_balance_wallet,  label: 'nav.wallet',    index: 1),
    (icon: Icons.group_outlined,                   selectedIcon: Icons.group,                   label: 'nav.groups',    index: 2),
    (icon: Icons.history,                          selectedIcon: Icons.history,                 label: 'nav.activity',  index: 3),
  ];

  @override
  Widget build(BuildContext context) {
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
          // ── Brand header (drag zone on macOS) ────────────────────────────
          DragToMoveArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  SvgPicture.asset(
                    'assets/icon_no_back.svg',
                    width: 32,
                    height: 32,
                    fit: BoxFit.contain,
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
          ),

          const SizedBox(height: 10),

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
            label: 'nav.settings',
            isSelected: selectedIndex == 4,
            onTap: () => onTap(4),
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
                  widget.label.tr(),
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
      body: SafeArea(
        bottom: false,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Row(
              children: [
                if (useRail) _buildRail(context),
                Expanded(child: child),
              ],
            ),
            const BugReportButton(),
          ],
        ),
      ),
      bottomNavigationBar: !useRail ? _buildBottomNav(context) : null,
    );
  }

  Widget _buildRail(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return NavigationRail(
      selectedIndex: selectedIndex,
      onDestinationSelected: onTap,
      labelType: NavigationRailLabelType.all,
      backgroundColor: isDark ? theme.colorScheme.surface : theme.colorScheme.surfaceContainerLow,
      selectedIconTheme: IconThemeData(color: isDark ? _kTeal : const Color(0xFF0D9488)),
      selectedLabelTextStyle: TextStyle(
        color: isDark ? _kTeal : const Color(0xFF0D9488),
        fontWeight: FontWeight.w700,
        fontSize: 11,
      ),
      unselectedIconTheme: IconThemeData(
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
      ),
      unselectedLabelTextStyle: TextStyle(
        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
        fontSize: 11,
      ),
      destinations: [
        NavigationRailDestination(
          icon: const Icon(Icons.dashboard_outlined),
          selectedIcon: const Icon(Icons.dashboard),
          label: Text('nav.dashboard'.tr()),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: const Icon(Icons.account_balance_wallet),
          label: Text('nav.wallet'.tr()),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.group_outlined),
          selectedIcon: const Icon(Icons.group),
          label: Text('nav.groups'.tr()),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.history),
          selectedIcon: const Icon(Icons.history),
          label: Text('nav.activity'.tr()),
        ),
        NavigationRailDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings),
          label: Text('nav.settings'.tr()),
        ),
      ],
    );
  }

  Widget _buildBottomNav(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onTap,
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.dashboard_outlined),
          selectedIcon: const Icon(Icons.dashboard),
          label: 'nav.dashboard'.tr(),
        ),
        NavigationDestination(
          icon: const Icon(Icons.account_balance_wallet_outlined),
          selectedIcon: const Icon(Icons.account_balance_wallet),
          label: 'nav.wallet'.tr(),
        ),
        NavigationDestination(
          icon: const Icon(Icons.group_outlined),
          selectedIcon: const Icon(Icons.group),
          label: 'nav.groups'.tr(),
        ),
        NavigationDestination(
          icon: const Icon(Icons.history),
          selectedIcon: const Icon(Icons.history),
          label: 'nav.activity'.tr(),
        ),
        NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings),
          label: 'nav.settings'.tr(),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// First-launch language confirmation sheet
// ---------------------------------------------------------------------------
class _LangPromptSheet extends StatelessWidget {
  const _LangPromptSheet({
    required this.langLabel,
    required this.langs,
    required this.currentCode,
  });

  final String langLabel;
  final List<({String code, String label})> langs;
  final String currentCode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Icon(Icons.language_outlined, color: _kTeal, size: 32),
            const SizedBox(height: 12),
            Text(
              'lang_prompt.title'.tr(),
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'lang_prompt.body'.tr(namedArgs: {'language': langLabel}),
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                style: FilledButton.styleFrom(
                  backgroundColor: _kTeal,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'lang_prompt.keep'.tr(namedArgs: {'language': langLabel}),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  _showLangPicker(context);
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kTeal,
                  side: const BorderSide(color: _kTeal),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  'lang_prompt.change'.tr(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLangPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Theme.of(ctx).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'settings.language'.tr(),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            ...langs.map((l) => ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              title: Text(l.label,
                  style: TextStyle(
                    fontWeight: l.code == currentCode
                        ? FontWeight.w700
                        : FontWeight.w500,
                  )),
              trailing: l.code == currentCode
                  ? const Icon(Icons.check_rounded, color: _kTeal, size: 20)
                  : null,
              onTap: () {
                ctx.setLocale(Locale(l.code));
                Navigator.of(ctx).pop();
              },
            )),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

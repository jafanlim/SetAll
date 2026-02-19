import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/layout/adaptive_shell.dart';
import '../../../../core/providers/setall_providers.dart';
import '../../../../core/providers/theme_mode_provider.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/group_model.dart';

class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  void _showThemeSelector() {
    HapticUtils.selection();
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final themeMode = ref.read(themeModeProvider);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Dark'),
                leading: Icon(Icons.dark_mode, color: themeMode == ThemeMode.dark ? Theme.of(ctx).colorScheme.primary : null),
                onTap: () {
                  ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
                  Navigator.pop(ctx);
                  HapticUtils.success();
                },
              ),
              ListTile(
                title: const Text('Light'),
                leading: Icon(Icons.light_mode, color: themeMode == ThemeMode.light ? Theme.of(ctx).colorScheme.primary : null),
                onTap: () {
                  ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);
                  Navigator.pop(ctx);
                  HapticUtils.success();
                },
              ),
              ListTile(
                title: const Text('System'),
                leading: Icon(Icons.brightness_auto, color: themeMode == ThemeMode.system ? Theme.of(ctx).colorScheme.primary : null),
                onTap: () {
                  ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system);
                  Navigator.pop(ctx);
                  HapticUtils.success();
                },
              ),
              const Divider(),
              ListTile(
                title: const Text('Sign out'),
                leading: const Icon(Icons.logout),
                onTap: () async {
                  Navigator.pop(ctx);
                  await Supabase.instance.client.auth.signOut();
                  if (ctx.mounted) context.go(AppRouter.login);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= kAdaptiveBreakpoint;

    final summaryAsync = ref.watch(balanceSummaryProvider);
    final groupsAsync = ref.watch(myGroupsProvider);
    final expensesAsync = ref.watch(recentExpensesProvider);

    final body = RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(balanceSummaryProvider);
        ref.invalidate(myGroupsProvider);
        ref.invalidate(recentExpensesProvider);
      },
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: GlassCard(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Global Net Balance',
                      style: theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    summaryAsync.when(
                      data: (summary) {
                        final owed = Decimal.tryParse(summary.youAreOwed) ?? Decimal.zero;
                        final owe = Decimal.tryParse(summary.youOwe) ?? Decimal.zero;
                        final net = owed - owe;
                        final isPositive = net >= Decimal.zero;
                        final display = isPositive ? net : -net;
                        return Text(
                          '${summary.currency} ${isPositive ? '' : '-'}${display.toStringAsFixed(2)}',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: isPositive ? const Color(0xFF4CAF50) : const Color(0xFFE57373),
                          ),
                        );
                      },
                      loading: () => const SizedBox(height: 24, child: Center(child: CircularProgressIndicator())),
                      error: (_, __) => Text('—', style: theme.textTheme.headlineMedium),
                    ),
                  ],
                ),
              ),
            ),
          ),
          summaryAsync.when(
            data: (summary) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Expanded(child: _MiniBalanceCard(label: 'You are owed', amount: summary.youAreOwed, currency: summary.currency, positive: true)),
                    const SizedBox(width: 12),
                    Expanded(child: _MiniBalanceCard(label: 'You owe', amount: summary.youOwe, currency: summary.currency, positive: false)),
                  ],
                ),
              ),
            ),
            loading: () => const SliverToBoxAdapter(child: SizedBox.shrink()),
            error: (_, __) => const SliverToBoxAdapter(child: SizedBox.shrink()),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Text(
                'Your groups',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          groupsAsync.when(
            data: (groups) => groups.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          'No groups yet. Create one when adding an expense.',
                          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final g = groups[index];
                        return _GroupCard(group: g);
                      },
                      childCount: groups.length,
                    ),
                  ),
            loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text('Could not load groups', style: TextStyle(color: theme.colorScheme.error))),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
              child: Text(
                'Activity',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          expensesAsync.when(
            data: (expenses) => expenses.isEmpty
                ? SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Text(
                        'No expenses yet. Tap Add expense to get started.',
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ),
                  )
                : SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final e = expenses[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          child: GlassCard(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            child: ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text(e.description.isEmpty ? 'Expense' : e.description),
                              subtitle: Text('${e.currency} ${e.amount}'),
                              trailing: Text(
                                '${e.currency} ${e.amount}',
                                style: theme.textTheme.titleSmall,
                              ),
                            ),
                          ),
                        );
                      },
                      childCount: expenses.length,
                    ),
                  ),
            loading: () => const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))),
            error: (e, _) => SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(child: Text('Could not load activity', style: TextStyle(color: theme.colorScheme.error))),
              ),
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text('SetAll'),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        actions: [
          IconButton(
            icon: const Icon(Icons.brightness_6_outlined),
            onPressed: _showThemeSelector,
            tooltip: 'Theme',
          ),
        ],
      ),
      body: useRail
          ? Row(
              children: [
                NavigationRail(
                  selectedIndex: 0,
                  onDestinationSelected: (_) {},
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: Text('Dashboard')),
                    NavigationRailDestination(icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group), label: Text('Groups')),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            )
          : body,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticUtils.primaryTap();
          context.push(AppRouter.groupPicker);
        },
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
    );
  }
}

class _MiniBalanceCard extends StatelessWidget {
  const _MiniBalanceCard({
    required this.label,
    required this.amount,
    required this.currency,
    required this.positive,
  });

  final String label;
  final String amount;
  final String currency;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            '$currency $amount',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: positive ? const Color(0xFF4CAF50) : const Color(0xFFE57373),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends ConsumerWidget {
  const _GroupCard({required this.group});

  final GroupModel group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final balanceAsync = ref.watch(groupBalanceSummaryProvider(group.id));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GlassCard(
        child: InkWell(
          onTap: () {
            HapticUtils.lightTap();
            context.push('/group/${group.id}', extra: {'groupName': group.name});
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      balanceAsync.when(
                        data: (s) => Text(
                          'Owed ${s.currency} ${s.youAreOwed} · Owe ${s.currency} ${s.youOwe}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                        loading: () => const SizedBox(height: 14),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

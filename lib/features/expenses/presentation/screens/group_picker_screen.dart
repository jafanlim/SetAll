import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../data/models/group_model.dart';
import '../../../../domain/entities/group.dart';

/// Choose an existing group or create a new one, then go to add expense.
class GroupPickerScreen extends ConsumerWidget {
  const GroupPickerScreen({super.key});

  void _openAddExpense(BuildContext context, GroupModel group) {
    context.pop();
    context.push(AppRouter.addExpense, extra: {
      'groupId': group.id,
      'groupName': group.name,
      if (group.defaultCurrency != null)
        'groupCurrency': group.defaultCurrency!,
    });
  }

  void _openCreateGroup(BuildContext context) {
    context.push(
      AppRouter.createGroup,
      // Callback: after group + members are created, jump straight to
      // add-expense (pop both CreateGroupScreen and this picker first).
      extra: (String groupId, String groupName) {
        context.pop(); // pop CreateGroupScreen
        context.pop(); // pop GroupPickerScreen
        context.push(AppRouter.addExpense,
            extra: {'groupId': groupId, 'groupName': groupName});
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(myGroupsProvider);
    final theme       = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('group_picker.title'.tr()),
        leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/');
              }
            }),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateGroup(context),
        icon: const Icon(Icons.group_add_outlined),
        label: Text('group_picker.new_group'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      ),
      body: groupsAsync.when(
        data: (groups) {
          final others = groups
              .where((g) => g.name != 'Personal' && g.type != GroupType.direct)
              .toList();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
            children: [
              // ── Existing groups ───────────────────────────────────────────────
              Text(
                'group_picker.choose_group'.tr(),
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              if (others.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                    'group_picker.no_groups'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              ...others.map((g) => Card(
                    child: ListTile(
                      leading: const Icon(Icons.group_outlined),
                      title: Text(g.name),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openAddExpense(context, g),
                    ),
                  )),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('group_picker.could_not_load'.tr(),
                    style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => ref.invalidate(myGroupsProvider),
                  child: Text('common.retry'.tr()),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../data/models/group_model.dart';
import '../../../../data/repositories/setall_repository.dart';

/// Choose an existing group or create a new one, then go to add expense.
class GroupPickerScreen extends ConsumerStatefulWidget {
  const GroupPickerScreen({super.key});

  @override
  ConsumerState<GroupPickerScreen> createState() => _GroupPickerScreenState();
}

class _GroupPickerScreenState extends ConsumerState<GroupPickerScreen> {
  final _nameController = TextEditingController();
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _openAddExpense(GroupModel group) {
    context.pop();
    context.push(AppRouter.addExpense, extra: {'groupId': group.id, 'groupName': group.name});
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a group name')));
      return;
    }
    setState(() => _isCreating = true);
    try {
      final repo = ref.read(setAllRepositoryProvider);
      final group = await repo.createGroup(name);
      if (mounted) {
        setState(() => _isCreating = false);
        if (group != null) {
          _nameController.clear();
          Navigator.of(context).pop(); // close dialog
          _openAddExpense(group);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create group')));
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        final msg = e.toString().replaceFirst(RegExp(r'^Exception: '), '');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create group: $msg')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(myGroupsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add expense'),
        leading: IconButton(icon: const Icon(Icons.close), onPressed: () => context.pop()),
      ),
      body: groupsAsync.when(
        data: (groups) {
          final personal = groups.where((g) => g.name == 'Personal').toList();
          final others = groups.where((g) => g.name != 'Personal').toList();
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Personal expense',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              if (personal.isNotEmpty)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.person),
                    title: const Text('Personal'),
                    subtitle: const Text('Just for you — no splitting'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _openAddExpense(personal.first),
                  ),
                )
              else
                const SizedBox.shrink(),
              const SizedBox(height: 20),
              Text(
                'Or choose a group',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ...others.map((g) => Card(
                child: ListTile(
                  title: Text(g.name),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _openAddExpense(g),
                ),
              )),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () {
                  showDialog<void>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('New group'),
                      content: TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Group name',
                          hintText: 'e.g. Trip to Paris',
                        ),
                        autofocus: true,
                        onSubmitted: (_) => _createGroup(),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: _isCreating ? null : _createGroup,
                          child: _isCreating
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Create'),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Create new group'),
              ),
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
                Text('Could not load groups', style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => ref.invalidate(myGroupsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

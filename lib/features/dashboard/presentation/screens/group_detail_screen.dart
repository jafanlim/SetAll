import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../data/models/expense_model.dart';
import '../../../../data/models/profile_model.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _addMember() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter an email')));
      return;
    }
    try {
      await ref.read(setAllRepositoryProvider).addMemberByEmail(
            widget.groupId,
            email,
            groupName: widget.groupName,
          );
      if (mounted) {
        _emailController.clear();
        ref.invalidate(groupMembersProvider(widget.groupId));
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Member added')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not add: $e')),
        );
      }
    }
  }

  void _showAddMemberDialog() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add member'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                hintText: 'friend@example.com',
              ),
              onSubmitted: (_) => _addMember(),
            ),
            const SizedBox(height: 12),
            Text(
              'They\'ll receive an email saying they were added to this group (if they have an account).',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              await _addMember();
              if (mounted) Navigator.of(ctx).pop();
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));
    final expensesAsync = ref.watch(groupExpensesProvider(widget.groupId));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.groupName),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: _showAddMemberDialog,
            tooltip: 'Add member',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(groupMembersProvider(widget.groupId));
          ref.invalidate(groupExpensesProvider(widget.groupId));
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _SectionTitle(title: 'Members'),
            const SizedBox(height: 8),
            membersAsync.when(
              data: (members) => _MemberList(members: members),
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
              error: (e, _) => Text('Could not load members', style: TextStyle(color: theme.colorScheme.error)),
            ),
            const SizedBox(height: 24),
            _SectionTitle(title: 'Expenses'),
            const SizedBox(height: 8),
            expensesAsync.when(
              data: (expenses) => _ExpenseList(
                expenses: expenses,
                groupId: widget.groupId,
                groupName: widget.groupName,
                onDeleted: () {
                  ref.invalidate(groupExpensesProvider(widget.groupId));
                  ref.invalidate(balanceSummaryProvider);
                  ref.invalidate(recentExpensesProvider);
                },
              ),
              loading: () => const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator())),
              error: (e, _) => Text('Could not load expenses', style: TextStyle(color: theme.colorScheme.error)),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(
          AppRouter.addExpense,
          extra: {'groupId': widget.groupId, 'groupName': widget.groupName},
        ),
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.onSurface,
      ),
    );
  }
}

class _MemberList extends StatelessWidget {
  const _MemberList({required this.members});

  final List<ProfileModel> members;

  @override
  Widget build(BuildContext context) {
    if (members.isEmpty) {
      return Text(
        'No members yet',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Card(
      child: Column(
        children: members.map((m) => ListTile(title: Text(m.name))).toList(),
      ),
    );
  }
}

class _ExpenseList extends StatelessWidget {
  const _ExpenseList({
    required this.expenses,
    required this.groupId,
    required this.groupName,
    required this.onDeleted,
  });

  final List<ExpenseModel> expenses;
  final String groupId;
  final String groupName;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return Text(
        'No expenses yet',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Card(
      child: Column(
        children: expenses.map((e) => _ExpenseTile(
          expense: e,
          groupId: groupId,
          groupName: groupName,
          onDeleted: onDeleted,
        )).toList(),
      ),
    );
  }
}

class _ExpenseTile extends ConsumerWidget {
  const _ExpenseTile({
    required this.expense,
    required this.groupId,
    required this.groupName,
    required this.onDeleted,
  });

  final ExpenseModel expense;
  final String groupId;
  final String groupName;
  final VoidCallback onDeleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: () => context.push(
        '/group/$groupId/expense/${expense.id}',
        extra: {'groupName': groupName},
      ),
      title: Text(expense.description.isEmpty ? 'Expense' : expense.description),
      subtitle: Text(
        '${expense.currency} ${expense.amount}${expense.category != 'General' ? ' · ${expense.category}' : ''}',
      ),
      trailing: PopupMenuButton<String>(
        icon: const Icon(Icons.more_vert),
        onSelected: (value) async {
          if (value == 'delete') {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Delete expense?'),
                content: Text(
                  'Remove "${expense.description.isEmpty ? expense.amount : expense.description}"? This cannot be undone.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.error,
                    ),
                    child: const Text('Delete'),
                  ),
                ],
              ),
            );
            if (confirm == true && context.mounted) {
              await ref.read(setAllRepositoryProvider).deleteExpense(expense.id);
              if (context.mounted) {
                onDeleted();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Expense deleted')),
                );
              }
            }
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}

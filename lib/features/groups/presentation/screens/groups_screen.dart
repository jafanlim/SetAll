import 'package:decimal/decimal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/utils/navigation_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../core/widgets/swipe_action_card.dart';
import '../../../../data/models/group_model.dart';

const _teal    = Color(0xFF00D9B0);
const _tealDim = Color(0x2600D9B0);
const _orange  = Color(0xFFFF8C42);

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme       = Theme.of(context);
    final groupsAsync = ref.watch(myGroupsProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Groups',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -0.3,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        automaticallyImplyLeading: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          HapticUtils.primaryTap();
          context.push(AppRouter.createGroup);
        },
        backgroundColor: _teal,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.group_add_outlined),
        label: const Text(
          'New group',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      body: RefreshIndicator(
        color: _teal,
        onRefresh: () async {
          HapticUtils.lightTap();
          ref.invalidate(myGroupsProvider);
        },
        child: groupsAsync.when(
          data: (groups) {
            if (groups.isEmpty) return const _EmptyGroupsView();
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
              itemCount: groups.length,
              itemBuilder: (_, i) => _GroupCard(group: groups[i]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load groups',
                style: TextStyle(color: theme.colorScheme.error, fontSize: 14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------
class _EmptyGroupsView extends StatelessWidget {
  const _EmptyGroupsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.group_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'No groups yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Create a group to split expenses with multiple people.',
              style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Group card — swipe to edit/delete, long-press context menu, right-click menu
// ---------------------------------------------------------------------------
class _GroupCard extends ConsumerStatefulWidget {
  const _GroupCard({required this.group});
  final GroupModel group;

  @override
  ConsumerState<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends ConsumerState<_GroupCard> {
  Future<void> _rename() async {
    HapticUtils.primaryTap();
    final ctrl = TextEditingController(text: widget.group.name);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename group'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'Group name'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final newName = ctrl.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (confirmed != true || newName.isEmpty || newName == widget.group.name) return;
    final ok = await ref.read(setAllRepositoryProvider).renameGroup(widget.group.id, newName);
    if (!mounted) return;
    if (ok) {
      ref.invalidate(myGroupsProvider);
      HapticUtils.success();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not rename. Only the group creator can rename.')),
      );
    }
  }

  Future<void> _delete() async {
    HapticUtils.primaryTap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete group?'),
        content: Text('Delete "${widget.group.name}" and all its expenses?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final doubleConfirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text('This action is irreversible. All expenses and balances in this group will be permanently deleted.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, delete forever'),
          ),
        ],
      ),
    );
    if (doubleConfirmed != true || !mounted) return;
    final ok = await ref.read(setAllRepositoryProvider).deleteGroup(widget.group.id);
    if (!mounted) return;
    if (ok) {
      ref.invalidate(myGroupsProvider);
      ref.invalidate(balanceSummaryProvider);
      ref.invalidate(recentExpensesProvider);
      HapticUtils.success();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete group.')),
      );
    }
  }

  Future<void> _showContextMenu(BuildContext context) async {
    HapticUtils.primaryTap();
    final result = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined, color: _teal),
              title: const Text('Rename group'),
              onTap: () => Navigator.of(ctx).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('Delete group', style: TextStyle(color: Colors.redAccent)),
              onTap: () => Navigator.of(ctx).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (result == 'rename') _rename();
    if (result == 'delete') _delete();
  }

  Future<void> _showRightClickMenu(BuildContext context, Offset position) async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
          position.dx, position.dy, position.dx + 1, position.dy + 1),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: Row(children: [
            const Icon(Icons.edit_outlined, size: 16, color: _teal),
            const SizedBox(width: 8),
            const Text('Rename group'),
          ]),
        ),
        const PopupMenuItem(
          value: 'delete',
          child: Row(children: [
            Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Delete group', style: TextStyle(color: Colors.redAccent)),
          ]),
        ),
      ],
    );
    if (result == 'rename') _rename();
    if (result == 'delete') _delete();
  }

  @override
  Widget build(BuildContext context) {
    final theme        = Theme.of(context);
    final membersAsync = ref.watch(groupMembersProvider(widget.group.id));
    final balanceAsync = ref.watch(groupBalanceSummaryProvider(widget.group.id));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: SwipeActionCard(
        actionsPanelWidth: 140,
        actions: [
          SwipeAction(icon: Icons.edit_outlined,  label: 'Edit',   color: _teal,             onTap: _rename),
          SwipeAction(icon: Icons.delete_outline, label: 'Delete', color: Colors.redAccent,  onTap: _delete),
        ],
        child: GestureDetector(
          onLongPress: () => _showContextMenu(context),
          onSecondaryTapUp: defaultTargetPlatform == TargetPlatform.macOS
              ? (d) => _showRightClickMenu(context, d.globalPosition)
              : null,
          child: GlassCard(
            child: InkWell(
              onTap: () {
                HapticUtils.lightTap();
                navigateToGroup(
                  context: context,
                  ref: ref,
                  groupId: widget.group.id,
                  groupName: widget.group.name,
                );
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // ── Group avatar ────────────────────────────────────────
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: _tealDim,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          widget.group.name.isNotEmpty ? widget.group.name[0].toUpperCase() : 'G',
                          style: const TextStyle(
                            color: _teal,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // ── Group info ──────────────────────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.group.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          membersAsync.when(
                            data: (members) => Text(
                              '${members.length} member${members.length == 1 ? '' : 's'}',
                              style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                            ),
                            loading: () => const SizedBox(height: 11),
                            error: (_, _) => const SizedBox.shrink(),
                          ),
                          const SizedBox(height: 4),
                          balanceAsync.when(
                            data: (s) {
                              final owed = Decimal.tryParse(s.youAreOwed) ?? Decimal.zero;
                              final owe  = Decimal.tryParse(s.youOwe)     ?? Decimal.zero;
                              if (owed == Decimal.zero && owe == Decimal.zero) {
                                return Text(
                                  'Settled up',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: _teal,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                );
                              }
                              return RichText(
                                text: TextSpan(
                                  style: const TextStyle(fontSize: 11),
                                  children: [
                                    if (owed > Decimal.zero)
                                      TextSpan(
                                        text: '+${s.currency} ${s.youAreOwed}',
                                        style: const TextStyle(color: _teal, fontWeight: FontWeight.w600),
                                      ),
                                    if (owed > Decimal.zero && owe > Decimal.zero)
                                      const TextSpan(text: '  '),
                                    if (owe > Decimal.zero)
                                      TextSpan(
                                        text: '-${s.currency} ${s.youOwe}',
                                        style: const TextStyle(color: _orange, fontWeight: FontWeight.w600),
                                      ),
                                  ],
                                ),
                              );
                            },
                            loading: () => const SizedBox(height: 11),
                            error: (_, _) => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),

                    // ── Quick invite icon ────────────────────────────────────
                    SizedBox(
                      width: 36,
                      height: 36,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: Icon(
                          Icons.person_add_outlined,
                          size: 18,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        onPressed: () {
                          HapticUtils.lightTap();
                          context.push(
                            '/group/${widget.group.id}/invite',
                            extra: {'groupName': widget.group.name},
                          );
                        },
                        tooltip: 'Add member',
                      ),
                    ),

                    const Icon(Icons.chevron_right, color: Colors.white38, size: 20),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

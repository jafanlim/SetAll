import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/group_model.dart';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const _teal        = Color(0xFF00D9B0);
const _orange      = Color(0xFFFF8C42);
const _brandOrange = Color(0xFFF97316);
// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
const _kStorageBase =
    'https://vrsmsgyxeyzyrdonsnrk.supabase.co/storage/v1/object/public/group-avatars/';

String? _resolveAvatarUrl(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  if (raw.startsWith('http')) return raw;
  return '$_kStorageBase$raw';
}

// ---------------------------------------------------------------------------
// Icon map (mirrors create_group_screen)
// ---------------------------------------------------------------------------
const Map<String, IconData> _kGroupIcons = {
  'groups':     Icons.groups_outlined,
  'home':       Icons.home_outlined,
  'flight':     Icons.flight_outlined,
  'hotel':      Icons.hotel_outlined,
  'restaurant': Icons.restaurant_outlined,
  'shopping':   Icons.shopping_bag_outlined,
  'sports':     Icons.sports_soccer_outlined,
  'music':      Icons.music_note_outlined,
  'school':     Icons.school_outlined,
  'work':       Icons.work_outline,
  'car':        Icons.directions_car_outlined,
  'beach':      Icons.beach_access_outlined,
  'party':      Icons.celebration_outlined,
  'health':     Icons.favorite_outline,
  'coffee':     Icons.local_cafe_outlined,
};

/// Info / overview screen for a single group.
/// Shows identity card, balance summary, members, and action buttons.
/// Mirrors the pattern of [WalletEntryDetailScreen] and [GroupExpenseDetailScreen].
class GroupInfoScreen extends ConsumerStatefulWidget {
  const GroupInfoScreen({super.key, required this.group});

  final GroupModel group;

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  bool _deleting = false;

  GroupModel get group => widget.group;

  // ── Delete ────────────────────────────────────────────────────────────────
  Future<void> _delete({bool force = false}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(force ? 'Force delete group?' : 'Delete group?'),
        content: Text(
          force
              ? 'Force-delete "${group.name}"? This will also purge all its expenses from the server.'
              : 'Delete "${group.name}"? You can restore it from the Activity screen within 12 months.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: force ? _brandOrange : Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(force ? 'Force Delete' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _deleting = true);
    final repo = ref.read(setAllRepositoryProvider);
    final ok = force
        ? await repo.forceDeleteGroup(group.id)
        : await repo.deleteGroup(group.id);
    if (!mounted) return;
    setState(() => _deleting = false);
    if (ok) {
      ref.invalidate(myGroupsProvider);
      ref.invalidate(balanceSummaryProvider);
      ref.invalidate(recentExpensesProvider);
      ref.invalidate(omniActivityProvider);
      HapticUtils.success();
      // Pop back to groups list
      if (context.canPop()) context.pop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not delete. Try Force Delete from the … menu.'),
        ),
      );
    }
  }

  // ── Rename ────────────────────────────────────────────────────────────────
  Future<void> _rename() async {
    HapticUtils.primaryTap();
    final ctrl = TextEditingController(text: group.name);
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: _teal, foregroundColor: Colors.black),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    final newName = ctrl.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (confirmed != true || newName.isEmpty || newName == group.name) return;
    final ok = await ref
        .read(setAllRepositoryProvider)
        .renameGroup(group.id, newName);
    if (!mounted) return;
    if (ok) {
      ref.invalidate(myGroupsProvider);
      HapticUtils.success();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not rename. Only the group creator can rename.'),
        ),
      );
    }
  }

  // ── Overflow menu ─────────────────────────────────────────────────────────
  Future<void> _showOverflowMenu() async {
    final result = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        MediaQuery.sizeOf(context).width - 48, 64, 0, 0),
      items: [
        PopupMenuItem(
          value: 'rename',
          child: Row(children: const [
            Icon(Icons.edit_outlined, size: 16, color: _teal),
            SizedBox(width: 8),
            Text('Rename group'),
          ]),
        ),
        const PopupMenuItem(
          value: 'invite',
          child: Row(children: [
            Icon(Icons.person_add_outlined, size: 16, color: _teal),
            SizedBox(width: 8),
            Text('Add member'),
          ]),
        ),
        const PopupMenuItem(
          value: 'force_delete',
          child: Row(children: [
            Icon(Icons.delete_forever_outlined, size: 16, color: _brandOrange),
            SizedBox(width: 8),
            Text('Force Delete',
                style: TextStyle(color: _brandOrange)),
          ]),
        ),
      ],
    );
    if (!mounted) return;
    if (result == 'rename') _rename();
    if (result == 'invite') {
      context.push('/group/${group.id}/invite',
          extra: {'groupName': group.name});
    }
    if (result == 'force_delete') _delete(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme        = Theme.of(context);
    final membersAsync = ref.watch(groupMembersProvider(group.id));
    final balanceAsync = ref.watch(groupBalanceSummaryProvider(group.id));

    final accentColor = group.colorValue != null
        ? Color(group.colorValue!)
        : _teal;
    final bgColor     = accentColor.withValues(alpha: 0.12);

    return Stack(
      children: [
        Scaffold(
          backgroundColor: theme.colorScheme.surface,
          appBar: AppBar(
            title: Text(
              group.name,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            backgroundColor: theme.colorScheme.surface,
            elevation: 0,
            scrolledUnderElevation: 0.5,
            actions: [
              IconButton(
                icon: const Icon(Icons.more_vert),
                onPressed: _showOverflowMenu,
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            children: [

              // ── Identity hero card ─────────────────────────────────────
              GlassCard(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    // Avatar / icon
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: bgColor,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: _resolveAvatarUrl(group.avatarUrl) != null
                            ? Image.network(
                                _resolveAvatarUrl(group.avatarUrl)!,
                                width: 64,
                                height: 64,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Center(
                                  child: Icon(Icons.groups_outlined, size: 30, color: accentColor),
                                ),
                              )
                            : Center(
                                child: group.iconName != null
                                    ? Icon(
                                        _kGroupIcons[group.iconName] ??
                                            Icons.groups_outlined,
                                        size: 30,
                                        color: accentColor,
                                      )
                                    : Text(
                                        group.name.isNotEmpty
                                            ? group.name[0].toUpperCase()
                                            : 'G',
                                        style: TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w800,
                                          color: accentColor,
                                        ),
                                      ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.name,
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: 20,
                              letterSpacing: -0.3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          membersAsync.when(
                            data: (members) => Text(
                              '${members.length} member${members.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            loading: () => const SizedBox(height: 13),
                            error: (_, _) => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Balance summary card ───────────────────────────────────
              balanceAsync.when(
                data: (s) {
                  final owed = Decimal.tryParse(s.youAreOwed) ?? Decimal.zero;
                  final owe  = Decimal.tryParse(s.youOwe)     ?? Decimal.zero;
                  final settled = owed == Decimal.zero && owe == Decimal.zero;
                  return GlassCard(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Balance',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (settled)
                          Row(children: [
                            Icon(Icons.check_circle_outline,
                                size: 18, color: _teal),
                            const SizedBox(width: 6),
                            Text(
                              'All settled up',
                              style: const TextStyle(
                                  color: _teal,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14),
                            ),
                          ])
                        else
                          Row(
                            children: [
                              if (owed > Decimal.zero) ...[
                                _BalancePill(
                                  label: 'Owed to you',
                                  amount: '${s.currency} ${s.youAreOwed}',
                                  positive: true,
                                ),
                                const SizedBox(width: 10),
                              ],
                              if (owe > Decimal.zero)
                                _BalancePill(
                                  label: 'You owe',
                                  amount: '${s.currency} ${s.youOwe}',
                                  positive: false,
                                ),
                            ],
                          ),
                      ],
                    ),
                  );
                },
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 12),

              // ── Members card ───────────────────────────────────────────
              membersAsync.when(
                data: (members) => members.isEmpty
                    ? const SizedBox.shrink()
                    : GlassCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Members (${members.length})',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 0.5,
                                    color:
                                        theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                TextButton.icon(
                                  onPressed: () => context.push(
                                    '/group/${group.id}/invite',
                                    extra: {'groupName': group.name},
                                  ),
                                  icon: const Icon(
                                      Icons.person_add_outlined,
                                      size: 14),
                                  label: const Text('Add',
                                      style: TextStyle(fontSize: 11)),
                                  style: TextButton.styleFrom(
                                    foregroundColor: _teal,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    minimumSize: Size.zero,
                                    tapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: members.map((m) {
                                final initial = (m.name.isNotEmpty)
                                    ? m.name[0].toUpperCase()
                                    : '?';
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 40,
                                      decoration: BoxDecoration(
                                        color: accentColor
                                            .withValues(alpha: 0.15),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Center(
                                        child: Text(
                                          initial,
                                          style: TextStyle(
                                            color: accentColor,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    SizedBox(
                                      width: 48,
                                      child: Text(
                                        m.name.split(' ').first,
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: theme.colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      ),
                loading: () => const SizedBox.shrink(),
                error: (_, _) => const SizedBox.shrink(),
              ),
              const SizedBox(height: 24),

              // ── Primary action — open full group hub ───────────────────
              FilledButton.icon(
                onPressed: () => context.push(
                  '/group/${group.id}',
                  extra: {'groupName': group.name},
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: const Icon(Icons.receipt_long_outlined),
                label: const Text(
                  'View Expenses & Balances',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ),
              const SizedBox(height: 10),

              // ── Secondary actions row ──────────────────────────
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push(
                        '/group/${group.id}/edit',
                        extra: group,
                      ),
                      icon: const Icon(Icons.palette_outlined, size: 16),
                      label: const Text('Edit',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _teal,
                        side: const BorderSide(color: _teal, width: 1),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _rename,
                      icon: const Icon(Icons.edit_outlined, size: 16),
                      label: const Text('Rename',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _teal,
                        side: const BorderSide(color: _teal, width: 1),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _delete(),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Delete',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(
                            color: Colors.redAccent, width: 1),
                        padding:
                            const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_deleting)
          const Positioned.fill(
            child: ColoredBox(
              color: Color(0x66000000),
              child: Center(child: CircularProgressIndicator()),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Balance pill widget
// ---------------------------------------------------------------------------
class _BalancePill extends StatelessWidget {
  const _BalancePill({
    required this.label,
    required this.amount,
    required this.positive,
  });

  final String label;
  final String amount;
  final bool   positive;

  @override
  Widget build(BuildContext context) {
    final color = positive ? _teal : _orange;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            amount,
            style: TextStyle(
              fontSize: 15,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

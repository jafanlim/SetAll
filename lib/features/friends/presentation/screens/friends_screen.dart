import 'dart:async';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/utils/navigation_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/group_model.dart';
import '../../../../data/models/profile_model.dart';
import '../../../../data/repositories/setall_repository.dart';

// ---------------------------------------------------------------------------
// Fintech colour palette (matches dashboard)
// ---------------------------------------------------------------------------
const _teal = Color(0xFF00D9B0);
const _orange = Color(0xFFFF8C42);
const _tealDim = Color(0x2600D9B0);

class FriendsScreen extends ConsumerStatefulWidget {
  const FriendsScreen({super.key});

  @override
  ConsumerState<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends ConsumerState<FriendsScreen> {
  void _showAddFriend() {
    HapticUtils.primaryTap();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _AddFriendSearchSheet(
        onAdded: () {
          ref.invalidate(friendGroupsProvider);
          HapticUtils.success();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final friendsAsync = ref.watch(friendGroupsProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Friends',
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
        onPressed: _showAddFriend,
        backgroundColor: _teal,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.person_add_outlined),
        label: const Text(
          'Add friend',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      body: RefreshIndicator(
        color: _teal,
        onRefresh: () async {
          HapticUtils.lightTap();
          ref.invalidate(friendGroupsProvider);
        },
        child: friendsAsync.when(
          data: (friends) {
            if (friends.isEmpty) {
              return _EmptyFriendsView(onAdd: _showAddFriend);
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
              itemCount: friends.length,
              itemBuilder: (_, i) => _FriendCard(group: friends[i]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load friends',
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 14,
                ),
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
class _EmptyFriendsView extends StatelessWidget {
  const _EmptyFriendsView({required this.onAdd});
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No friends yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add a friend by email to track 1-on-1 expenses.',
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('Add friend'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Friend card
// ---------------------------------------------------------------------------
class _FriendCard extends ConsumerWidget {
  const _FriendCard({required this.group});
  final GroupModel group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final balanceAsync = ref.watch(groupBalanceSummaryProvider(group.id));
    final membersAsync = ref.watch(groupMembersProvider(group.id));
    final currentUid = ref.watch(currentUserIdProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GlassCard(
        child: InkWell(
          onTap: () {
            HapticUtils.lightTap();
            // Derive display name from members
            String friendName = 'Friend';
            if (membersAsync.hasValue) {
              final others = membersAsync.value!
                  .where((m) => m.id != currentUid)
                  .toList();
              if (others.isNotEmpty) friendName = others.first.name;
            }
            navigateToGroup(context: context, ref: ref, groupId: group.id, groupName: friendName);
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _FriendAvatar(membersAsync: membersAsync, currentUid: currentUid),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FriendName(
                        membersAsync: membersAsync,
                        currentUid: currentUid,
                        theme: theme,
                      ),
                      const SizedBox(height: 4),
                      balanceAsync.when(
                        skipLoadingOnReload: true,
                        data: (s) => _BalanceSubtitle(summary: s),
                        loading: () => const SizedBox(height: 12),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: Colors.white38,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FriendAvatar extends StatelessWidget {
  const _FriendAvatar({required this.membersAsync, required this.currentUid});
  final AsyncValue<List<ProfileModel>> membersAsync;
  final String? currentUid;

  @override
  Widget build(BuildContext context) {
    String initial = '?';
    if (membersAsync.hasValue) {
      final others =
          membersAsync.value!.where((m) => m.id != currentUid).toList();
      if (others.isNotEmpty && others.first.name.isNotEmpty) {
        initial = others.first.name[0].toUpperCase();
      }
    }
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: _tealDim,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: _teal,
            fontWeight: FontWeight.w800,
            fontSize: 16,
          ),
        ),
      ),
    );
  }
}

class _FriendName extends StatelessWidget {
  const _FriendName({
    required this.membersAsync,
    required this.currentUid,
    required this.theme,
  });
  final AsyncValue<List<ProfileModel>> membersAsync;
  final String? currentUid;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    if (membersAsync.isLoading) {
      return const SizedBox(
        height: 14,
        width: 100,
        child: LinearProgressIndicator(),
      );
    }
    String name = 'Friend';
    if (membersAsync.hasValue) {
      final others =
          membersAsync.value!.where((m) => m.id != currentUid).toList();
      if (others.isNotEmpty) name = others.first.name;
    }
    return Text(
      name,
      style: theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 14,
      ),
    );
  }
}

class _BalanceSubtitle extends StatelessWidget {
  const _BalanceSubtitle({required this.summary});
  final BalanceSummary summary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owed = Decimal.tryParse(summary.youAreOwed) ?? Decimal.zero;
    final owe = Decimal.tryParse(summary.youOwe) ?? Decimal.zero;

    if (owed == Decimal.zero && owe == Decimal.zero) {
      return Text(
        'Settled up',
        style: theme.textTheme.bodySmall?.copyWith(
          color: _teal,
          fontSize: 11,
        ),
      );
    }

    final parts = <TextSpan>[];
    if (owed > Decimal.zero) {
      parts.add(TextSpan(
        text: '+${summary.currency} ${summary.youAreOwed}',
        style: const TextStyle(color: _teal, fontWeight: FontWeight.w600),
      ));
    }
    if (owed > Decimal.zero && owe > Decimal.zero) {
      parts.add(const TextSpan(text: '  '));
    }
    if (owe > Decimal.zero) {
      parts.add(TextSpan(
        text: '-${summary.currency} ${summary.youOwe}',
        style: const TextStyle(color: _orange, fontWeight: FontWeight.w600),
      ));
    }

    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 11),
        children: parts,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add friend — search-based bottom sheet
// ---------------------------------------------------------------------------
class _AddFriendSearchSheet extends ConsumerStatefulWidget {
  const _AddFriendSearchSheet({required this.onAdded});
  final VoidCallback onAdded;

  @override
  ConsumerState<_AddFriendSearchSheet> createState() =>
      _AddFriendSearchSheetState();
}

class _AddFriendSearchSheetState
    extends ConsumerState<_AddFriendSearchSheet> {
  final _ctrl     = TextEditingController();
  Timer?  _debounce;
  String  _query  = '';
  bool    _adding = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  Future<void> _addFriend(ProfileModel profile) async {
    setState(() { _adding = true; _error = null; _success = null; });
    HapticUtils.primaryTap();
    try {
      final group = await ref
          .read(setAllRepositoryProvider)
          .createDirectGroupById(profile.id);
      if (!mounted) return;
      if (group != null) {
        HapticUtils.success();
        setState(() {
          _success = '${profile.name} added as a friend!';
          _adding  = false;
        });
        await Future.delayed(const Duration(milliseconds: 800));
        if (mounted) {
          widget.onAdded();
          Navigator.pop(context);
        }
      } else {
        setState(() {
          _error  = 'Could not create friendship. Try again.';
          _adding = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error  = e.toString().contains('cannot_add_self')
            ? 'You cannot add yourself as a friend.'
            : 'Something went wrong. Check your connection.';
        _adding = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final searchAsync = ref.watch(searchUsersProvider(_query));

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add a Friend',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          'Search by name, @nickname or email',
                          style: TextStyle(
                            fontSize: 12,
                            color: _teal,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 8),

            // Search field
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                onChanged: _onQueryChanged,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'Search by name, @nickname or email…',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _ctrl.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18),
                          onPressed: () {
                            _ctrl.clear();
                            setState(() => _query = '');
                          },
                        )
                      : null,
                ),
              ),
            ),
            const SizedBox(height: 8),

            // Feedback
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: GlassCard(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline,
                          color: theme.colorScheme.error, size: 15),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                              color: theme.colorScheme.error, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (_success != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: GlassCard(
                  padding: const EdgeInsets.all(10),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_outline,
                          color: _teal, size: 15),
                      const SizedBox(width: 8),
                      Text(
                        _success!,
                        style: const TextStyle(color: _teal, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),

            // Results
            Flexible(
              child: _query.length < 2
                  ? Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 24),
                      child: Center(
                        child: Text(
                          'Type at least 2 characters to search for friends.',
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : searchAsync.when(
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (_, _) => Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            'Search unavailable. Check your connection.',
                            style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ),
                      ),
                      data: (results) => results.isEmpty
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Text(
                                  'No users found for "$_query".',
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: theme.colorScheme.onSurfaceVariant),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              children: results
                                  .map((p) => _FriendResultTile(
                                        profile: p,
                                        adding:  _adding,
                                        onAdd:   () => _addFriend(p),
                                      ))
                                  .toList(),
                            ),
                    ),
            ),

            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Friend result tile (mirrors _UserResultTile from add_person_modal)
// ---------------------------------------------------------------------------
class _FriendResultTile extends StatelessWidget {
  const _FriendResultTile({
    required this.profile,
    required this.adding,
    required this.onAdd,
  });

  final ProfileModel profile;
  final bool         adding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final initial = profile.name.isNotEmpty
        ? profile.name[0].toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: ListTile(
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_teal, Color(0xFF00A896)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
            ),
          ),
          title: Text(
            profile.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          subtitle: profile.nickname != null
              ? Text(
                  '@${profile.nickname}',
                  style: const TextStyle(fontSize: 11, color: _teal),
                )
              : null,
          trailing: adding
              ? const SizedBox(
                  height: 20,
                  width:  20,
                  child:  CircularProgressIndicator(strokeWidth: 2),
                )
              : FilledButton(
                  onPressed: onAdd,
                  style: FilledButton.styleFrom(
                    backgroundColor: _teal,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700),
                    minimumSize: const Size(0, 0),
                  ),
                  child: const Text('Add'),
                ),
        ),
      ),
    );
  }
}

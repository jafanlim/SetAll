import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
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
      builder: (_) => _AddFriendSheet(
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
        title: Text(
          'Friends',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20.sp,
            letterSpacing: -0.3,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddFriend,
        backgroundColor: _teal,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.person_add_outlined),
        label: Text(
          'Add friend',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp),
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
              padding: EdgeInsets.fromLTRB(0, 8.h, 0, 96.h),
              itemCount: friends.length,
              itemBuilder: (_, i) => _FriendCard(group: friends[i]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: EdgeInsets.all(24.w),
              child: Text(
                'Could not load friends',
                style: TextStyle(
                  color: theme.colorScheme.error,
                  fontSize: 14.sp,
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
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline,
              size: 64.sp,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            SizedBox(height: 16.h),
            Text(
              'No friends yet',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Add a friend by email to track 1-on-1 expenses.',
              style: TextStyle(
                fontSize: 13.sp,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24.h),
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
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
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
            context.push(
              '/group/${group.id}',
              extra: {'groupName': friendName},
            );
          },
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                _FriendAvatar(membersAsync: membersAsync, currentUid: currentUid),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _FriendName(
                        membersAsync: membersAsync,
                        currentUid: currentUid,
                        theme: theme,
                      ),
                      SizedBox(height: 4.h),
                      balanceAsync.when(
                        data: (s) => _BalanceSubtitle(summary: s),
                        loading: () => SizedBox(height: 12.h),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 20.sp,
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
      width: 44.w,
      height: 44.w,
      decoration: BoxDecoration(
        color: _tealDim,
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: _teal,
            fontWeight: FontWeight.w800,
            fontSize: 18.sp,
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
      return SizedBox(
        height: 14.h,
        width: 100.w,
        child: const LinearProgressIndicator(),
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
        fontSize: 14.sp,
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
          fontSize: 11.sp,
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
        style: TextStyle(fontSize: 11.sp),
        children: parts,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Add friend bottom sheet
// ---------------------------------------------------------------------------
class _AddFriendSheet extends ConsumerStatefulWidget {
  const _AddFriendSheet({required this.onAdded});
  final VoidCallback onAdded;

  @override
  ConsumerState<_AddFriendSheet> createState() => _AddFriendSheetState();
}

class _AddFriendSheetState extends ConsumerState<_AddFriendSheet> {
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _emailCtrl.text.trim();
    if (email.isEmpty) {
      setState(() => _error = 'Enter an email address');
      return;
    }
    setState(() { _loading = true; _error = null; });
    try {
      final repo = ref.read(setAllRepositoryProvider);
      final group = await repo.createDirectGroup(email);
      if (!mounted) return;
      if (group != null) {
        widget.onAdded();
        Navigator.pop(context);
      } else {
        setState(() => _error = 'Could not create friendship. Try again.');
      }
    } on DirectGroupUserNotFoundException {
      if (mounted) {
        setState(() => _error = 'No SetAll account found for that email.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Check your connection.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: 16.w,
        right: 16.w,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24.h,
        top: 8.h,
      ),
      child: GlassCard(
        padding: EdgeInsets.all(20.w),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36.w,
                height: 4.h,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2.r),
                ),
              ),
            ),
            SizedBox(height: 16.h),
            Text(
              'Add a friend',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 4.h),
            Text(
              'Enter their email to start splitting 1-on-1 expenses.',
              style: TextStyle(
                fontSize: 12.sp,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            SizedBox(height: 16.h),
            TextField(
              controller: _emailCtrl,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'friend@example.com',
                prefixIcon: const Icon(Icons.email_outlined),
                errorText: _error,
              ),
            ),
            SizedBox(height: 16.h),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? SizedBox(
                        height: 18.h,
                        width: 18.w,
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        'Add friend',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.sp,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

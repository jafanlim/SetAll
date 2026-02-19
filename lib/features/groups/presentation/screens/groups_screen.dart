import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/group_model.dart';

const _teal    = Color(0xFF00D9B0);
const _tealDim = Color(0x2600D9B0);
const _orange  = Color(0xFFFF8C42);

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme      = Theme.of(context);
    final groupsAsync = ref.watch(myGroupsProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Groups',
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
        onPressed: () {
          HapticUtils.primaryTap();
          context.push(AppRouter.createGroup);
        },
        backgroundColor: _teal,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.group_add_outlined),
        label: Text(
          'New group',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp),
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
            if (groups.isEmpty) return _EmptyGroupsView();
            return ListView.builder(
              padding: EdgeInsets.fromLTRB(0, 8.h, 0, 96.h),
              itemCount: groups.length,
              itemBuilder: (_, i) => _GroupCard(group: groups[i]),
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: EdgeInsets.all(24.w),
              child: Text(
                'Could not load groups',
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
class _EmptyGroupsView extends StatelessWidget {
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
              Icons.group_outlined,
              size: 64.sp,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            SizedBox(height: 16.h),
            Text(
              'No groups yet',
              style: TextStyle(
                fontSize: 18.sp,
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
            ),
            SizedBox(height: 8.h),
            Text(
              'Create a group to split expenses with multiple people.',
              style: TextStyle(
                fontSize: 13.sp,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Group card
// ---------------------------------------------------------------------------
class _GroupCard extends ConsumerWidget {
  const _GroupCard({required this.group});
  final GroupModel group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme        = Theme.of(context);
    final membersAsync = ref.watch(groupMembersProvider(group.id));
    final balanceAsync = ref.watch(groupBalanceSummaryProvider(group.id));

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
      child: GlassCard(
        child: InkWell(
          onTap: () {
            HapticUtils.lightTap();
            context.push('/group/${group.id}', extra: {'groupName': group.name});
          },
          borderRadius: BorderRadius.circular(16.r),
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                // ── Group avatar ────────────────────────────────────────
                Container(
                  width: 48.w,
                  height: 48.w,
                  decoration: BoxDecoration(
                    color: _tealDim,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Center(
                    child: Text(
                      group.name.isNotEmpty ? group.name[0].toUpperCase() : 'G',
                      style: TextStyle(
                        color: _teal,
                        fontWeight: FontWeight.w800,
                        fontSize: 20.sp,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 14.w),

                // ── Group info ──────────────────────────────────────────
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.sp,
                        ),
                      ),
                      SizedBox(height: 3.h),
                      membersAsync.when(
                        data: (members) => Text(
                          '${members.length} member${members.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 11.sp,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        loading: () => SizedBox(height: 11.h),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                      SizedBox(height: 4.h),
                      balanceAsync.when(
                        data: (s) {
                          final owed = double.tryParse(s.youAreOwed) ?? 0;
                          final owe  = double.tryParse(s.youOwe)     ?? 0;
                          if (owed == 0 && owe == 0) {
                            return Text(
                              'Settled up',
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: _teal,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          }
                          if (owed > 0) {
                            return Text(
                              'You are owed ${s.currency} ${s.youAreOwed}',
                              style: TextStyle(
                                fontSize: 11.sp,
                                color: _teal,
                                fontWeight: FontWeight.w600,
                              ),
                            );
                          }
                          return Text(
                            'You owe ${s.currency} ${s.youOwe}',
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: _orange,
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
                        loading: () => SizedBox(height: 11.h),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),

                // ── Quick invite icon ────────────────────────────────────
                IconButton(
                  icon: Icon(
                    Icons.person_add_outlined,
                    size: 18.sp,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  onPressed: () {
                    HapticUtils.lightTap();
                    context.push(
                      '/group/${group.id}/invite',
                      extra: {'groupName': group.name},
                    );
                  },
                  tooltip: 'Add member',
                ),

                Icon(
                  Icons.chevron_right,
                  color: theme.colorScheme.onSurfaceVariant,
                  size: 18.sp,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

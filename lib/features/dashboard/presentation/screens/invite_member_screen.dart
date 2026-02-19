import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../widgets/add_person_modal.dart';

const _teal = Color(0xFF00D9B0);
const _tealDim = Color(0x2600D9B0);
const _orange = Color(0xFFFF8C42);

class InviteMemberScreen extends ConsumerStatefulWidget {
  const InviteMemberScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  final String groupId;
  final String groupName;

  @override
  ConsumerState<InviteMemberScreen> createState() => _InviteMemberScreenState();
}

class _InviteMemberScreenState extends ConsumerState<InviteMemberScreen> {
  // Holds the last result to show a summary before popping
  AddPersonResult? _lastResult;

  Future<void> _openAddPersonModal() async {
    HapticUtils.primaryTap();
    final result = await showAddPersonModal(
      context,
      groupId: widget.groupId,
      groupName: widget.groupName,
    );
    if (result == null || !mounted) return;

    setState(() => _lastResult = result);

    // Refresh the group members list in the parent screen.
    ref.invalidate(groupMembersProvider(widget.groupId));
    ref.invalidate(balanceSummaryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Invite member',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16.sp),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            HapticUtils.lightTap();
            context.pop();
          },
        ),
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
        children: [
          // ── Group context card ─────────────────────────────────────────
          GlassCard(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                Container(
                  width: 44.w,
                  height: 44.w,
                  decoration: BoxDecoration(
                    color: _tealDim,
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Center(
                    child: Text(
                      widget.groupName.isNotEmpty
                          ? widget.groupName[0].toUpperCase()
                          : 'G',
                      style: TextStyle(
                        color: _teal,
                        fontWeight: FontWeight.w800,
                        fontSize: 16.sp,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.groupName,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.sp,
                        ),
                      ),
                      Text(
                        'Add members to this group',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 20.h),

          // ── Add Person CTA ────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _openAddPersonModal,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.black,
                padding: EdgeInsets.symmetric(vertical: 14.h),
              ),
              icon: const Icon(Icons.person_search_outlined),
              label: Text(
                'Search & Add Person',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp),
              ),
            ),
          ),

          SizedBox(height: 24.h),

          // ── Last result feedback ───────────────────────────────────────
          if (_lastResult != null) _LastResultCard(result: _lastResult!),

          SizedBox(height: 24.h),

          // ── Info section ──────────────────────────────────────────────
          GlassCard(
            padding: EdgeInsets.all(16.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                  icon: Icons.search,
                  color: _teal,
                  title: 'Find by name, @nickname, or email',
                  body: 'Search instantly searches all SetAll users.',
                ),
                SizedBox(height: 12.h),
                _InfoRow(
                  icon: Icons.send_outlined,
                  color: _orange,
                  title: 'Ghost Invite',
                  body:
                      'If someone isn\'t on SetAll yet, enter their email to add '
                      'them as a placeholder. Their debts are tracked immediately '
                      'and automatically claimed when they sign up.',
                ),
                SizedBox(height: 12.h),
                _InfoRow(
                  icon: Icons.lock_outline,
                  color: theme.colorScheme.onSurfaceVariant,
                  title: 'Privacy',
                  body: 'Members can see all expenses in this group.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Last result feedback card
// ---------------------------------------------------------------------------
class _LastResultCard extends StatelessWidget {
  const _LastResultCard({required this.result});
  final AddPersonResult result;

  @override
  Widget build(BuildContext context) {
    final isGhost = result is AddPersonResultGhost;
    final color = isGhost ? _orange : _teal;
    final icon =
        isGhost ? Icons.send_outlined : Icons.check_circle_outline;
    final title = isGhost
        ? 'Ghost invite sent to ${(result as AddPersonResultGhost).email}'
        : '${(result as AddPersonResultReal).profile.name} added!';

    return GlassCard(
      padding: EdgeInsets.all(12.w),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18.sp),
          SizedBox(width: 10.w),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13.sp,
              ),
            ),
          ),
          TextButton(
            onPressed: () => (context as Element).markNeedsBuild(),
            child: Text(
              'Add another',
              style: TextStyle(color: color, fontSize: 12.sp),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Info row helper
// ---------------------------------------------------------------------------
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: EdgeInsets.all(6.w),
          decoration: BoxDecoration(
            color: color.withAlpha(40),
            borderRadius: BorderRadius.circular(6.r),
          ),
          child: Icon(icon, color: color, size: 14.sp),
        ),
        SizedBox(width: 10.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12.sp,
                ),
              ),
              Text(
                body,
                style: TextStyle(
                  fontSize: 11.sp,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

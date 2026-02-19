import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';

const _teal = Color(0xFF00D9B0);

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
  final _emailCtrl = TextEditingController();
  bool _loading = false;
  String? _error;
  bool _success = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendInvite() async {
    final email = _emailCtrl.text.trim().toLowerCase();
    if (email.isEmpty) {
      setState(() => _error = 'Enter an email address');
      return;
    }
    if (!email.contains('@')) {
      setState(() => _error = 'Enter a valid email address');
      return;
    }

    setState(() { _loading = true; _error = null; _success = false; });
    HapticUtils.primaryTap();

    try {
      final repo = ref.read(setAllRepositoryProvider);
      await repo.addMemberByEmail(widget.groupId, email, groupName: widget.groupName);
      if (!mounted) return;
      HapticUtils.success();
      setState(() { _success = true; _emailCtrl.clear(); });
      // Invalidate members so GroupDetailScreen refreshes on pop.
      ref.invalidate(groupMembersProvider(widget.groupId));
    } catch (e) {
      if (!mounted) return;
      HapticUtils.lightTap();
      final msg = e.toString().toLowerCase();
      if (msg.contains('user_not_found') || msg.contains('not found')) {
        setState(() => _error =
            'No SetAll account found for that email.\n'
            'They can sign up at setall.app and you can add them afterwards.');
      } else if (msg.contains('already') || msg.contains('duplicate')) {
        setState(() => _error = 'That person is already a member of this group.');
      } else {
        setState(() => _error = 'Could not send invite. Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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
          // ── Context card ────────────────────────────────────────────────
          GlassCard(
            padding: EdgeInsets.all(16.w),
            child: Row(
              children: [
                Container(
                  width: 40.w,
                  height: 40.w,
                  decoration: BoxDecoration(
                    color: const Color(0x2600D9B0),
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
                        'Invite by email',
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

          // ── Email field ─────────────────────────────────────────────────
          Text(
            'Email address',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 13.sp,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 8.h),
          TextField(
            controller: _emailCtrl,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _sendInvite(),
            decoration: InputDecoration(
              hintText: 'member@example.com',
              prefixIcon: const Icon(Icons.email_outlined),
            ),
          ),
          SizedBox(height: 8.h),

          // ── Error / Success feedback ─────────────────────────────────────
          if (_error != null)
            Padding(
              padding: EdgeInsets.only(top: 4.h, bottom: 4.h),
              child: GlassCard(
                padding: EdgeInsets.all(12.w),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        color: theme.colorScheme.error, size: 16.sp),
                    SizedBox(width: 8.w),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 12.sp,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          if (_success)
            Padding(
              padding: EdgeInsets.only(top: 4.h, bottom: 4.h),
              child: GlassCard(
                padding: EdgeInsets.all(12.w),
                child: Row(
                  children: [
                    Icon(Icons.check_circle_outline,
                        color: _teal, size: 16.sp),
                    SizedBox(width: 8.w),
                    Text(
                      'Member added successfully!',
                      style: TextStyle(
                        color: _teal,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.sp,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          SizedBox(height: 20.h),

          // ── CTA ─────────────────────────────────────────────────────────
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _sendInvite,
              icon: _loading
                  ? SizedBox(
                      height: 16.h,
                      width: 16.w,
                      child: const CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(
                'Send invite',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14.sp,
                ),
              ),
            ),
          ),
          SizedBox(height: 16.h),

          // ── Info note ───────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline,
                size: 13.sp,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              SizedBox(width: 6.w),
              Expanded(
                child: Text(
                  'The person must have a SetAll account. Once added, they can '
                  'see all expenses in this group.',
                  style: TextStyle(
                    fontSize: 11.sp,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

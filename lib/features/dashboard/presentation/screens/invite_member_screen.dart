import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          // ── Group context card ─────────────────────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _tealDim,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      widget.groupName.isNotEmpty
                          ? widget.groupName[0].toUpperCase()
                          : 'G',
                      style: TextStyle(
                        color: _teal,
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.groupName,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'Add members to this group',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // ── Add Person CTA ────────────────────────────────────────────
          ElevatedButton.icon(
              onPressed: _openAddPersonModal,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: const Icon(Icons.person_search_outlined),
              label: Text(
                'Search & Add Person',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
          ),

          const SizedBox(height: 24),

          // ── Last result feedback ───────────────────────────────────────
          if (_lastResult != null)
            _LastResultCard(
              result: _lastResult!,
              onAddAnother: () => setState(() => _lastResult = null),
            ),

          const SizedBox(height: 24),

          // ── Info section ──────────────────────────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _InfoRow(
                  icon: Icons.search,
                  color: _teal,
                  title: 'Find by name, @nickname, or email',
                  body: 'Search instantly searches all SetAll users.',
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  icon: Icons.send_outlined,
                  color: _orange,
                  title: 'Ghost Invite',
                  body:
                      'If someone isn\'t on SetAll yet, enter their email to add '
                      'them as a placeholder. Their debts are tracked immediately '
                      'and automatically claimed when they sign up.',
                ),
                const SizedBox(height: 12),
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
  const _LastResultCard({required this.result, required this.onAddAnother});
  final AddPersonResult result;
  final VoidCallback onAddAnother;

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
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
          TextButton(
            onPressed: onAddAnother,
            child: Text(
              'Add another',
              style: TextStyle(color: color, fontSize: 12),
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
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: color.withAlpha(40),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, color: color, size: 14),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              Text(
                body,
                style: TextStyle(
                  fontSize: 11,
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

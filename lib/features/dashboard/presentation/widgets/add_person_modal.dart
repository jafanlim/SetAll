import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/profile_model.dart';

const _teal = Color(0xFF00D9B0);
const _orange = Color(0xFFFF8C42);
const _orangeDim = Color(0x26FF8C42);

/// Result of the "Add Person" flow.
sealed class AddPersonResult {}

/// The user selected a real (already-registered) profile.
class AddPersonResultReal extends AddPersonResult {
  AddPersonResultReal(this.profile);
  final ProfileModel profile;
}

/// The user chose to ghost-invite an email address.
class AddPersonResultGhost extends AddPersonResult {
  AddPersonResultGhost(this.email);
  final String email;
}

/// Show the "Add Person" modal and return the result when the user confirms.
/// Returns null if the user dismissed without selecting.
Future<AddPersonResult?> showAddPersonModal(
  BuildContext context, {
  required String groupId,
  required String groupName,
}) {
  return showModalBottomSheet<AddPersonResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _AddPersonModal(groupId: groupId, groupName: groupName),
  );
}

// ---------------------------------------------------------------------------
// Internal modal widget
// ---------------------------------------------------------------------------
class _AddPersonModal extends ConsumerStatefulWidget {
  const _AddPersonModal({required this.groupId, required this.groupName});

  final String groupId;
  final String groupName;

  @override
  ConsumerState<_AddPersonModal> createState() => _AddPersonModalState();
}

class _AddPersonModalState extends ConsumerState<_AddPersonModal> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _query = '';

  // State machine
  bool _adding  = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _ctrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = value.trim());
    });
  }

  bool get _looksLikeEmail => _query.contains('@') && _query.contains('.');

  Future<void> _addRealUser(ProfileModel profile) async {
    setState(() { _adding = true; _error = null; _success = null; });
    HapticUtils.primaryTap();
    try {
      await ref.read(setAllRepositoryProvider).addMemberById(
        widget.groupId,
        profile.id,
      );
      if (!mounted) return;
      HapticUtils.success();
      setState(() { _success = '${profile.name} added to group!'; _adding = false; });
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.of(context).pop(AddPersonResultReal(profile));
    } catch (e) {
      if (!mounted) return;
      final raw = e.toString();
      debugPrint('[addPersonModal] addMemberById failed: $raw');
      final msg = raw.toLowerCase();
      setState(() {
        _error = msg.contains('already') || msg.contains('duplicate') || msg.contains('23505')
            ? '${profile.name} is already in this group.'
            : msg.contains('not found')
                ? 'User not found.'
                : 'Could not add member — $raw';
        _adding = false;
      });
    }
  }

  Future<void> _addGhostUser(String email) async {
    setState(() { _adding = true; _error = null; _success = null; });
    HapticUtils.primaryTap();
    try {
      final repo = ref.read(setAllRepositoryProvider);
      final ghostId = await repo.addGhostMember(widget.groupId, email);
      if (!mounted) return;
      if (ghostId == null) {
        setState(() {
          _error = 'Ghost invite requires an internet connection.';
          _adding = false;
        });
        return;
      }
      HapticUtils.success();
      setState(() { _success = 'Invite sent to $email'; _adding = false; });
      await Future.delayed(const Duration(milliseconds: 800));
      if (mounted) Navigator.of(context).pop(AddPersonResultGhost(email));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not create ghost invite. Check your connection.';
        _adding = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final searchAsync = ref.watch(searchUsersProvider(_query));

    return AnimatedPadding(
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle ───────────────────────────────────────────────────
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

            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add Person',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                          ),
                        ),
                        Text(
                          widget.groupName,
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

            // ── Search field ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _ctrl,
                autofocus: false,
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

            // ── Feedback ─────────────────────────────────────────────────
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

            // ── Results ───────────────────────────────────────────────────
            Flexible(
              child: _query.length < 2
                  ? _EmptySearchHint()
                  : searchAsync.when(
                      loading: () => const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      error: (_, _) => _GhostInviteSection(
                        email: _query,
                        looksLikeEmail: _looksLikeEmail,
                        adding: _adding,
                        onInvite: _addGhostUser,
                      ),
                      data: (results) => results.isEmpty
                          ? _GhostInviteSection(
                              email: _query,
                              looksLikeEmail: _looksLikeEmail,
                              adding: _adding,
                              onInvite: _addGhostUser,
                            )
                          : ListView(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 16, vertical: 4),
                              children: [
                                ...results.map((p) => _UserResultTile(
                                  profile: p,
                                  adding: _adding,
                                  onAdd: () => _addRealUser(p),
                                )),
                                const SizedBox(height: 8),
                                // Always show ghost invite below results
                                if (_looksLikeEmail)
                                  _GhostInviteSection(
                                    email: _query,
                                    looksLikeEmail: true,
                                    adding: _adding,
                                    onInvite: _addGhostUser,
                                  ),
                              ],
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
// User result tile
// ---------------------------------------------------------------------------
class _UserResultTile extends StatelessWidget {
  const _UserResultTile({
    required this.profile,
    required this.adding,
    required this.onAdd,
  });

  final ProfileModel profile;
  final bool adding;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: _Avatar(profile: profile),
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
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : FilledButton(
                onPressed: onAdd,
                style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.black,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  textStyle: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w700),
                  minimumSize: const Size(0, 0),
                ),
                child: const Text('Add'),
              ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ghost invite section
// ---------------------------------------------------------------------------
class _GhostInviteSection extends StatelessWidget {
  const _GhostInviteSection({
    required this.email,
    required this.looksLikeEmail,
    required this.adding,
    required this.onInvite,
  });

  final String email;
  final bool looksLikeEmail;
  final bool adding;
  final ValueChanged<String> onInvite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!looksLikeEmail) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.person_search,
                  size: 40, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 12),
              Text(
                'No users found for "$email".',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Try a full email address to send a ghost invite.',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _orangeDim,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.send_outlined,
                      color: _orange, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Ghost Invite',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'No SetAll account found for:',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Text(
              email,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: _orange,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'They\'ll be added as a placeholder. When they sign up with this '
              'email, their expenses and debts will be automatically claimed.',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            ElevatedButton.icon(
                onPressed: adding ? null : () => onInvite(email),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _orange,
                  foregroundColor: Colors.white,
                ),
                icon: adding
                    ? const SizedBox(
                        height: 14,
                        width: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.person_add_outlined, size: 16),
                label: Text(
                  'Send Ghost Invite',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state hint
// ---------------------------------------------------------------------------
class _EmptySearchHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Column(
        children: [
          Icon(Icons.search, size: 40,
              color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            'Search by name, @nickname, or email address.',
            style: TextStyle(
              fontSize: 13,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Enter a full email address to send a ghost invite if the person '
            'doesn\'t have an account yet.',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant.withAlpha(170),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar widget
// ---------------------------------------------------------------------------
class _Avatar extends StatelessWidget {
  const _Avatar({required this.profile});
  final ProfileModel profile;

  @override
  Widget build(BuildContext context) {
    return Container(
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
          profile.displayInitial,
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

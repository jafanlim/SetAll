import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/profile_model.dart';

const _teal    = Color(0xFF00D9B0);
const _tealDim = Color(0x2600D9B0);

class CreateGroupScreen extends ConsumerStatefulWidget {
  /// Optional callback invoked instead of the default navigation to group detail.
  /// Receives the new group id and name. Use this from the expense flow to
  /// redirect to add-expense after group creation.
  final void Function(String groupId, String groupName)? onGroupCreated;

  const CreateGroupScreen({super.key, this.onGroupCreated});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameCtrl   = TextEditingController();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  String _query   = '';
  bool   _creating = false;
  String? _error;

  // Selected members to add on creation
  final List<ProfileModel> _selected = [];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onQueryChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  void _toggleMember(ProfileModel profile) {
    HapticUtils.selection();
    setState(() {
      if (_selected.any((p) => p.id == profile.id)) {
        _selected.removeWhere((p) => p.id == profile.id);
      } else {
        _selected.add(profile);
      }
    });
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a group name.');
      return;
    }
    setState(() { _creating = true; _error = null; });
    HapticUtils.primaryTap();

    try {
      final repo  = ref.read(setAllRepositoryProvider);
      final group = await repo.createGroup(name);
      if (group == null) {
        setState(() {
          _error    = 'Could not create group. Check your connection.';
          _creating = false;
        });
        return;
      }

      // Add all selected members via the SECURITY DEFINER RPC.
      final failedNames = <String>[];
      for (final member in _selected) {
        try {
          await repo.addMemberById(group.id, member.id);
        } catch (e) {
          failedNames.add(member.name);
          debugPrint('addMemberById failed for ${member.name}: $e');
        }
      }

      ref.invalidate(myGroupsProvider);
      HapticUtils.success();

      if (!mounted) return;

      if (failedNames.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Group created, but could not add: ${failedNames.join(', ')}. '
              'Try adding them from the group page.',
            ),
            duration: const Duration(seconds: 5),
          ),
        );
      }
      final onCreated = widget.onGroupCreated;
      if (onCreated != null) {
        onCreated(group.id, group.name);
      } else {
        context.pushReplacement(
          '/group/${group.id}',
          extra: {'groupName': group.name},
        );
      }
    } catch (e) {
      if (!mounted) return;
      // createGroup threw — likely offline or RLS blocked the group insert.
      setState(() {
        _error    = 'Could not create group: ${e.toString().replaceFirst('Exception: ', '')}';
        _creating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final searchAsync = ref.watch(searchUsersProvider(_query));

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'New Group',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [

                // ── Group name ───────────────────────────────────────────────
                Text(
                  'Group name',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'e.g. Barcelona trip, Flat mates…',
                    prefixIcon: const Icon(Icons.group_outlined),
                    errorText: _error,
                  ),
                  onChanged: (_) {
                    if (_error != null) setState(() => _error = null);
                  },
                ),

                const SizedBox(height: 24),

                // ── Selected members chips ───────────────────────────────────
                if (_selected.isNotEmpty) ...[
                  Text(
                    'Members (${_selected.length})',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _selected
                        .map((p) => Chip(
                              label: Text(
                                p.name,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              avatar: CircleAvatar(
                                backgroundColor: _tealDim,
                                child: Text(
                                  p.name.isNotEmpty
                                      ? p.name[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: _teal,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              deleteIcon: const Icon(Icons.close, size: 14),
                              onDeleted: () => _toggleMember(p),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Add members section ──────────────────────────────────────
                Text(
                  'Add members (optional)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _searchCtrl,
                  onChanged: _onQueryChanged,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'Search by name, @nickname or email…',
                    prefixIcon: const Icon(Icons.person_search_outlined),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = '');
                            },
                          )
                        : null,
                  ),
                ),

                const SizedBox(height: 8),

                // ── Search results ───────────────────────────────────────────
                if (_query.length >= 2)
                  searchAsync.when(
                    loading: () => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: const Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        'Search unavailable. Check connection.',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    data: (results) {
                      if (results.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'No users found for "$_query".',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        );
                      }
                      return Column(
                        children: results.map((p) {
                          final isSelected =
                              _selected.any((s) => s.id == p.id);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: GlassCard(
                              padding: EdgeInsets.zero,
                              child: ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: isSelected ? _teal : _tealDim,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      p.name.isNotEmpty
                                          ? p.name[0].toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: isSelected
                                            ? Colors.black
                                            : _teal,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                title: Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                subtitle: p.nickname != null
                                    ? Text(
                                        '@${p.nickname}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: _teal,
                                        ),
                                      )
                                    : null,
                                trailing: isSelected
                                    ? const Icon(Icons.check_circle,
                                        color: _teal, size: 22)
                                    : Icon(Icons.add_circle_outline,
                                        color: theme.colorScheme.onSurfaceVariant,
                                        size: 22),
                                onTap: () => _toggleMember(p),
                              ),
                            ),
                          );
                        }).toList(),
                      );
                    },
                  )
                else if (_query.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      'You can add members now or later from the group page.',
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),

                const SizedBox(height: 100), // space for bottom button
              ],
            ),
          ),

          // ── Create button ────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(16, 12, 16,
                MediaQuery.paddingOf(context).bottom + 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: theme.colorScheme.outlineVariant,
                  width: 0.5,
                ),
              ),
            ),
            child: FilledButton.icon(
                onPressed: _creating ? null : _create,
                style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                icon: _creating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.check_rounded),
                label: Text(
                  _creating
                      ? 'Creating…'
                      : _selected.isEmpty
                          ? 'Create Group'
                          : 'Create Group with ${_selected.length} member${_selected.length == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
            ),
          ),
        ],
      ),
    );
  }
}

import 'dart:async';
import 'dart:io' as _io;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/profile_model.dart';

const _teal    = Color(0xFF00D9B0);
const _tealDim = Color(0x2600D9B0);

// ── Fintech group palette ──────────────────────────────────────────────────
const _groupPalette = [
  _GroupColor('Teal',   Color(0xFF00D9B0), Color(0xFF004D40)),
  _GroupColor('Indigo', Color(0xFF6366F1), Color(0xFF1E1B4B)),
  _GroupColor('Rose',   Color(0xFFF43F5E), Color(0xFF4C0519)),
  _GroupColor('Amber',  Color(0xFFF59E0B), Color(0xFF451A03)),
  _GroupColor('Slate',  Color(0xFF94A3B8), Color(0xFF1E293B)),
];

class _GroupColor {
  final String label;
  final Color accent;
  final Color bg;
  const _GroupColor(this.label, this.accent, this.bg);
}

// ── Icon catalogue ─────────────────────────────────────────────────────────
const _groupIcons = <_GroupIcon>[
  _GroupIcon('groups',     Icons.groups_outlined),
  _GroupIcon('home',       Icons.home_outlined),
  _GroupIcon('flight',     Icons.flight_outlined),
  _GroupIcon('hotel',      Icons.hotel_outlined),
  _GroupIcon('restaurant', Icons.restaurant_outlined),
  _GroupIcon('shopping',   Icons.shopping_bag_outlined),
  _GroupIcon('sports',     Icons.sports_soccer_outlined),
  _GroupIcon('music',      Icons.music_note_outlined),
  _GroupIcon('school',     Icons.school_outlined),
  _GroupIcon('work',       Icons.work_outline),
  _GroupIcon('car',        Icons.directions_car_outlined),
  _GroupIcon('beach',      Icons.beach_access_outlined),
  _GroupIcon('party',      Icons.celebration_outlined),
  _GroupIcon('health',     Icons.favorite_outline),
  _GroupIcon('coffee',     Icons.local_cafe_outlined),
];

class _GroupIcon {
  final String name;
  final IconData data;
  const _GroupIcon(this.name, this.data);
}

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

  String _query    = '';
  bool   _creating = false;
  String? _error;

  // Identity customization
  int _colorIdx  = 0; // index into _groupPalette
  int _iconIdx   = 0; // index into _groupIcons
  String? _avatarLocalPath;

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

  Future<void> _pickAvatar() async {
    if (kIsWeb) return;
    HapticUtils.lightTap();
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: ImageSource.gallery);
      if (picked == null || !mounted) return;
      setState(() => _avatarLocalPath = picked.path);
    } catch (e) {
      debugPrint('[CreateGroup] avatar pick failed: $e');
    }
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Please enter a group name.');
      return;
    }
    setState(() { _creating = true; _error = null; });
    HapticUtils.primaryTap();

    final palette   = _groupPalette[_colorIdx];
    final iconEntry = _groupIcons[_iconIdx];
    final colorValue = palette.accent.value;
    final iconName   = iconEntry.name;

    try {
      final repo = ref.read(setAllRepositoryProvider);

      // Upload avatar first if the user selected one.
      String? avatarStoragePath;
      if (_avatarLocalPath != null) {
        // We need the group id first — create without avatar, then upload.
        final tempGroup = await repo.createGroup(
          name, iconName: iconName, colorValue: colorValue);
        if (tempGroup == null) {
          setState(() {
            _error    = 'Could not create group. Check your connection.';
            _creating = false;
          });
          return;
        }
        avatarStoragePath = await repo.uploadGroupAvatar(
            tempGroup.id, _avatarLocalPath!);
        if (avatarStoragePath != null) {
          await repo.updateGroupCustomization(
              tempGroup.id, avatarUrl: avatarStoragePath);
        }
        await _addMembersAndNavigate(repo, tempGroup.id, name);
        return;
      }

      final group = await repo.createGroup(
        name,
        iconName: iconName,
        colorValue: colorValue,
        avatarUrl: avatarStoragePath,
      );
      if (group == null) {
        setState(() {
          _error    = 'Could not create group. Check your connection.';
          _creating = false;
        });
        return;
      }
      await _addMembersAndNavigate(repo, group.id, name);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error    = 'Could not create group: ${e.toString().replaceFirst('Exception: ', '')}';
        _creating = false;
      });
    }
  }

  Future<void> _addMembersAndNavigate(
      dynamic repo, String groupId, String name) async {
    final failedNames = <String>[];
    for (final member in _selected) {
      try {
        await repo.addMemberById(groupId, member.id);
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
      onCreated(groupId, name);
    } else {
      context.pushReplacement(
        '/group/$groupId',
        extra: {'groupName': name},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme       = Theme.of(context);
    final searchAsync = ref.watch(searchUsersProvider(_query));
    final palette     = _groupPalette[_colorIdx];
    final iconEntry   = _groupIcons[_iconIdx];

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'New Group',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
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

                // ── Group Appearance ─────────────────────────────────────────
                _SectionLabel('Group Appearance', theme),
                const SizedBox(height: 10),

                // Avatar preview + upload button
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: palette.bg,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: palette.accent.withValues(alpha: 0.4),
                              width: 2,
                            ),
                          ),
                          child: _avatarLocalPath != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(18),
                                  child: Image.file(
                                    _io.File(_avatarLocalPath!),
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Icon(iconEntry.data, size: 36, color: palette.accent),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: palette.accent,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.camera_alt_outlined,
                                size: 13, color: Colors.black),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // ── Colour picker ────────────────────────────────────────────
                Text(
                  'Colour',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: List.generate(_groupPalette.length, (i) {
                    final c = _groupPalette[i];
                    final selected = i == _colorIdx;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () {
                          HapticUtils.selection();
                          setState(() => _colorIdx = i);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: c.accent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? Colors.white : Colors.transparent,
                              width: 2.5,
                            ),
                            boxShadow: selected
                                ? [BoxShadow(color: c.accent.withValues(alpha: 0.5), blurRadius: 8)]
                                : null,
                          ),
                          child: selected
                              ? const Icon(Icons.check, size: 16, color: Colors.white)
                              : null,
                        ),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 16),

                // ── Icon picker ──────────────────────────────────────────────
                Text(
                  'Icon',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_groupIcons.length, (i) {
                    final ic      = _groupIcons[i];
                    final selected = i == _iconIdx;
                    return GestureDetector(
                      onTap: () {
                        HapticUtils.selection();
                        setState(() {
                          _iconIdx = i;
                          _avatarLocalPath = null;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: selected ? palette.accent.withValues(alpha: 0.2) : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? palette.accent : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(ic.data, size: 20,
                            color: selected ? palette.accent : theme.colorScheme.onSurfaceVariant),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 24),

                // ── Group name ───────────────────────────────────────────────
                _SectionLabel('Group Name', theme),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameCtrl,
                  autofocus: false,
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
                  _SectionLabel('Members (${_selected.length})', theme),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _selected
                        .map((p) => Chip(
                              label: Text(p.name,
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                              avatar: CircleAvatar(
                                backgroundColor: _tealDim,
                                child: Text(
                                  p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                                  style: const TextStyle(fontSize: 10, color: _teal, fontWeight: FontWeight.w700),
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
                _SectionLabel('Add Members (optional)', theme),
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
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (_, _) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('Search unavailable. Check connection.',
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                    ),
                    data: (results) {
                      if (results.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text('No users found for "$_query".',
                              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                        );
                      }
                      return Column(
                        children: results.map((p) {
                          final isSelected = _selected.any((s) => s.id == p.id);
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: GlassCard(
                              padding: EdgeInsets.zero,
                              child: ListTile(
                                leading: Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: isSelected ? _teal : _tealDim,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                                      style: TextStyle(
                                        color: isSelected ? Colors.black : _teal,
                                        fontWeight: FontWeight.w800, fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                                title: Text(p.name,
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                subtitle: p.nickname != null
                                    ? Text('@${p.nickname}',
                                        style: const TextStyle(fontSize: 11, color: _teal))
                                    : null,
                                trailing: isSelected
                                    ? const Icon(Icons.check_circle, color: _teal, size: 22)
                                    : Icon(Icons.add_circle_outline,
                                        color: theme.colorScheme.onSurfaceVariant, size: 22),
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
                      style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ),

                const SizedBox(height: 100),
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
                top: BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5),
              ),
            ),
            child: FilledButton.icon(
              onPressed: _creating ? null : _create,
              style: FilledButton.styleFrom(
                backgroundColor: _groupPalette[_colorIdx].accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _creating
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                _creating
                    ? 'Creating…'
                    : _selected.isEmpty
                        ? 'Create Group'
                        : 'Create Group with ${_selected.length} member${_selected.length == 1 ? '' : 's'}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label, this.theme);
  final String label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: theme.colorScheme.onSurfaceVariant,
        letterSpacing: 0.5,
      ),
    );
  }
}

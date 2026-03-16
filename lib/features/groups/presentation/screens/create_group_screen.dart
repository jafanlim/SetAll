import 'dart:async';
import 'dart:io' as _io;

import 'package:easy_localization/easy_localization.dart';
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

// ── Expanded group palette (15 colours) ───────────────────────────────────
const _groupPalette = [
  _GroupColor('Teal',     Color(0xFF00D9B0), Color(0xFF004D40)),
  _GroupColor('Indigo',   Color(0xFF6366F1), Color(0xFF1E1B4B)),
  _GroupColor('Rose',     Color(0xFFF43F5E), Color(0xFF4C0519)),
  _GroupColor('Amber',    Color(0xFFF59E0B), Color(0xFF451A03)),
  _GroupColor('Slate',    Color(0xFF94A3B8), Color(0xFF1E293B)),
  _GroupColor('Purple',   Color(0xFFA855F7), Color(0xFF3B0764)),
  _GroupColor('Blue',     Color(0xFF3B82F6), Color(0xFF1E3A8A)),
  _GroupColor('Green',    Color(0xFF22C55E), Color(0xFF14532D)),
  _GroupColor('Orange',   Color(0xFFF97316), Color(0xFF431407)),
  _GroupColor('Cyan',     Color(0xFF06B6D4), Color(0xFF164E63)),
  _GroupColor('Lime',     Color(0xFF84CC16), Color(0xFF1A2E05)),
  _GroupColor('Pink',     Color(0xFFEC4899), Color(0xFF500724)),
  _GroupColor('Red',      Color(0xFFEF4444), Color(0xFF7F1D1D)),
  _GroupColor('Emerald',  Color(0xFF10B981), Color(0xFF064E3B)),
  _GroupColor('Fuchsia',  Color(0xFFD946EF), Color(0xFF4A044E)),
];

// Extended swatches shown in the custom colour picker dialog
const _kCustomColors = [
  Color(0xFF00D9B0), Color(0xFF6366F1), Color(0xFFF43F5E), Color(0xFFF59E0B),
  Color(0xFF94A3B8), Color(0xFFA855F7), Color(0xFF3B82F6), Color(0xFF22C55E),
  Color(0xFFF97316), Color(0xFF06B6D4), Color(0xFF84CC16), Color(0xFFEC4899),
  Color(0xFFEF4444), Color(0xFF10B981), Color(0xFFD946EF), Color(0xFF14B8A6),
  Color(0xFFE879F9), Color(0xFF818CF8), Color(0xFF34D399), Color(0xFFFBBF24),
  Color(0xFFF87171), Color(0xFF60A5FA), Color(0xFF4ADE80), Color(0xFFA78BFA),
  Color(0xFFFDA4AF), Color(0xFF67E8F9), Color(0xFFBEF264), Color(0xFFD1D5DB),
  Color(0xFF1F2937), Color(0xFFFFFFFF),
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
  int _colorIdx        = 0; // index into _groupPalette
  int _iconIdx         = 0; // index into _groupIcons
  Color? _customColor;
  String? _avatarLocalPath;
  String? _defaultCurrency;

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
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: Text('create_group.choose_gallery'.tr()),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: Text('create_group.take_photo'.tr()),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            if (_avatarLocalPath != null)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: Text('create_group.remove_photo'.tr(), style: const TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() => _avatarLocalPath = null);
                },
              ),
          ],
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(source: source, imageQuality: 85);
      if (picked == null || !mounted) return;
      setState(() => _avatarLocalPath = picked.path);
    } catch (e) {
      debugPrint('[CreateGroup] avatar pick failed: $e');
    }
  }

  Color get _accentColor => _customColor ?? _groupPalette[_colorIdx].accent;

  Future<void> _openColorPicker() async {
    HapticUtils.selection();
    final picked = await showDialog<Color>(
      context: context,
      builder: (ctx) => _ColorPickerDialog(initial: _accentColor),
    );
    if (picked != null && mounted) setState(() => _customColor = picked);
  }

  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'create_group.please_enter_name'.tr());
      return;
    }
    setState(() { _creating = true; _error = null; });
    HapticUtils.primaryTap();

    final iconEntry  = _groupIcons[_iconIdx];
    final colorValue = _accentColor.toARGB32();
    final iconName   = iconEntry.name;

    try {
      final repo = ref.read(setAllRepositoryProvider);

      // Upload avatar first if the user selected one.
      String? avatarStoragePath;
      if (_avatarLocalPath != null) {
        // We need the group id first — create without avatar, then upload.
        final tempGroup = await repo.createGroup(
          name, iconName: iconName, colorValue: colorValue,
          defaultCurrency: _defaultCurrency);
        if (tempGroup == null) {
          setState(() {
            _error    = 'create_group.could_not_create'.tr();
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
        defaultCurrency: _defaultCurrency,
      );
      if (group == null) {
        setState(() {
          _error    = 'create_group.could_not_create'.tr();
          _creating = false;
        });
        return;
      }
      await _addMembersAndNavigate(repo, group.id, name);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error    = 'create_group.could_not_create'.tr();
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
            'create_group.partial_add_failed'.tr(namedArgs: {'names': failedNames.join(', ')}),
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
    final existingMembersAsync = ref.watch(allGroupMembersProvider);
    final palette     = _groupPalette[_colorIdx];
    final iconEntry   = _groupIcons[_iconIdx];
    final accent      = _accentColor;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'create_group.title'.tr(),
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

                // ── Group Appearance ─────────────────────────────────────────
                _SectionLabel('create_group.appearance'.tr(), theme),
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
                              : Icon(iconEntry.data, size: 36, color: accent),
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: accent,
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
                  'create_group.colour'.tr(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...List.generate(_groupPalette.length, (i) {
                        final c = _groupPalette[i];
                        final selected = _customColor == null && i == _colorIdx;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () {
                              HapticUtils.selection();
                              setState(() { _colorIdx = i; _customColor = null; });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 34,
                              height: 34,
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
                                  ? const Icon(Icons.check, size: 15, color: Colors.white)
                                  : null,
                            ),
                          ),
                        );
                      }),
                      // Custom colour button
                      GestureDetector(
                        onTap: _openColorPicker,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 34, height: 34,
                          decoration: BoxDecoration(
                            color: _customColor ?? Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _customColor != null
                                  ? Colors.white
                                  : theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                              width: _customColor != null ? 2.5 : 1.5,
                            ),
                            boxShadow: _customColor != null
                                ? [BoxShadow(color: _customColor!.withValues(alpha: 0.5), blurRadius: 8)]
                                : null,
                          ),
                          child: Icon(
                            Icons.colorize_outlined, size: 15,
                            color: _customColor != null
                                ? Colors.white
                                : theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Icon picker ──────────────────────────────────────────────
                Text(
                  'create_group.icon'.tr(),
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
                          color: selected ? accent.withValues(alpha: 0.2) : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? accent : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(ic.data, size: 20,
                            color: selected ? accent : theme.colorScheme.onSurfaceVariant),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 16),

                // ── Group currency ───────────────────────────────────────────
                Text(
                  'create_group.group_currency'.tr(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'create_group.group_currency_subtitle'.tr(),
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                _CurrencyPickerButton(
                  value: _defaultCurrency,
                  accent: _accentColor,
                  onChanged: (v) => setState(() => _defaultCurrency = v),
                ),

                const SizedBox(height: 24),

                // ── Group name ───────────────────────────────────────────────
                _SectionLabel('create_group.group_name'.tr(), theme),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameCtrl,
                  autofocus: false,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: 'create_group.group_name_hint'.tr(),
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
                  _SectionLabel('create_group.members_count'.tr(namedArgs: {'count': '${_selected.length}'}), theme),
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

                // ── Fast-add from existing groups ────────────────────────────
                existingMembersAsync.when(
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (existing) {
                    final available = existing
                        .where((p) => !_selected.any((s) => s.id == p.id))
                        .toList();
                    if (available.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SectionLabel('create_group.quick_add'.tr(), theme),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: available.map((p) => GestureDetector(
                            onTap: () => _toggleMember(p),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: _tealDim,
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: _teal.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CircleAvatar(
                                    radius: 10,
                                    backgroundColor: _teal.withValues(alpha: 0.2),
                                    child: Text(
                                      p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                                      style: const TextStyle(fontSize: 9, color: _teal, fontWeight: FontWeight.w700),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(p.name,
                                      style: const TextStyle(fontSize: 12, color: _teal, fontWeight: FontWeight.w600)),
                                  const SizedBox(width: 4),
                                  const Icon(Icons.add, size: 12, color: _teal),
                                ],
                              ),
                            ),
                          )).toList(),
                        ),
                        const SizedBox(height: 16),
                      ],
                    );
                  },
                ),

                // ── Add members section ──────────────────────────────────────
                _SectionLabel('create_group.add_members'.tr(), theme),
                const SizedBox(height: 6),
                TextField(
                  controller: _searchCtrl,
                  onChanged: _onQueryChanged,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: 'create_group.search_hint'.tr(),
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
                      child: Text('create_group.search_unavailable'.tr(),
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
                    ),
                    data: (results) {
                      if (results.isEmpty) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text('create_group.no_users_found'.tr(namedArgs: {'query': _query}),
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
                      'create_group.add_later_hint'.tr(),
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
                backgroundColor: accent,
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
                    ? 'create_group.creating'.tr()
                    : _selected.isEmpty
                        ? 'create_group.create_btn'.tr()
                        : _selected.length == 1
                            ? 'create_group.create_with_members_one'.tr()
                            : 'create_group.create_with_members_other'.tr(namedArgs: {'count': '${_selected.length}'}),
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
// Colour picker dialog (30-swatch grid)
// ---------------------------------------------------------------------------
class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial});
  final Color initial;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late Color _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text('create_group.pick_colour'.tr(), style: const TextStyle(fontSize: 16)),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _kCustomColors.map((c) {
                final sel = c.toARGB32() == _selected.toARGB32();
                return GestureDetector(
                  onTap: () => setState(() => _selected = c),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sel ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                      boxShadow: sel
                          ? [BoxShadow(color: c.withValues(alpha: 0.6), blurRadius: 6)]
                          : null,
                    ),
                    child: sel
                        ? const Icon(Icons.check, size: 16, color: Colors.white)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: _selected,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: theme.colorScheme.outlineVariant, width: 1),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '#${_selected.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                  style: TextStyle(
                    fontSize: 12, fontFamily: 'monospace',
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('common.cancel'.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: Text('common.apply'.tr()),
        ),
      ],
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

// ---------------------------------------------------------------------------
// Currency picker button (shared by Create + Edit group screens)
// ---------------------------------------------------------------------------
const _kCommonCurrencies = [
  'USD', 'EUR', 'GBP', 'JPY', 'CNY', 'INR', 'AUD', 'CAD', 'CHF', 'KRW',
  'SGD', 'HKD', 'SEK', 'NOK', 'DKK', 'NZD', 'MXN', 'BRL', 'ZAR', 'RUB',
  'TRY', 'AED', 'SAR', 'THB', 'IDR', 'MYR', 'PHP', 'VND', 'PLN', 'HUF',
  'CZK', 'ILS', 'CLP', 'PKR', 'EGP', 'NGN', 'UAH', 'GEL', 'RON', 'ARS',
];

class _CurrencyPickerButton extends StatelessWidget {
  const _CurrencyPickerButton({
    required this.value,
    required this.accent,
    required this.onChanged,
  });
  final String?  value;
  final Color    accent;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => _openPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: value != null
                ? accent.withValues(alpha: 0.6)
                : theme.colorScheme.outlineVariant,
            width: value != null ? 1.2 : 0.8,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.currency_exchange_outlined,
              size: 18,
              color: value != null ? accent : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                value ?? 'create_group.use_default_currency'.tr(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: value != null ? FontWeight.w700 : FontWeight.w400,
                  color: value != null
                      ? theme.colorScheme.onSurface
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            if (value != null)
              GestureDetector(
                onTap: () => onChanged(null),
                child: Icon(Icons.close, size: 16,
                    color: theme.colorScheme.onSurfaceVariant),
              )
            else
              Icon(Icons.chevron_right, size: 18,
                  color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CurrencyPickerSheet(current: value),
    );
    if (picked != null) onChanged(picked);
  }
}

class _CurrencyPickerSheet extends StatefulWidget {
  const _CurrencyPickerSheet({required this.current});
  final String? current;

  @override
  State<_CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<_CurrencyPickerSheet> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final filtered = _kCommonCurrencies
        .where((c) => c.contains(_query.toUpperCase()))
        .toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      minChildSize: 0.4,
      builder: (ctx, scroll) => Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: TextField(
                controller: _ctrl,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: 'create_group.search_currency'.tr(),
                  prefixIcon: const Icon(Icons.search, size: 18),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: filtered.length,
                itemBuilder: (_, i) {
                  final c = filtered[i];
                  final selected = c == widget.current;
                  return ListTile(
                    title: Text(c,
                        style: TextStyle(
                          fontWeight: selected
                              ? FontWeight.w700 : FontWeight.w500,
                          color: selected
                              ? const Color(0xFF00D9B0)
                              : theme.colorScheme.onSurface,
                        )),
                    trailing: selected
                        ? const Icon(Icons.check_circle,
                            color: Color(0xFF00D9B0), size: 20)
                        : null,
                    onTap: () => Navigator.pop(context, c),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

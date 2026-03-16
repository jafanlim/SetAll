import 'dart:io' as io;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../data/models/group_model.dart';

// ---------------------------------------------------------------------------
// Expanded colour palette (15 standard + custom)
// ---------------------------------------------------------------------------
const _kGroupPalette = [
  _GC('Teal',     Color(0xFF00D9B0), Color(0xFF004D40)),
  _GC('Indigo',   Color(0xFF6366F1), Color(0xFF1E1B4B)),
  _GC('Rose',     Color(0xFFF43F5E), Color(0xFF4C0519)),
  _GC('Amber',    Color(0xFFF59E0B), Color(0xFF451A03)),
  _GC('Slate',    Color(0xFF94A3B8), Color(0xFF1E293B)),
  _GC('Purple',   Color(0xFFA855F7), Color(0xFF3B0764)),
  _GC('Blue',     Color(0xFF3B82F6), Color(0xFF1E3A8A)),
  _GC('Green',    Color(0xFF22C55E), Color(0xFF14532D)),
  _GC('Orange',   Color(0xFFF97316), Color(0xFF431407)),
  _GC('Cyan',     Color(0xFF06B6D4), Color(0xFF164E63)),
  _GC('Lime',     Color(0xFF84CC16), Color(0xFF1A2E05)),
  _GC('Pink',     Color(0xFFEC4899), Color(0xFF500724)),
  _GC('Red',      Color(0xFFEF4444), Color(0xFF7F1D1D)),
  _GC('Emerald',  Color(0xFF10B981), Color(0xFF064E3B)),
  _GC('Fuchsia',  Color(0xFFD946EF), Color(0xFF4A044E)),
];

// Extended custom palette for the picker dialog (more hues)
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

// ---------------------------------------------------------------------------
// Icon catalogue (same as CreateGroupScreen)
// ---------------------------------------------------------------------------
const _kGroupIcons = <_GI>[
  _GI('groups',     Icons.groups_outlined),
  _GI('home',       Icons.home_outlined),
  _GI('flight',     Icons.flight_outlined),
  _GI('hotel',      Icons.hotel_outlined),
  _GI('restaurant', Icons.restaurant_outlined),
  _GI('shopping',   Icons.shopping_bag_outlined),
  _GI('sports',     Icons.sports_soccer_outlined),
  _GI('music',      Icons.music_note_outlined),
  _GI('school',     Icons.school_outlined),
  _GI('work',       Icons.work_outline),
  _GI('car',        Icons.directions_car_outlined),
  _GI('beach',      Icons.beach_access_outlined),
  _GI('party',      Icons.celebration_outlined),
  _GI('health',     Icons.favorite_outline),
  _GI('coffee',     Icons.local_cafe_outlined),
];

class _GC {
  final String label;
  final Color accent;
  final Color bg;
  const _GC(this.label, this.accent, this.bg);
}

class _GI {
  final String name;
  final IconData data;
  const _GI(this.name, this.data);
}

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class EditGroupScreen extends ConsumerStatefulWidget {
  const EditGroupScreen({super.key, required this.group});
  final GroupModel group;

  @override
  ConsumerState<EditGroupScreen> createState() => _EditGroupScreenState();
}

class _EditGroupScreenState extends ConsumerState<EditGroupScreen> {
  late final TextEditingController _nameCtrl;

  int _colorIdx   = 0;
  int _iconIdx    = 0;
  Color? _customColor;
  String? _avatarLocalPath;
  bool? _removeAvatar;
  bool _saving = false;
  String? _defaultCurrency;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.group.name);

    // Pre-select matching colour
    final cv = widget.group.colorValue;
    if (cv != null) {
      final idx = _kGroupPalette
          .indexWhere((c) => c.accent.toARGB32() == cv);
      if (idx >= 0) {
        _colorIdx = idx;
      } else {
        _customColor = Color(cv);
      }
    }

    // Pre-select matching icon
    final iname = widget.group.iconName;
    if (iname != null) {
      final idx = _kGroupIcons.indexWhere((i) => i.name == iname);
      if (idx >= 0) _iconIdx = idx;
    }

    // Pre-fill group currency
    _defaultCurrency = widget.group.defaultCurrency;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Color get _accentColor =>
      _customColor ?? _kGroupPalette[_colorIdx].accent;

  Future<void> _pickAvatar() async {
    if (kIsWeb) return;
    HapticUtils.lightTap();
    final hasAvatar =
        _avatarLocalPath != null || (widget.group.avatarUrl != null && _removeAvatar != true);
    final source = await showModalBottomSheet<ImageSource?>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from Gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('Take a Photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            if (hasAvatar)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Remove Photo',
                    style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _avatarLocalPath = null;
                    _removeAvatar = true;
                  });
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
      setState(() {
        _avatarLocalPath = picked.path;
        _removeAvatar = false;
      });
    } catch (e) {
      debugPrint('[EditGroup] avatar pick failed: $e');
    }
  }

  Future<void> _openColorPicker() async {
    HapticUtils.selection();
    Color? picked = await showDialog<Color>(
      context: context,
      builder: (ctx) => _ColorPickerDialog(initial: _accentColor),
    );
    if (picked != null && mounted) {
      setState(() {
        _customColor = picked;
      });
    }
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Group name cannot be empty')));
      return;
    }
    setState(() => _saving = true);
    HapticUtils.primaryTap();

    final repo     = ref.read(setAllRepositoryProvider);
    final groupId  = widget.group.id;
    final iconName = _kGroupIcons[_iconIdx].name;
    final colorVal = _accentColor.toARGB32();

    String? avatarUrl = widget.group.avatarUrl;

    // Handle avatar changes
    if (_avatarLocalPath != null) {
      final path = await repo.uploadGroupAvatar(groupId, _avatarLocalPath!);
      if (path != null) avatarUrl = path;
    } else if (_removeAvatar == true) {
      avatarUrl = null;
    }

    // Rename if changed
    if (name != widget.group.name) {
      await repo.renameGroup(groupId, name);
    }

    // Update customization
    await repo.updateGroupCustomization(
      groupId,
      iconName: iconName,
      colorValue: colorVal,
      avatarUrl: avatarUrl,
      clearAvatarUrl: _removeAvatar == true && _avatarLocalPath == null,
      defaultCurrency: _defaultCurrency,
    );

    if (!mounted) return;
    ref.invalidate(myGroupsProvider);
    HapticUtils.success();
    setState(() => _saving = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Group updated')));
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme     = Theme.of(context);
    final accent    = _accentColor;
    final iconEntry = _kGroupIcons[_iconIdx];
    final hasAvatar = _avatarLocalPath != null ||
        (widget.group.avatarUrl != null && _removeAvatar != true);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Edit Group',
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
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              children: [

                // ── Avatar preview ─────────────────────────────────────────
                _SectionLabel('Group Appearance', theme),
                const SizedBox(height: 10),
                Center(
                  child: GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: accent.withAlpha(40),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: accent.withValues(alpha: 0.4),
                              width: 2,
                            ),
                          ),
                          child: _buildAvatarContent(
                              accent, iconEntry, hasAvatar),
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

                // ── Colour picker ──────────────────────────────────────────
                _SectionLabel('Colour', theme),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      ...List.generate(_kGroupPalette.length, (i) {
                        final c = _kGroupPalette[i];
                        final selected =
                            _customColor == null && i == _colorIdx;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () {
                              HapticUtils.selection();
                              setState(() {
                                _colorIdx    = i;
                                _customColor = null;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: c.accent,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? Colors.white
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                                boxShadow: selected
                                    ? [
                                        BoxShadow(
                                            color: c.accent
                                                .withValues(alpha: 0.5),
                                            blurRadius: 8)
                                      ]
                                    : null,
                              ),
                              child: selected
                                  ? const Icon(Icons.check,
                                      size: 15, color: Colors.white)
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
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: _customColor ?? Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _customColor != null
                                  ? Colors.white
                                  : theme.colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.4),
                              width: _customColor != null ? 2.5 : 1.5,
                            ),
                            boxShadow: _customColor != null
                                ? [
                                    BoxShadow(
                                        color: _customColor!
                                            .withValues(alpha: 0.5),
                                        blurRadius: 8)
                                  ]
                                : null,
                          ),
                          child: Icon(
                            Icons.colorize_outlined,
                            size: 15,
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

                // ── Icon picker ────────────────────────────────────────────
                _SectionLabel('Icon', theme),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: List.generate(_kGroupIcons.length, (i) {
                    final ic       = _kGroupIcons[i];
                    final selected = i == _iconIdx;
                    return GestureDetector(
                      onTap: () {
                        HapticUtils.selection();
                        setState(() {
                          _iconIdx       = i;
                          _avatarLocalPath = null;
                          _removeAvatar    = true;
                        });
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: selected
                              ? accent.withValues(alpha: 0.2)
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected
                                ? accent
                                : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(ic.data,
                            size: 20,
                            color: selected
                                ? accent
                                : theme.colorScheme.onSurfaceVariant),
                      ),
                    );
                  }),
                ),

                const SizedBox(height: 24),

                // ── Group name ─────────────────────────────────────────────
                _SectionLabel('Group Name', theme),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(
                    hintText: 'Group name…',
                    prefixIcon: Icon(Icons.group_outlined),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Group currency ────────────────────────────────────────────
                _SectionLabel('Group Currency', theme),
                const SizedBox(height: 6),
                Text(
                  'Expenses in this group will display totals in this currency.',
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
                ),
                const SizedBox(height: 8),
                _GroupCurrencyPickerButton(
                  value: _defaultCurrency,
                  accent: accent,
                  onChanged: (v) => setState(() => _defaultCurrency = v),
                ),

                const SizedBox(height: 100),
              ],
            ),
          ),

          // ── Save button ─────────────────────────────────────────────────
          Container(
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, MediaQuery.paddingOf(context).bottom + 16),
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              border: Border(
                top: BorderSide(
                    color: theme.colorScheme.outlineVariant, width: 0.5),
              ),
            ),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(
                _saving ? 'Saving…' : 'Save Changes',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvatarContent(Color accent, _GI iconEntry, bool hasAvatar) {
    if (_avatarLocalPath != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Image.file(
          io.File(_avatarLocalPath!),
          fit: BoxFit.cover,
        ),
      );
    }
    if (widget.group.avatarUrl != null && _removeAvatar != true) {
      return _NetworkAvatar(storagePath: widget.group.avatarUrl!, accent: accent);
    }
    return Icon(iconEntry.data, size: 36, color: accent);
  }
}

// ---------------------------------------------------------------------------
// Network avatar (signed URL via repository)
// ---------------------------------------------------------------------------
class _NetworkAvatar extends ConsumerWidget {
  const _NetworkAvatar({required this.storagePath, required this.accent});
  final String storagePath;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final urlAsync = ref.watch(_groupAvatarUrlProvider(storagePath));
    return urlAsync.when(
      data: (url) => url != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Image.network(url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Icon(
                      Icons.groups_outlined,
                      size: 36,
                      color: accent)),
            )
          : Icon(Icons.groups_outlined, size: 36, color: accent),
      loading: () => const Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2))),
      error: (_, _) => Icon(Icons.groups_outlined, size: 36, color: accent),
    );
  }
}

final _groupAvatarUrlProvider =
    FutureProvider.family<String?, String>((ref, storagePath) async {
  return ref
      .watch(setAllRepositoryProvider)
      .generateGroupAvatarSignedUrl(storagePath);
});

// ---------------------------------------------------------------------------
// Custom colour picker dialog
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
      title: const Text('Pick a colour', style: TextStyle(fontSize: 16)),
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
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: c,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: sel ? Colors.white : Colors.transparent,
                        width: 2.5,
                      ),
                      boxShadow: sel
                          ? [BoxShadow(
                              color: c.withValues(alpha: 0.6), blurRadius: 6)]
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
                  width: 32,
                  height: 32,
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
                    fontSize: 12,
                    fontFamily: 'monospace',
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
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section label helper
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
// Currency picker (Edit group screen)
// ---------------------------------------------------------------------------
const _kEditCurrencies = [
  'USD', 'EUR', 'GBP', 'JPY', 'CNY', 'INR', 'AUD', 'CAD', 'CHF', 'KRW',
  'SGD', 'HKD', 'SEK', 'NOK', 'DKK', 'NZD', 'MXN', 'BRL', 'ZAR', 'RUB',
  'TRY', 'AED', 'SAR', 'THB', 'IDR', 'MYR', 'PHP', 'VND', 'PLN', 'HUF',
  'CZK', 'ILS', 'CLP', 'PKR', 'EGP', 'NGN', 'UAH', 'GEL', 'RON', 'ARS',
];

class _GroupCurrencyPickerButton extends StatelessWidget {
  const _GroupCurrencyPickerButton({
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
                value ?? 'Use my default currency',
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
      builder: (_) => _GroupCurrencyPickerSheet(current: value),
    );
    if (picked != null) onChanged(picked);
  }
}

class _GroupCurrencyPickerSheet extends StatefulWidget {
  const _GroupCurrencyPickerSheet({required this.current});
  final String? current;

  @override
  State<_GroupCurrencyPickerSheet> createState() =>
      _GroupCurrencyPickerSheetState();
}

class _GroupCurrencyPickerSheetState
    extends State<_GroupCurrencyPickerSheet> {
  final _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final filtered = _kEditCurrencies
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
                decoration: const InputDecoration(
                  hintText: 'Search currency (e.g. EUR, GEL…)',
                  prefixIcon: Icon(Icons.search, size: 18),
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

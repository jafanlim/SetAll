import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/providers/theme_mode_provider.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/biometric_service.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/profile_model.dart';

const _teal = Color(0xFF00D9B0);
const _tealDim = Color(0x2600D9B0);

// ---------------------------------------------------------------------------
// Grace period options (seconds)
// ---------------------------------------------------------------------------
const List<({int seconds, String label})> kGracePeriodOptions = [
  (seconds: 0,   label: 'Immediately'),
  (seconds: 30,  label: '30 seconds'),
  (seconds: 60,  label: '1 minute'),
  (seconds: 300, label: '5 minutes'),
];
const String _kGracePeriodKey = 'setall_biometric_grace_seconds';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // ── Profile fields ──────────────────────────────────────────────────────
  final _nameCtrl     = TextEditingController();
  final _nicknameCtrl = TextEditingController();
  bool _profileSaving = false;
  String? _profileError;
  bool _profileSaved = false;
  String? _localAvatarPath; // path of newly picked image (before upload)
  bool _avatarUploading = false;

  // ── Currency ────────────────────────────────────────────────────────────
  String? _selectedCurrency;
  bool _currencySaving = false;

  // ── Biometric ───────────────────────────────────────────────────────────
  bool _biometricAvailable = false;
  bool _biometricEnabled   = false;
  int  _gracePeriodSeconds = 30;
  bool _biometricLoading   = true;

  @override
  void initState() {
    super.initState();
    _loadBiometricSettings();
    // Seed controllers from a cached profile immediately (no wait for first frame).
    // ref.read is safe in initState for ConsumerStatefulWidget.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final cached = ref.read(currentProfileProvider).valueOrNull;
      if (cached != null) _seedFromProfile(cached);
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _nicknameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBiometricSettings() async {
    final bio = BiometricService.instance;
    final available = await bio.canUseBiometrics();
    final enabled   = await bio.getUseBiometric();
    final prefs     = await SharedPreferences.getInstance();
    final grace     = prefs.getInt(_kGracePeriodKey) ?? 30;
    if (mounted) {
      setState(() {
        _biometricAvailable  = available;
        _biometricEnabled    = enabled;
        _gracePeriodSeconds  = grace;
        _biometricLoading    = false;
      });
    }
  }

  void _seedFromProfile(ProfileModel profile) {
    if (_nameCtrl.text.isEmpty) {
      _nameCtrl.text = profile.name;
    }
    if (_nicknameCtrl.text.isEmpty) {
      _nicknameCtrl.text = profile.nickname ?? '';
    }
    _selectedCurrency ??= profile.defaultCurrency;
  }

  Future<void> _saveProfile() async {
    final name     = _nameCtrl.text.trim();
    final nickname = _nicknameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _profileError = 'Name cannot be empty');
      return;
    }
    setState(() { _profileSaving = true; _profileError = null; _profileSaved = false; });
    HapticUtils.primaryTap();
    try {
      await ref.read(setAllRepositoryProvider).updateProfile(
        name: name,
        nickname: nickname.isEmpty ? '' : nickname,
      );
      if (!mounted) return;
      ref.invalidate(currentProfileProvider);
      HapticUtils.success();
      setState(() { _profileSaved = true; _profileSaving = false; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _profileError  = 'Could not save. Check your connection.';
        _profileSaving = false;
      });
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    final picker = ImagePicker();
    final XFile? picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked == null) return;

    setState(() { _localAvatarPath = picked.path; _avatarUploading = true; });
    HapticUtils.primaryTap();

    try {
      final client = Supabase.instance.client;
      final uid = client.auth.currentUser?.id;
      if (uid == null) throw Exception('Not authenticated');

      final bytes = await File(picked.path).readAsBytes();
      // Normalise extension: iOS sometimes gives HEIC; convert to jpeg mime.
      final rawExt  = picked.path.split('.').last.toLowerCase();
      final ext     = (rawExt == 'heic' || rawExt == 'heif') ? 'jpg' : rawExt;
      // Path inside the 'avatars' bucket: one file per user, always replaced.
      final storagePath = '$uid.$ext';

      await client.storage.from('avatars').uploadBinary(
        storagePath,
        bytes,
        fileOptions: FileOptions(
          contentType: 'image/$ext',
          upsert: true,
        ),
      );

      final publicUrl = client.storage.from('avatars').getPublicUrl(storagePath);

      await ref.read(setAllRepositoryProvider).updateProfile(avatarUrl: publicUrl);
      ref.invalidate(currentProfileProvider);
      HapticUtils.success();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not upload photo: ${e.toString()}'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _avatarUploading = false);
    }
  }

  Future<void> _saveCurrency(String code) async {
    setState(() { _currencySaving = true; _selectedCurrency = code; });
    HapticUtils.selection();
    try {
      await ref.read(setAllRepositoryProvider).updateProfile(defaultCurrency: code);
      ref.invalidate(currentProfileProvider);
      ref.invalidate(baseCurrencyProvider);
      ref.invalidate(balanceSummaryProvider);
      HapticUtils.success();
    } catch (_) {} finally {
      if (mounted) setState(() => _currencySaving = false);
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    final bio = BiometricService.instance;
    if (value) {
      final ok = await bio.authenticate(reason: 'Confirm Face ID / Touch ID to enable');
      if (!ok) return;
    }
    await bio.setUseBiometric(value);
    if (mounted) setState(() => _biometricEnabled = value);
    HapticUtils.success();
  }

  Future<void> _setGracePeriod(int seconds) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kGracePeriodKey, seconds);
    if (mounted) setState(() => _gracePeriodSeconds = seconds);
    HapticUtils.selection();
  }

  Future<void> _signOut() async {
    HapticUtils.primaryTap();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {}
    if (mounted) context.go(AppRouter.login);
  }

  @override
  Widget build(BuildContext context) {
    final theme        = Theme.of(context);
    final profileAsync = ref.watch(currentProfileProvider);

    // Seed when data arrives (async load or after invalidation+reload).
    profileAsync.whenData((p) { if (p != null) _seedFromProfile(p); });

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16.sp),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () { HapticUtils.lightTap(); context.pop(); },
        ),
      ),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        children: [
          // ── Profile ─────────────────────────────────────────────────────
          _SectionHeader(label: 'Profile'),
          SizedBox(height: 8.h),
          profileAsync.when(
            data: (profile) => _ProfileSection(
              nameCtrl:         _nameCtrl,
              nicknameCtrl:     _nicknameCtrl,
              profile:          profile,
              saving:           _profileSaving,
              saved:            _profileSaved,
              error:            _profileError,
              onSave:           _saveProfile,
              localAvatarPath:  _localAvatarPath,
              avatarUploading:  _avatarUploading,
              onPickAvatar:     _pickAndUploadAvatar,
            ),
            loading: () => const Center(child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )),
            error: (_, _) => Text(
              'Could not load profile',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),

          SizedBox(height: 24.h),

          // ── Base Currency ────────────────────────────────────────────────
          _SectionHeader(label: 'Base Currency'),
          Text(
            'All dashboard totals are displayed in this currency.',
            style: TextStyle(
              fontSize: 12.sp,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 10.h),
          _CurrencyDropdown(
            selected:   _selectedCurrency ?? 'USD',
            saving:     _currencySaving,
            onSelected: _saveCurrency,
          ),

          SizedBox(height: 24.h),

          // ── Security ─────────────────────────────────────────────────────
          _SectionHeader(label: 'Security'),
          SizedBox(height: 8.h),
          GlassCard(
            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
            child: Column(
              children: [
                if (_biometricLoading)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(),
                  )
                else if (!_biometricAvailable)
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 12.h),
                    child: Row(
                      children: [
                        Icon(Icons.fingerprint,
                            color: theme.colorScheme.onSurfaceVariant),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Text(
                            'Biometrics not available on this device.',
                            style: TextStyle(
                              fontSize: 13.sp,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      'Face ID / Touch ID',
                      style: TextStyle(
                        fontSize: 14.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      'Require biometric unlock when opening the app.',
                      style: TextStyle(
                        fontSize: 11.sp,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: _biometricEnabled,
                    activeThumbColor: _teal,
                    onChanged: _toggleBiometric,
                  ),
                  if (_biometricEnabled) ...[
                    Divider(height: 1.h, indent: 0, endIndent: 0),
                    Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.h),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Grace Period',
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Skip Face ID if app was closed less than this long ago.',
                            style: TextStyle(
                              fontSize: 11.sp,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          SizedBox(height: 8.h),
                          Wrap(
                            spacing: 8.w,
                            children: kGracePeriodOptions.map((opt) {
                              final active = _gracePeriodSeconds == opt.seconds;
                              return ChoiceChip(
                                label: Text(opt.label),
                                selected: active,
                                selectedColor: _tealDim,
                                labelStyle: TextStyle(
                                  color: active ? _teal : theme.colorScheme.onSurface,
                                  fontWeight: active
                                      ? FontWeight.w700
                                      : FontWeight.w400,
                                  fontSize: 12.sp,
                                ),
                                onSelected: (_) => _setGracePeriod(opt.seconds),
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ],
            ),
          ),

          SizedBox(height: 24.h),

          // ── Appearance ───────────────────────────────────────────────────
          _SectionHeader(label: 'Appearance'),
          SizedBox(height: 8.h),
          _ThemeSection(),

          SizedBox(height: 24.h),

          // ── Account ──────────────────────────────────────────────────────
          _SectionHeader(label: 'Account'),
          SizedBox(height: 8.h),
          GlassCard(
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title: const Text(
                'Sign out',
                style: TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: _signOut,
            ),
          ),

          SizedBox(height: 32.h),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Profile section
// ---------------------------------------------------------------------------
class _ProfileSection extends StatelessWidget {
  const _ProfileSection({
    required this.nameCtrl,
    required this.nicknameCtrl,
    required this.profile,
    required this.saving,
    required this.saved,
    required this.error,
    required this.onSave,
    required this.onPickAvatar,
    this.localAvatarPath,
    this.avatarUploading = false,
  });

  final TextEditingController nameCtrl;
  final TextEditingController nicknameCtrl;
  final ProfileModel? profile;
  final bool saving;
  final bool saved;
  final String? error;
  final VoidCallback onSave;
  final VoidCallback onPickAvatar;
  final String? localAvatarPath;
  final bool avatarUploading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final initials = profile?.displayInitial ?? '?';
    final remoteUrl = profile?.avatarUrl;

    // Determine what to show in the avatar circle
    ImageProvider? avatarImage;
    if (localAvatarPath != null) {
      avatarImage = FileImage(File(localAvatarPath!));
    } else if (remoteUrl != null && remoteUrl.isNotEmpty) {
      avatarImage = NetworkImage(remoteUrl);
    }

    return GlassCard(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // ── Avatar with upload button ──────────────────────────────
              GestureDetector(
                onTap: avatarUploading ? null : onPickAvatar,
                child: Stack(
                  children: [
                    Container(
                      width: 64.w,
                      height: 64.w,
                      decoration: BoxDecoration(
                        gradient: avatarImage == null
                            ? const LinearGradient(
                                colors: [_teal, Color(0xFF00A896)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              )
                            : null,
                        image: avatarImage != null
                            ? DecorationImage(
                                image: avatarImage,
                                fit: BoxFit.cover,
                              )
                            : null,
                        borderRadius: BorderRadius.circular(18.r),
                      ),
                      child: avatarImage == null
                          ? Center(
                              child: Text(
                                initials,
                                style: TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 22.sp,
                                ),
                              ),
                            )
                          : null,
                    ),
                    // Upload progress overlay
                    if (avatarUploading)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(18.r),
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    // Camera badge
                    if (!avatarUploading)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          width: 22.w,
                          height: 22.w,
                          decoration: BoxDecoration(
                            color: _teal,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.surface,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            Icons.camera_alt,
                            size: 11.sp,
                            color: Colors.black,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              SizedBox(width: 14.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.name ?? '',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15.sp,
                      ),
                    ),
                    if (profile?.nickname != null)
                      Text(
                        '@${profile!.nickname}',
                        style: TextStyle(fontSize: 12.sp, color: _teal),
                      ),
                    SizedBox(height: 4.h),
                    GestureDetector(
                      onTap: avatarUploading ? null : onPickAvatar,
                      child: Text(
                        avatarUploading ? 'Uploading…' : 'Change photo',
                        style: TextStyle(
                          fontSize: 11.sp,
                          color: avatarUploading
                              ? theme.colorScheme.onSurfaceVariant
                              : _teal,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Text(
            'Display Name',
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 6.h),
          TextField(
            controller: nameCtrl,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              hintText: 'Your name',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          SizedBox(height: 12.h),
          Text(
            'Nickname (optional)',
            style: TextStyle(
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          SizedBox(height: 6.h),
          TextField(
            controller: nicknameCtrl,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSave(),
            decoration: const InputDecoration(
              hintText: 'yourhandle (no @)',
              prefixIcon: Icon(Icons.alternate_email),
            ),
          ),
          if (error != null) ...[
            SizedBox(height: 8.h),
            Text(
              error!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12.sp),
            ),
          ],
          if (saved) ...[
            SizedBox(height: 8.h),
            Row(
              children: [
                Icon(Icons.check_circle_outline, color: _teal, size: 14.sp),
                SizedBox(width: 6.w),
                Text('Saved', style: TextStyle(color: _teal, fontSize: 12.sp)),
              ],
            ),
          ],
          SizedBox(height: 14.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: saving ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.black,
              ),
              child: saving
                  ? SizedBox(
                      height: 16.h,
                      width: 16.w,
                      child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : Text(
                      'Save Profile',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.sp,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Currency dropdown
// ---------------------------------------------------------------------------
class _CurrencyDropdown extends StatelessWidget {
  const _CurrencyDropdown({
    required this.selected,
    required this.saving,
    required this.onSelected,
  });

  final String selected;
  final bool saving;
  final ValueChanged<String> onSelected;

  // Build ordered list: most-used first (deduped), then remaining.
  static List<Map<String, String>> get _orderedCurrencies {
    final mostUsedCodes = kMostUsedCurrencies.map((c) => c['code']!).toSet();
    final rest = kAllSupportedCurrencies
        .where((c) => !mostUsedCodes.contains(c['code']))
        .toList();
    return [...kMostUsedCurrencies, ...rest];
  }

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final ordered  = _orderedCurrencies;
    final selected = this.selected;

    return GlassCard(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
      child: saving
          ? Padding(
              padding: EdgeInsets.symmetric(vertical: 14.h),
              child: const Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          : DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: ordered.any((c) => c['code'] == selected)
                    ? selected
                    : ordered.first['code'],
                isExpanded: true,
                icon: const Icon(Icons.expand_more),
                borderRadius: BorderRadius.circular(12.r),
                onChanged: saving
                    ? null
                    : (code) {
                        if (code != null) onSelected(code);
                      },
                selectedItemBuilder: (context) => ordered
                    .map((c) => Align(
                          alignment: Alignment.centerLeft,
                          child: Row(
                            children: [
                              Text(c['flag']!, style: TextStyle(fontSize: 18.sp)),
                              SizedBox(width: 10.w),
                              Text(
                                '${c['code']!}  —  ${c['name']!}',
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ))
                    .toList(),
                items: ordered.map((c) {
                  final isSelected = c['code'] == selected;
                  return DropdownMenuItem<String>(
                    value: c['code'],
                    child: Row(
                      children: [
                        Text(c['flag']!, style: TextStyle(fontSize: 18.sp)),
                        SizedBox(width: 10.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                c['code']!,
                                style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? _teal
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                c['name']!,
                                style: TextStyle(
                                  fontSize: 11.sp,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle, color: _teal, size: 14.sp),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Theme section
// ---------------------------------------------------------------------------
class _ThemeSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return GlassCard(
      padding: EdgeInsets.symmetric(vertical: 4.h),
      child: Column(
        children: [
          _ThemeTile(
            icon: Icons.dark_mode_outlined,
            label: 'Dark',
            active: themeMode == ThemeMode.dark,
            onTap: () {
              ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
              HapticUtils.success();
            },
          ),
          _ThemeTile(
            icon: Icons.light_mode_outlined,
            label: 'Light',
            active: themeMode == ThemeMode.light,
            onTap: () {
              ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);
              HapticUtils.success();
            },
          ),
          _ThemeTile(
            icon: Icons.brightness_auto_outlined,
            label: 'System default',
            active: themeMode == ThemeMode.system,
            onTap: () {
              ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.system);
              HapticUtils.success();
            },
          ),
        ],
      ),
    );
  }
}

class _ThemeTile extends StatelessWidget {
  const _ThemeTile({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(icon,
          color: active ? _teal : theme.colorScheme.onSurfaceVariant,
          size: 20.sp),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          color: active ? _teal : theme.colorScheme.onSurface,
          fontSize: 13.sp,
        ),
      ),
      trailing: active
          ? Icon(Icons.check, color: _teal, size: 16.sp)
          : null,
      onTap: onTap,
    );
  }
}

// ---------------------------------------------------------------------------
// Shared helpers
// ---------------------------------------------------------------------------
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: 2.h),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11.sp,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

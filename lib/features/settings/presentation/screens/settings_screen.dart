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
import '../../../../core/services/biometric_service.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/profile_model.dart';
import '../../../../data/local/local_database.dart';

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

  // ── Email ────────────────────────────────────────────────────────────────
  String? _currentEmail;
  bool _emailChanging = false;

  // ── Password ─────────────────────────────────────────────────────────────
  bool _passwordChanging = false;

  // ── Currency ────────────────────────────────────────────────────────────
  String? _selectedCurrency;
  bool _currencySaving = false;
  bool _currencyUserSelected = false; // true once user explicitly picks a value

  // ── Biometric ───────────────────────────────────────────────────────────
  bool _biometricAvailable = false;
  bool _biometricEnabled   = false;
  int  _gracePeriodSeconds = 30;
  bool _biometricLoading   = true;

  @override
  void initState() {
    super.initState();
    _loadBiometricSettings();
    _currentEmail = Supabase.instance.client.auth.currentUser?.email;
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
    if (!_currencyUserSelected) _selectedCurrency = profile.defaultCurrency;
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
      // Show the actual DB error (e.g. nickname already taken) not a generic message.
      final msg = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _profileError  = msg.contains('duplicate') || msg.contains('unique')
            ? 'That nickname is already taken.'
            : msg.contains('network') || msg.contains('socket')
                ? 'Could not save. Check your connection.'
                : msg;
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

  /// Returns true when the current user has a password-based identity
  /// (i.e. they signed up with email+password, not Google-only).
  bool get _hasPasswordIdentity {
    final identities =
        Supabase.instance.client.auth.currentUser?.identities ?? [];
    return identities.any((i) => i.provider == 'email');
  }

  Future<void> _showSetPasswordDialog() async {
    final newPwCtrl    = TextEditingController();
    final confirmCtrl  = TextEditingController();
    final formKey      = GlobalKey<FormState>();
    bool obscureNew    = true;
    bool obscureConf   = true;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: Text(_hasPasswordIdentity ? 'Change Password' : 'Set Password'),
          content: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                if (!_hasPasswordIdentity)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      'Add a password so you can also sign in with email + password.',
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                TextFormField(
                  controller: newPwCtrl,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: 'New password (min 8 characters)',
                    suffixIcon: IconButton(
                      icon: Icon(obscureNew
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setDlg(() => obscureNew = !obscureNew),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Enter a password';
                    if (v.length < 8) return 'Use at least 8 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: confirmCtrl,
                  obscureText: obscureConf,
                  decoration: InputDecoration(
                    labelText: 'Confirm password',
                    suffixIcon: IconButton(
                      icon: Icon(obscureConf
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () => setDlg(() => obscureConf = !obscureConf),
                    ),
                  ),
                  validator: (v) {
                    if (v != newPwCtrl.text) return 'Passwords do not match';
                    return null;
                  },
                ),
              ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.black,
              ),
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.of(ctx).pop(true);
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );

    final newPassword = newPwCtrl.text;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      newPwCtrl.dispose();
      confirmCtrl.dispose();
    });
    if (confirmed != true || !mounted) return;

    // Capture messenger before any async gap so we never call it on a
    // deactivated context.
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    final isPasswordUser = _hasPasswordIdentity;

    setState(() => _passwordChanging = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isPasswordUser
                ? 'Password updated successfully.'
                : 'Password set! You can now sign in with email + password.',
          ),
          backgroundColor: _teal.withValues(alpha: 0.9),
        ),
      );
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(
        SnackBar(
          content: Text(msg.isNotEmpty ? msg : 'Could not update password.'),
          backgroundColor: errorColor,
        ),
      );
    } finally {
      if (mounted) setState(() => _passwordChanging = false);
    }
  }

  Future<void> _showChangeEmailDialog() async {
    final ctrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Email'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current: ${_currentEmail ?? '—'}',
                style: TextStyle(fontSize: 12.sp, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              SizedBox(height: 12.h),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  hintText: 'New email address',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Send confirmation'),
          ),
        ],
      ),
    );
    final newEmail = ctrl.text.trim().toLowerCase();
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (confirmed != true || !mounted) return;
    if (newEmail.isEmpty || !newEmail.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid email address.')),
      );
      return;
    }
    final messenger  = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    setState(() => _emailChanging = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(email: newEmail),
      );
      if (mounted) setState(() {
        _currentEmail  = newEmail;
        _emailChanging = false;
      });
      messenger.showSnackBar(
        SnackBar(
          content: Text('Confirmation sent to $newEmail. Check your inbox.'),
          backgroundColor: _teal.withValues(alpha: 0.9),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _emailChanging = false);
      final msg = e.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(
        SnackBar(
          content: Text(msg.isNotEmpty ? msg : 'Could not update email.'),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  Future<void> _saveCurrency(String code) async {
    setState(() { _currencySaving = true; _selectedCurrency = code; _currencyUserSelected = true; });
    HapticUtils.selection();
    try {
      await ref.read(setAllRepositoryProvider).updateProfile(defaultCurrency: code);
      // Invalidate profile + balance providers so the new currency is picked
      // up by baseCurrencyProvider immediately. The _currencyUserSelected flag
      // prevents _seedFromProfile from overwriting the user's selection.
      ref.invalidate(currentProfileProvider);
      ref.invalidate(baseCurrencyProvider);
      ref.invalidate(balanceSummaryProvider);
      HapticUtils.success();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not save currency: ${e.toString().replaceFirst('Exception: ', '')}'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
        // Revert to the last known-good value from the DB, not null
        // (null would cause the ?? 'USD' fallback to show incorrectly).
        final profile = ref.read(currentProfileProvider).valueOrNull;
        if (mounted) setState(() => _selectedCurrency = profile?.defaultCurrency ?? 'USD');
      }
    } finally {
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
          onPressed: () { HapticUtils.lightTap(); context.canPop() ? context.pop() : context.go('/'); },
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
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: Text(
                    _currentEmail ?? '—',
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    'Tap to change email',
                    style: TextStyle(fontSize: 11.sp, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  trailing: _emailChanging
                      ? SizedBox(width: 18.w, height: 18.w, child: const CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.edit_outlined, size: 18.sp, color: theme.colorScheme.onSurfaceVariant),
                  onTap: _emailChanging ? null : _showChangeEmailDialog,
                ),
                Divider(height: 1.h, indent: 16.w, endIndent: 16.w),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(
                    _hasPasswordIdentity ? 'Change Password' : 'Set Password',
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    _hasPasswordIdentity
                        ? 'Update your sign-in password'
                        : 'Add a password to enable email + password login',
                    style: TextStyle(fontSize: 11.sp, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  trailing: _passwordChanging
                      ? SizedBox(width: 18.w, height: 18.w, child: const CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.chevron_right, size: 18.sp, color: theme.colorScheme.onSurfaceVariant),
                  onTap: _passwordChanging ? null : _showSetPasswordDialog,
                ),
                Divider(height: 1.h, indent: 16.w, endIndent: 16.w),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined, color: Colors.orangeAccent),
                  title: const Text(
                    'Clear all expenses',
                    style: TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text('Wipe all expenses & splits from device and cloud'),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear all expenses?'),
                        content: const Text(
                          'This will permanently delete every expense and split from your account. '
                          'Groups and members are kept. This cannot be undone.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              foregroundColor: Colors.black,
                            ),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: const Text('Clear expenses'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !context.mounted) return;
                    await ref.read(setAllRepositoryProvider).clearAllExpenses();
                    ref.invalidate(recentExpensesProvider);
                    ref.invalidate(balanceSummaryProvider);
                    ref.invalidate(myGroupsProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('All expenses cleared')),
                      );
                    }
                  },
                ),
                Divider(height: 1.h, indent: 16.w, endIndent: 16.w),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: const Text(
                    'Sign out',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () async {
                    try {
                      await Supabase.instance.client.auth.signOut();
                      await LocalDatabase.db.delete('splits');
                      await LocalDatabase.db.delete('expenses');
                      await LocalDatabase.db.delete('group_members');
                      await LocalDatabase.db.delete('groups');
                      await LocalDatabase.db.delete('profiles');
                      debugPrint('🧹 Local cache wiped. Clean state for next user.');
                      // Invalidate all cached providers so the next user
                      // never sees data that belonged to the previous session.
                      ref.invalidate(currentProfileProvider);
                      ref.invalidate(myGroupsProvider);
                      ref.invalidate(friendGroupsProvider);
                      ref.invalidate(recentExpensesProvider);
                      ref.invalidate(balanceSummaryProvider);
                      ref.invalidate(baseCurrencyProvider);
                      if (context.mounted) context.go('/login');
                    } catch (e) {
                      debugPrint('❌ Logout Error: $e');
                    }
                  },
                ),
              ],
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

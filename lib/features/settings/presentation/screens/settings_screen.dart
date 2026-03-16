import 'dart:async';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/providers/theme_mode_provider.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/services/update_service.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/local/local_database.dart';
import '../../../../data/models/profile_model.dart';
import 'splitwise_import_screen.dart';

const _teal = Color(0xFF00D9B0);


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

  // ── App version ─────────────────────────────────────────────────────────
  String _appVersion = '';

  // ── Update check ────────────────────────────────────────────────────────
  bool _checkingUpdate = false;
  UpdateCheckResult? _updateResult;

  // ── Email ────────────────────────────────────────────────────────────────
  String? _currentEmail;
  bool _emailChanging = false;

  // ── Password ─────────────────────────────────────────────────────────────
  bool _passwordChanging = false;

  // ── Currency ────────────────────────────────────────────────────────────
  String? _selectedCurrency;
  bool _currencySaving = false;
  bool _currencyUserSelected = false; // true once user explicitly picks a value

  // ── Developer tools ──────────────────────────────────────────────────────
  bool _sendingTestEmail = false;
  String? _testEmailResult;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
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

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = 'v${info.version}');
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
      setState(() => _profileError = 'settings_ext.name_empty'.tr());
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
          content: Text('${'settings_ext.upload_photo_error'.tr()}: ${e.toString()}'),
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
          title: Text(_hasPasswordIdentity ? 'settings_ext.dialog_change_password_title'.tr() : 'settings_ext.dialog_set_password_title'.tr()),
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
                      'settings_ext.dialog_add_password_body'.tr(),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                TextFormField(
                  controller: newPwCtrl,
                  obscureText: obscureNew,
                  decoration: InputDecoration(
                    labelText: 'settings_ext.dialog_new_password_label'.tr(),
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
                    labelText: 'settings_ext.dialog_confirm_password_label'.tr(),
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
              child: Text('common.cancel'.tr()),
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
              child: Text('common.save'.tr()),
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
                ? 'settings_ext.password_updated'.tr()
                : 'settings_ext.password_set'.tr(),
          ),
          backgroundColor: _teal.withValues(alpha: 0.9),
        ),
      );
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(
        SnackBar(
          content: Text(msg.isNotEmpty ? msg : 'settings_ext.could_not_update_password'.tr()),
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
        title: Text('settings_ext.dialog_change_email_title'.tr()),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Current: ${_currentEmail ?? '—'}',
                style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  hintText: 'settings_ext.dialog_new_email_hint'.tr(),
                  prefixIcon: const Icon(Icons.email_outlined),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: _teal, foregroundColor: Colors.black),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text('settings_ext.dialog_send_confirm'.tr()),
          ),
        ],
      ),
    );
    final newEmail = ctrl.text.trim().toLowerCase();
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (confirmed != true || !mounted) return;
    if (newEmail.isEmpty || !newEmail.contains('@')) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('settings_ext.enter_valid_email'.tr())),
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
      if (mounted) {
        setState(() {
          _currentEmail  = newEmail;
          _emailChanging = false;
        });
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('settings_ext.confirmation_sent'.tr(namedArgs: {'email': newEmail})),
          backgroundColor: _teal.withValues(alpha: 0.9),
        ),
      );
    } catch (e) {
      if (mounted) setState(() => _emailChanging = false);
      final msg = e.toString().replaceFirst('Exception: ', '');
      messenger.showSnackBar(
        SnackBar(
          content: Text(msg.isNotEmpty ? msg : 'settings_ext.could_not_update_email'.tr()),
          backgroundColor: errorColor,
        ),
      );
    }
  }

  Future<void> _launchUpdateUrl() async {
    HapticUtils.primaryTap();
    String url;
    if (kIsWeb) {
      url = 'https://setall.app/download';
    } else if (defaultTargetPlatform == TargetPlatform.iOS) {
      url = 'https://apps.apple.com/app/setall/id6744063602';
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      url = 'https://setall.app/download';
    } else {
      url = 'https://setall.app/download';
    }
    await UpdateService.instance.openReleasePage(url);
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
            content: Text('settings_ext.could_not_save_currency'.tr(namedArgs: {'error': e.toString().replaceFirst('Exception: ', '')})),
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

  Future<void> _showDeleteAccountDialog() async {
    HapticUtils.primaryTap();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('settings_ext.dialog_delete_account_title'.tr()),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.redAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'settings_ext.dialog_cooling_period'.tr(),
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.redAccent, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'settings_ext.dialog_delete_account_body'.tr(),
              style: const TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('settings_ext.dialog_delete_my_account'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final messenger  = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    try {
      final client = Supabase.instance.client;
      final result = await client.rpc('delete_user_data') as Map<String, dynamic>?;
      if (result != null && result['success'] != true) {
        throw Exception(result['error'] ?? 'Deletion failed');
      }
      // Wipe local cache
      await LocalDatabase.db.delete('splits');
      await LocalDatabase.db.delete('expenses');
      await LocalDatabase.db.delete('group_members');
      await LocalDatabase.db.delete('groups');
      await LocalDatabase.db.delete('profiles');
      await client.auth.signOut();
    } catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text('settings_ext.error_generic'.tr(namedArgs: {'error': e.toString()})),
        backgroundColor: errorColor,
      ));
    }
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
          'settings.title'.tr(),
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        children: [
          // ── Profile ─────────────────────────────────────────────────────
          _SectionHeader(label: 'settings_ext.profile'.tr()),
          const SizedBox(height: 8),
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
              'settings_ext.could_not_load_profile'.tr(),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),

          const SizedBox(height: 24),

          // ── Base Currency ────────────────────────────────────────────────
          _SectionHeader(label: 'settings.currency'.tr()),
          Text(
            'settings_ext.base_currency_subtitle'.tr(),
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          _CurrencyDropdown(
            selected:   _selectedCurrency ?? 'USD',
            saving:     _currencySaving,
            onSelected: _saveCurrency,
          ),

          const SizedBox(height: 24),

          // ── Sub-menus ─────────────────────────────────────────────────────
          _SectionHeader(label: 'settings.preferences'.tr()),
          const SizedBox(height: 8),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                _NavRow(
                  icon: LucideIcons.shieldCheck,
                  iconColor: _teal,
                  label: 'settings_ext.security'.tr(),
                  subtitle: 'settings_ext.security_subtitle'.tr(),
                  onTap: () => context.push(AppRouter.settingsSecurity),
                ),
                const Divider(height: 1, indent: 56, endIndent: 0),
                _NavRow(
                  icon: LucideIcons.bell,
                  iconColor: _teal,
                  label: 'settings_ext.notifications'.tr(),
                  subtitle: 'settings_ext.notifications_subtitle'.tr(),
                  onTap: () => context.push(AppRouter.settingsNotifications),
                ),
                const Divider(height: 1, indent: 56, endIndent: 0),
                _NavRow(
                  icon: LucideIcons.globe,
                  iconColor: _teal,
                  label: 'settings_ext.regional'.tr(),
                  subtitle: 'settings_ext.regional_subtitle'.tr(),
                  onTap: () => context.push(AppRouter.settingsRegional),
                ),
                const Divider(height: 1, indent: 56, endIndent: 0),
                _LanguageRow(),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── Splitwise Import ─────────────────────────────────────────────
          _SectionHeader(label: 'settings_ext.data'.tr()),
          const SizedBox(height: 8),
          GlassCard(
            padding: EdgeInsets.zero,
            child: _NavRow(
              icon: LucideIcons.fileUp,
              iconColor: const Color(0xFF22C55E),
              label: 'settings_ext.import_splitwise'.tr(),
              subtitle: 'settings_ext.import_splitwise_subtitle'.tr(),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const SplitwiseImportScreen()),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // ── Appearance ───────────────────────────────────────────────────
          _SectionHeader(label: 'settings.appearance'.tr()),
          const SizedBox(height: 8),
          _ThemeSection(),

          const SizedBox(height: 24),

          // ── Account ──────────────────────────────────────────────────────
          _SectionHeader(label: 'settings.account'.tr()),
          const SizedBox(height: 8),
          GlassCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.email_outlined),
                  title: Text(
                    _currentEmail ?? '—',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    'settings_ext.tap_change_email'.tr(),
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  trailing: _emailChanging
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.edit_outlined, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  onTap: _emailChanging ? null : _showChangeEmailDialog,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.lock_outline),
                  title: Text(
                    _hasPasswordIdentity ? 'settings_ext.change_password'.tr() : 'settings_ext.set_password'.tr(),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    _hasPasswordIdentity
                        ? 'settings_ext.change_password_subtitle'.tr()
                        : 'settings_ext.set_password_subtitle'.tr(),
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  trailing: _passwordChanging
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(Icons.chevron_right, size: 18, color: theme.colorScheme.onSurfaceVariant),
                  onTap: _passwordChanging ? null : _showSetPasswordDialog,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.delete_sweep_outlined, color: Colors.orangeAccent),
                  title: Text(
                    'settings_ext.clear_expenses'.tr(),
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text('settings_ext.clear_expenses_subtitle'.tr()),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('settings_ext.dialog_clear_expenses_title'.tr()),
                        content: Text(
                          'settings_ext.dialog_clear_expenses_body'.tr(),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text('common.cancel'.tr()),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              foregroundColor: Colors.black,
                            ),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: Text('settings_ext.dialog_clear_expenses_confirm'.tr()),
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
                        SnackBar(content: Text('settings_ext.expenses_cleared'.tr())),
                      );
                    }
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.refresh, color: Colors.orangeAccent),
                  title: Text(
                    'settings_ext.reset_cache'.tr(),
                    style: const TextStyle(
                      color: Colors.orangeAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'settings_ext.reset_cache_subtitle'.tr(),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text('settings_ext.dialog_reset_cache_title'.tr()),
                        content: Text(
                          'settings_ext.dialog_reset_cache_body'.tr(),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(ctx).pop(false),
                            child: Text('common.cancel'.tr()),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Colors.orangeAccent,
                              foregroundColor: Colors.black,
                            ),
                            onPressed: () => Navigator.of(ctx).pop(true),
                            child: Text('settings_ext.dialog_reset_sync'.tr()),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true || !context.mounted) return;
                    try {
                      await LocalDatabase.db.delete('splits');
                      await LocalDatabase.db.delete('expenses');
                      await LocalDatabase.db.delete('group_members');
                      await LocalDatabase.db.delete('groups');
                      await LocalDatabase.db.delete('profiles');
                      await ref.read(syncServiceProvider).performFullSync();
                      ref.invalidate(myGroupsProvider);
                      ref.invalidate(balanceSummaryProvider);
                      ref.invalidate(recentExpensesProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('settings_ext.cache_reset_success'.tr())),
                        );
                      }
                    } catch (e) {
                      debugPrint('Reset Local Cache error: $e');
                    }
                  },
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.person_remove_outlined, color: Colors.redAccent),
                  title: Text(
                    'settings_ext.delete_account'.tr(),
                    style: const TextStyle(color: Colors.redAccent, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'settings_ext.delete_account_subtitle'.tr(),
                    style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
                  ),
                  onTap: _showDeleteAccountDialog,
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.logout, color: Colors.redAccent),
                  title: Text(
                    'settings.sign_out'.tr(),
                    style: const TextStyle(
                      color: Colors.redAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  onTap: () async {
                    // Best-effort sync: push pending writes but never let it
                    // block sign-out (3 s cap covers slow / offline Windows).
                    try {
                      await ref
                          .read(syncServiceProvider)
                          .performFullSync()
                          .timeout(const Duration(seconds: 3));
                    } catch (_) {}

                    // Wipe SQLite BEFORE signOut so the auth-state listener
                    // never races with the delete and re-populates the cache.
                    try {
                      await LocalDatabase.db.delete('splits');
                      await LocalDatabase.db.delete('expenses');
                      await LocalDatabase.db.delete('group_members');
                      await LocalDatabase.db.delete('groups');
                      await LocalDatabase.db.delete('profiles');
                    } catch (e) {
                      debugPrint('❌ Logout wipe error: $e');
                    }

                    try {
                      await Supabase.instance.client.auth.signOut();
                      // _AuthRefresh notifies GoRouter → redirects to /login.
                      // Do NOT call context.go here — double-navigation on
                      // Windows silently no-ops when the widget is already gone.
                    } catch (e) {
                      debugPrint('❌ Logout signOut error: $e');
                      // Force-navigate even if signOut threw (e.g. network error).
                      if (context.mounted) context.go('/login');
                    }
                  },
                ),
              ],
            ),
          ),

                        const SizedBox(height: 24),

                        // ── About / Version ────────────────────────────────
                        _SectionHeader(label: 'settings.about'.tr()),
                        const SizedBox(height: 8),
                        GlassCard(
                          padding: EdgeInsets.zero,
                          child: Column(
                            children: [
                              // Version tile with update badge
                              ListTile(
                                leading: const Icon(Icons.info_outline),
                                title: Row(
                                  children: [
                                    const Text(
                                      'SetAll',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                    ),
                                    if (_updateResult != null && _updateResult!.hasUpdate) ...
                                      [
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: _teal.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(20),
                                            border: Border.all(color: _teal.withValues(alpha: 0.5)),
                                          ),
                                          child: Text(
                                            '${_updateResult!.latestTag} available',
                                            style: const TextStyle(fontSize: 10, color: _teal, fontWeight: FontWeight.w700),
                                          ),
                                        ),
                                      ],
                                  ],
                                ),
                                subtitle: Text(
                                  _appVersion.isEmpty ? 'common.loading'.tr() : '${'settings_ext.version_prefix'.tr()} $_appVersion',
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                                ),
                              ),
                              const Divider(height: 1, indent: 16, endIndent: 16),
                              // Check for updates tile
                              ListTile(
                                leading: _checkingUpdate
                                    ? const SizedBox(width: 20, height: 20,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: _teal))
                                    : const Icon(Icons.system_update_alt_rounded, color: _teal),
                                title: Text(
                                  _updateResult != null && _updateResult!.hasUpdate
                                      ? 'settings_ext.update_available'.tr()
                                      : 'settings_ext.check_updates'.tr(),
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                                subtitle: Text(
                                  _updateResult != null
                                      ? (_updateResult!.hasUpdate
                                          ? 'Tap "Update Now" to get ${_updateResult!.latestTag}'
                                          : 'You\'re up to date ✓')
                                      : 'Tap to check for a new version',
                                  style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                                ),
                                onTap: _checkingUpdate ? null : () async {
                                  HapticUtils.lightTap();
                                  setState(() { _checkingUpdate = true; });
                                  final result = await UpdateService.instance.checkForUpdate();
                                  if (!mounted) return;
                                  setState(() { _checkingUpdate = false; _updateResult = result; });
                                },
                              ),
                              // Update Now button — only shown when update is available
                              if (_updateResult != null && _updateResult!.hasUpdate) ...
                                [
                                  const Divider(height: 1, indent: 16, endIndent: 16),
                                  Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    child: SizedBox(
                                      width: double.infinity,
                                      child: FilledButton.icon(
                                        onPressed: () => _launchUpdateUrl(),
                                        icon: const Icon(Icons.open_in_new, size: 16),
                                        label: Text('settings_ext.update_now'.tr(), style: const TextStyle(fontWeight: FontWeight.w700)),
                                        style: FilledButton.styleFrom(
                                          backgroundColor: _teal,
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                            ],
                          ),
                        ),

                        if (kDebugMode) ...[
                          const SizedBox(height: 24),

                          // ── Developer ───────────────────────────────────
                          _SectionHeader(label: 'settings_ext.developer'.tr()),
                          const SizedBox(height: 8),
                          GlassCard(
                            padding: EdgeInsets.zero,
                            child: Column(
                              children: [
                                ListTile(
                                  leading: _sendingTestEmail
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: _teal,
                                          ),
                                        )
                                      : const Icon(Icons.mail_outline_rounded,
                                          color: _teal),
                                  title: const Text(
                                    'Send Test Email',
                                    style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  subtitle: _testEmailResult != null
                                      ? Text(
                                          _testEmailResult!,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: theme.colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        )
                                      : Text(
                                          'Sends a test email via noreply@setall.app',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: theme.colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                  onTap: _sendingTestEmail
                                      ? null
                                      : () async {
                                          HapticUtils.lightTap();
                                          final email = _currentEmail;
                                          if (email == null || email.isEmpty) {
                                            setState(() => _testEmailResult =
                                                'No email address on account');
                                            return;
                                          }
                                          setState(() {
                                            _sendingTestEmail = true;
                                            _testEmailResult = null;
                                          });
                                          try {
                                            await Supabase.instance.client.functions
                                                .invoke(
                                              'send-test-email',
                                              body: {'to': email},
                                            );
                                            if (!mounted) return;
                                            setState(() {
                                              _sendingTestEmail = false;
                                              _testEmailResult =
                                                  'Sent to $email ✓';
                                            });
                                          } catch (e) {
                                            if (!mounted) return;
                                            setState(() {
                                              _sendingTestEmail = false;
                                              _testEmailResult =
                                                  'Failed: ${e.toString().replaceFirst('Exception: ', '')}';
                                            });
                                          }
                                        },
                                ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 32),
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
      padding: const EdgeInsets.all(16),
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
                      width: 64,
                      height: 64,
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
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: avatarImage == null
                          ? Center(
                              child: Text(
                                initials,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 22,
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
                            borderRadius: BorderRadius.circular(18),
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
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: _teal,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: theme.colorScheme.surface,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 11,
                            color: Colors.black,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile?.name ?? '',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    if (profile?.nickname != null)
                      Text(
                        '@${profile!.nickname}',
                        style: const TextStyle(fontSize: 12, color: _teal),
                      ),
                    const SizedBox(height: 4),
                    GestureDetector(
                      onTap: avatarUploading ? null : onPickAvatar,
                      child: Text(
                        avatarUploading ? 'settings_ext.uploading_photo'.tr() : 'settings_ext.change_photo'.tr(),
                        style: TextStyle(
                          fontSize: 11,
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
          const SizedBox(height: 16),
          Text(
            'settings_ext.display_name'.tr(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: nameCtrl,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              hintText: 'settings_ext.name_hint'.tr(),
              prefixIcon: const Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'settings_ext.nickname_optional'.tr(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: nicknameCtrl,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onSave(),
            decoration: InputDecoration(
              hintText: 'settings_ext.nickname_hint'.tr(),
              prefixIcon: const Icon(Icons.alternate_email),
            ),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 12),
            ),
          ],
          if (saved) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle_outline, color: _teal, size: 14),
                const SizedBox(width: 6),
                Text('settings_ext.saved'.tr(), style: const TextStyle(color: _teal, fontSize: 12)),
              ],
            ),
          ],
          const SizedBox(height: 14),
          ElevatedButton(
              onPressed: saving ? null : onSave,
              style: ElevatedButton.styleFrom(
                backgroundColor: _teal,
                foregroundColor: Colors.black,
              ),
              child: saving
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.black,
                      ),
                    )
                  : const Text(
                      'Save Profile',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      child: saving
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 14),
              child: Center(
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
                borderRadius: BorderRadius.circular(12),
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
                              Text(c['flag']!, style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 10),
                              Text(
                                '${c['code']!}  —  ${c['name']!}',
                                style: TextStyle(
                                  fontSize: 13,
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
                        Text(c['flag']!, style: const TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                c['code']!,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected
                                      ? _teal
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                              Text(
                                c['name']!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(Icons.check_circle, color: _teal, size: 14),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        children: [
          _ThemeTile(
            icon: Icons.dark_mode_outlined,
            label: 'settings_ext.theme_dark'.tr(),
            active: themeMode == ThemeMode.dark,
            onTap: () {
              ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.dark);
              HapticUtils.success();
            },
          ),
          _ThemeTile(
            icon: Icons.light_mode_outlined,
            label: 'settings_ext.theme_light'.tr(),
            active: themeMode == ThemeMode.light,
            onTap: () {
              ref.read(themeModeProvider.notifier).setThemeMode(ThemeMode.light);
              HapticUtils.success();
            },
          ),
          _ThemeTile(
            icon: Icons.brightness_auto_outlined,
            label: 'settings_ext.theme_system'.tr(),
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
          size: 20),
      title: Text(
        label,
        style: TextStyle(
          fontWeight: active ? FontWeight.w700 : FontWeight.w400,
          color: active ? _teal : theme.colorScheme.onSurface,
          fontSize: 13,
        ),
      ),
      trailing: active
          ? const Icon(Icons.check, color: _teal, size: 16)
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
      padding: const EdgeInsets.only(bottom: 2),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Nav row: icon + label + subtitle + chevron
// ---------------------------------------------------------------------------
// ---------------------------------------------------------------------------
// Language row — inline selector that updates locale instantly
// ---------------------------------------------------------------------------
class _LanguageRow extends StatelessWidget {
  static const _langs = [
    (code: 'en', label: 'English'),
    (code: 'ru', label: 'Русский'),
    (code: 'ka', label: 'ქართული'),
    (code: 'de', label: 'Deutsch'),
    (code: 'es', label: 'Español'),
    (code: 'fr', label: 'Français'),
  ];

  @override
  Widget build(BuildContext context) {
    final current = context.locale.languageCode;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _teal.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: const Icon(Icons.language_outlined, color: _teal, size: 18),
      ),
      title: Text('settings.language'.tr(),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(
        _langs.firstWhere((l) => l.code == current,
            orElse: () => _langs.first).label,
        style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
      trailing: Icon(Icons.chevron_right,
          size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
      onTap: () => _showPicker(context, current),
    );
  }

  void _showPicker(BuildContext context, String current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(ctx).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text('settings.language'.tr(),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              ..._langs.map((l) => ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 0),
                title: Text(l.label,
                    style: TextStyle(
                      fontWeight: l.code == current
                          ? FontWeight.w700
                          : FontWeight.w500,
                    )),
                trailing: l.code == current
                    ? const Icon(Icons.check_rounded, color: _teal, size: 20)
                    : null,
                onTap: () {
                  ctx.setLocale(Locale(l.code));
                  Navigator.of(ctx).pop();
                },
              )),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Nav row: icon + label + subtitle + chevron
// ---------------------------------------------------------------------------
class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  final IconData  icon;
  final Color     iconColor;
  final String    label;
  final String    subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: iconColor.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: iconColor, size: 18),
      ),
      title: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle,
          style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
      trailing: Icon(Icons.chevron_right, size: 18,
          color: theme.colorScheme.onSurfaceVariant),
      onTap: () {
        HapticUtils.lightTap();
        onTap();
      },
    );
  }
}

import 'package:shared_preferences/shared_preferences.dart';

/// User preference controlling whether the "mirror my share into wallet"
/// prompt appears after saving a group expense.
enum MirrorSharePreference {
  /// Show the confirm sheet every time (default).
  ask,

  /// Mirror automatically without prompting.
  always,

  /// Never mirror; skip silently.
  never,
}

/// SharedPreferences key for the mirror-share preference.
const _kPrefKey = 'wallet_mirror_share_pref';

/// Reads the stored [MirrorSharePreference], defaulting to [MirrorSharePreference.ask].
Future<MirrorSharePreference> readMirrorSharePref() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_kPrefKey);
  switch (raw) {
    case 'always':
      return MirrorSharePreference.always;
    case 'never':
      return MirrorSharePreference.never;
    default:
      return MirrorSharePreference.ask;
  }
}

/// Persists [pref] so future reads return it without prompting again.
Future<void> writeMirrorSharePref(MirrorSharePreference pref) async {
  final prefs = await SharedPreferences.getInstance();
  final value = switch (pref) {
    MirrorSharePreference.always => 'always',
    MirrorSharePreference.never  => 'never',
    MirrorSharePreference.ask    => 'ask',
  };
  await prefs.setString(_kPrefKey, value);
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _keyThemeMode = 'setall_theme_mode';

/// Persisted theme mode: dark (default), light, or system.
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _load();
  }

  static int _modeToInt(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 1;
      case ThemeMode.system:
        return 2;
      case ThemeMode.dark:
      default:
        return 0;
    }
  }

  static ThemeMode _intToMode(int v) {
    switch (v) {
      case 1:
        return ThemeMode.light;
      case 2:
        return ThemeMode.system;
      default:
        return ThemeMode.dark;
    }
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = _intToMode(prefs.getInt(_keyThemeMode) ?? 0);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyThemeMode, _modeToInt(mode));
  }
}

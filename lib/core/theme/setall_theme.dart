import 'package:flutter/material.dart';

/// SetAll branded dark theme — Material 3, premium cost-sharing aesthetic.
class SetAllTheme {
  SetAllTheme._();

  static const String _fontFamily = 'Roboto';

  // Brand palette: deep charcoal, gold accent, clean neutrals
  static const Color _surfaceDark = Color(0xFF0F0F12);
  static const Color _surfaceVariant = Color(0xFF1A1A1F);
  static const Color _surfaceContainer = Color(0xFF242429);
  static const Color _gold = Color(0xFFD4AF37);
  static const Color _goldDim = Color(0xFF9A8B2E);
  static const Color _outline = Color(0xFF3D3D45);
  static const Color _onSurface = Color(0xFFE8E8EC);
  static const Color _onSurfaceVariant = Color(0xFFB0B0B8);
  static const Color _onGold = Color(0xFF0F0F12);

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: _fontFamily,
      colorScheme: ColorScheme.dark(
        surface: _surfaceDark,
        onSurface: _onSurface,
        surfaceContainerHighest: _surfaceContainer,
        primary: _gold,
        onPrimary: _onGold,
        primaryContainer: _goldDim,
        onPrimaryContainer: _onSurface,
        outline: _outline,
        outlineVariant: _surfaceVariant,
        onSurfaceVariant: _onSurfaceVariant,
      ),
      scaffoldBackgroundColor: _surfaceDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: _surfaceDark,
        foregroundColor: _onSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: _onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: _surfaceVariant,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: _onGold,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceContainer,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _outline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _gold, width: 2),
        ),
        labelStyle: const TextStyle(color: _onSurfaceVariant),
        hintStyle: const TextStyle(color: _onSurfaceVariant),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _gold,
        foregroundColor: _onGold,
      ),
    );
  }

  /// Light theme — same brand, light surfaces.
  static ThemeData get light {
    const Color surfaceLight = Color(0xFFF5F5F7);
    const Color surfaceVariantLight = Color(0xFFE8E8EC);
    const Color surfaceContainerLight = Color(0xFFDEDEE2);
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: _fontFamily,
      colorScheme: ColorScheme.light(
        surface: surfaceLight,
        onSurface: _onGold,
        surfaceContainerHighest: surfaceContainerLight,
        primary: _gold,
        onPrimary: _onGold,
        primaryContainer: _goldDim,
        onPrimaryContainer: Color(0xFF1A1A1F),
        outline: Color(0xFF8E8E93),
        outlineVariant: surfaceVariantLight,
        onSurfaceVariant: Color(0xFF48484A),
      ),
      scaffoldBackgroundColor: surfaceLight,
      appBarTheme: const AppBarTheme(
        backgroundColor: surfaceLight,
        foregroundColor: _onGold,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          fontFamily: _fontFamily,
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Color(0xFF0F0F12),
        ),
      ),
      cardTheme: CardThemeData(
        color: surfaceVariantLight,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: _onGold,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerLight,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF8E8E93)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _gold, width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFF48484A)),
        hintStyle: const TextStyle(color: Color(0xFF8E8E93)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _gold,
        foregroundColor: _onGold,
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// SetAll branded dark theme — Material 3, Outfit font, premium fintech aesthetic.
class SetAllTheme {
  SetAllTheme._();

  static String get _fontFamily => GoogleFonts.outfit().fontFamily!;

  // Brand palette
  static const Color _surfaceDark = Color(0xFF0F172A);       // Slate-900
  static const Color _surfaceVariant = Color(0xFF1E293B);    // Slate-800
  static const Color _surfaceContainer = Color(0xFF334155);  // Slate-700
  static const Color _gold = Color(0xFFD4AF37);
  static const Color _goldDim = Color(0xFF9A8B2E);
  static const Color _outline = Color(0xFF334155);           // Slate-700 border
  static const Color _onSurface = Color(0xFFF1F5F9);         // Slate-100
  static const Color _onSurfaceVariant = Color(0xFF94A3B8);  // Slate-400
  static const Color _onGold = Color(0xFF0F172A);

  // ── TextTheme: Outfit — amounts Bold/700 -1.0ls, headers Bold/700, labels Medium/500 ──
  static const Color _slate500 = Color(0xFF64748B);

  static TextTheme get _outfitTextTheme => GoogleFonts.outfitTextTheme().copyWith(
    // Display — large amount figures
    displayLarge:  GoogleFonts.outfit(fontSize: 45, fontWeight: FontWeight.w700, letterSpacing: -1.0),
    displayMedium: GoogleFonts.outfit(fontSize: 36, fontWeight: FontWeight.w700, letterSpacing: -1.0),
    displaySmall:  GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -1.0),
    // Headlines — screen titles, card headers
    headlineLarge: GoogleFonts.outfit(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5),
    headlineMedium:GoogleFonts.outfit(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.5),
    headlineSmall: GoogleFonts.outfit(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.5),
    // Titles — card titles, section headers
    titleLarge:    GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w700),
    titleMedium:   GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500),
    titleSmall:    GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w500),
    // Body — general text
    bodyLarge:     GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w500),
    bodyMedium:    GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w400),
    bodySmall:     GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w400),
    // Labels — chips, badges, captions
    labelLarge:    GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w500, color: _slate500),
    labelMedium:   GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.w500, color: _slate500),
    labelSmall:    GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.w500, color: _slate500),
  );

  static TextTheme get _compactTextTheme => _outfitTextTheme;

  static ThemeData get desktopDark  => dark.copyWith(
    scaffoldBackgroundColor: const Color(0xFF020617),
    colorScheme: dark.colorScheme.copyWith(surface: const Color(0xFF020617)),
    textTheme: _compactTextTheme.apply(fontFamily: _fontFamily, bodyColor: _onSurface, displayColor: _onSurface),
  );
  static const Color _deskScaffold  = Color(0xFFCBD5E1); // Slate-300
  static const Color _deskCard      = Color(0xFFF1F5F9); // Slate-100
  static const Color _deskBorder    = Color(0xFFE2E8F0); // Slate-200

  static ThemeData get desktopLight {
    final base = light;
    return base.copyWith(
      scaffoldBackgroundColor: _deskScaffold,
      colorScheme: base.colorScheme.copyWith(
        surface:                  _deskScaffold,
        surfaceContainerHighest:  _deskCard,
        outlineVariant:           _deskBorder,
      ),
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: _deskScaffold,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: _deskCard,
      ),
      textTheme: _compactTextTheme.apply(
        fontFamily:   _fontFamily,
        bodyColor:    _onGold,
        displayColor: _onGold,
      ),
    );
  }

  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: _fontFamily,
      colorScheme: ColorScheme.dark(
        surface: _surfaceDark,
        onSurface: _onSurface,
        surfaceContainerHighest: _surfaceVariant,
        primary: _gold,
        onPrimary: _onGold,
        primaryContainer: _goldDim,
        onPrimaryContainer: _onSurface,
        outline: _outline,
        outlineVariant: _surfaceVariant,
        onSurfaceVariant: _onSurfaceVariant,
      ),
      scaffoldBackgroundColor: _surfaceDark,
      appBarTheme: AppBarTheme(
        backgroundColor: _surfaceDark,
        foregroundColor: _onSurface,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: _onSurface,
        ),
      ),
      cardTheme: CardThemeData(
        color: _surfaceVariant,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: _outline, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: _onGold,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          textStyle: GoogleFonts.outfit(
            fontSize: 14, fontWeight: FontWeight.w700),
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
    const Color surfaceLight = Color(0xFFF8FAFC);           // Slate-50
    const Color surfaceVariantLight = Color(0xFFE2E8F0);    // Slate-200
    const Color surfaceContainerLight = Color(0xFFCBD5E1);  // Slate-300
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
        onPrimaryContainer: const Color(0xFF1A1A1F),
        outline: const Color(0xFFCBD5E1),
        outlineVariant: surfaceVariantLight,
        onSurfaceVariant: const Color(0xFF475569),
      ),
      scaffoldBackgroundColor: surfaceLight,
      appBarTheme: AppBarTheme(
        backgroundColor: surfaceLight,
        foregroundColor: _onGold,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF0F172A),
        ),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: surfaceVariantLight, width: 1),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _gold,
          foregroundColor: _onGold,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 0,
          textStyle: GoogleFonts.outfit(
            fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainerLight,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _gold, width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFF475569)),
        hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: _gold,
        foregroundColor: _onGold,
      ),
    );
  }
}

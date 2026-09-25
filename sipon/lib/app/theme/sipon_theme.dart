import 'package:flutter/material.dart';

import 'sipon_theme_colors.dart';

abstract final class SiponTheme {
  static const Color brand = Color(0xFF9A3D78);

  static ThemeData get light => _build(Brightness.light);
  static ThemeData get dark => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(seedColor: brand, brightness: brightness).copyWith(
          primary: isDark ? const Color(0xFFE8A0CC) : brand,
          onPrimary: isDark ? const Color(0xFF42132F) : Colors.white,
          surface: isDark ? const Color(0xFF211C22) : Colors.white,
          onSurface: isDark ? const Color(0xFFF5EFF4) : const Color(0xFF252229),
          onSurfaceVariant: isDark
              ? const Color(0xFFC4B8C2)
              : const Color(0xFF716A72),
          outlineVariant: isDark
              ? const Color(0xFF4A3D48)
              : const Color(0xFFF0E7EE),
          error: isDark ? const Color(0xFFFFB4AB) : const Color(0xFFB3261E),
        );
    final extensions = <ThemeExtension<dynamic>>[
      isDark ? SiponThemeColors.dark : SiponThemeColors.light,
    ];

    return ThemeData(
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark
          ? const Color(0xFF151216)
          : const Color(0xFFFBF8F9),
      canvasColor: scheme.surface,
      cardColor: scheme.surface,
      dividerColor: scheme.outlineVariant,
      useMaterial3: true,
      extensions: extensions,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: CardThemeData(
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF2C252D) : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xFF2C252D) : Colors.white,
        modalBackgroundColor: isDark ? const Color(0xFF2C252D) : Colors.white,
        surfaceTintColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surface,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFFF5EFF4)
            : const Color(0xFF252229),
        contentTextStyle: TextStyle(
          color: isDark ? const Color(0xFF252229) : Colors.white,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Palette inspirée de Messenger (clair).
class AppColors {
  static const bg = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF0F2F5);
  static const surface2 = Color(0xFFE4E6EB);
  static const primary = Color(0xFF0084FF);
  static const cyan = primary; // ancien nom, gardé pour compatibilité
  static const violet = Color(0xFF7C4DFF);
  static const muted = Color(0xFF65676B);
  static const text = Color(0xFF050505);
  static const bubbleTheirs = Color(0xFFF0F0F0);
  static const online = Color(0xFF31A24C);

  static const gradient = LinearGradient(
    colors: [Color(0xFF0099FF), Color(0xFF0084FF)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

ThemeData buildTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.primary,
    onPrimary: Colors.white,
    surface: AppColors.bg,
    onSurface: AppColors.text,
  );

  OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: color, width: 1.2),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.bg,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: AppColors.text,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      border: border(Colors.transparent),
      enabledBorder: border(Colors.transparent),
      focusedBorder: border(AppColors.primary),
      hintStyle: const TextStyle(color: AppColors.muted),
      labelStyle: const TextStyle(color: AppColors.muted),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(26),
        ),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: AppColors.bg,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Color(0xFFE7F3FF),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF323436),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

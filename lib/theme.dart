import 'package:flutter/material.dart';

class _Palette {
  const _Palette({
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.primary,
    required this.muted,
    required this.text,
    required this.bubbleTheirs,
  });

  final Color bg;
  final Color surface;
  final Color surface2;
  final Color primary;
  final Color muted;
  final Color text;
  final Color bubbleTheirs;
}

const _light = _Palette(
  bg: Color(0xFFFFFFFF),
  surface: Color(0xFFF0F2F5),
  surface2: Color(0xFFE4E6EB),
  primary: Color(0xFF0084FF),
  muted: Color(0xFF65676B),
  text: Color(0xFF050505),
  bubbleTheirs: Color(0xFFF0F0F0),
);

const _dark = _Palette(
  bg: Color(0xFF18191A),
  surface: Color(0xFF242526),
  surface2: Color(0xFF3A3B3C),
  primary: Color(0xFF2D88FF),
  muted: Color(0xFFB0B3B8),
  text: Color(0xFFE4E6EB),
  bubbleTheirs: Color(0xFF3A3B3C),
);

/// Couleurs de l'app (Messenger). `dark` est mis à jour par RootApp quand le
/// thème change, puis tout l'arbre de widgets est reconstruit.
class AppColors {
  static bool dark = false;

  static _Palette get _p => dark ? _dark : _light;

  static Color get bg => _p.bg;
  static Color get surface => _p.surface;
  static Color get surface2 => _p.surface2;
  static Color get primary => _p.primary;
  static Color get cyan => _p.primary; // ancien nom, gardé pour compatibilité
  static Color get muted => _p.muted;
  static Color get text => _p.text;
  static Color get bubbleTheirs => _p.bubbleTheirs;
  static Color get violet => const Color(0xFF7C4DFF);
  static Color get online => const Color(0xFF31A24C);

  static LinearGradient get gradient => LinearGradient(
        colors: [const Color(0xFF0099FF), _p.primary],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

ThemeData buildTheme(bool dark) {
  final p = dark ? _dark : _light;
  final scheme = ColorScheme.fromSeed(
    seedColor: p.primary,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: p.primary,
    onPrimary: Colors.white,
    surface: p.bg,
    onSurface: p.text,
  );

  OutlineInputBorder border(Color color) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: BorderSide(color: color, width: 1.2),
      );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: p.bg,
    appBarTheme: AppBarTheme(
      backgroundColor: p.bg,
      foregroundColor: p.text,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        color: p.text,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.surface,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      border: border(Colors.transparent),
      enabledBorder: border(Colors.transparent),
      focusedBorder: border(p.primary),
      hintStyle: TextStyle(color: p.muted),
      labelStyle: TextStyle(color: p.muted),
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
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: p.bg,
      surfaceTintColor: Colors.transparent,
      indicatorColor: dark ? const Color(0xFF263951) : const Color(0xFFE7F3FF),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: p.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? p.surface2 : const Color(0xFF323436),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

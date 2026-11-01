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
  bg: Color(0xFFF3F5F3),
  surface: Color(0xFFFFFFFF),
  surface2: Color(0xFFE2E8E4),
  primary: Color(0xFF3F6B57),
  muted: Color(0xFF5E6B64),
  text: Color(0xFF1B2420),
  bubbleTheirs: Color(0xFFE4EAE6),
);

const _dark = _Palette(
  bg: Color(0xFF111714),
  surface: Color(0xFF1A231F),
  surface2: Color(0xFF26332D),
  primary: Color(0xFF5C8F76),
  muted: Color(0xFF9AA8A0),
  text: Color(0xFFE6EDE9),
  bubbleTheirs: Color(0xFF222D28),
);

/// Palette « bleu nuit » réservée à l'application Lumi.
const _nova = _Palette(
  bg: Color(0xFF050B1F),
  surface: Color(0xFF0E1A3A),
  surface2: Color(0xFF1A2A55),
  primary: Color(0xFF2D7BFF),
  muted: Color(0xFF93A4C8),
  text: Color(0xFFEAF0FF),
  bubbleTheirs: Color(0xFF152447),
);

/// Espacements, rayons et durées communs (design system).
class AppSpacing {
  static const xs = 4.0, sm = 8.0, md = 12.0, lg = 16.0, xl = 24.0;
  static const radiusSm = 12.0, radiusMd = 18.0, radiusLg = 26.0;
  static const fast = Duration(milliseconds: 180);
  static const normal = Duration(milliseconds: 280);
}

/// Couleurs de l'app (vert & or). `dark` est mis à jour par RootApp quand le
/// thème change, puis tout l'arbre de widgets est reconstruit.
class AppColors {
  static bool dark = false;
  static bool nova = false; // vrai tant que l'application Lumi est ouverte

  static _Palette get _p => nova ? _nova : (dark ? _dark : _light);

  static Color get bg => _p.bg;
  static Color get surface => _p.surface;
  static Color get surface2 => _p.surface2;
  static Color get primary => _p.primary;
  static Color get cyan => _p.primary; // ancien nom, gardé pour compatibilité
  static Color get muted => _p.muted;
  static Color get text => _p.text;
  static Color get bubbleTheirs => _p.bubbleTheirs;
  static Color get violet => const Color(0xFF7C4DFF);
  static Color get online => const Color(0xFF31C46E);

  /// Or : accent (remplissages, anneaux). Pour du texte sur fond clair,
  /// utiliser [goldText] (contraste suffisant).
  static const gold = Color(0xFFD4AF37);
  static Color get goldText =>
      dark ? const Color(0xFFD4AF37) : const Color(0xFF8A6D12);
  static const deepGreen = Color(0xFF26382F);

  static LinearGradient get gradient => const LinearGradient(
        colors: [Color(0xFF3F6B57), Color(0xFF55856D)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

ThemeData buildTheme(bool dark, {bool nova = false}) {
  if (nova) dark = true;
  final p = nova ? _nova : (dark ? _dark : _light);
  final scheme = ColorScheme.fromSeed(
    seedColor: p.primary,
    brightness: dark ? Brightness.dark : Brightness.light,
  ).copyWith(
    primary: p.primary,
    onPrimary: Colors.white,
    secondary: AppColors.gold,
    onSecondary: const Color(0xFF07130F),
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
      indicatorColor: nova
          ? const Color(0xFF1E3A78)
          : (dark ? const Color(0xFF1B3428) : const Color(0xFFDDEFE3)),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.gold : p.muted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? p.primary
              : p.surface2),
    ),
    cardTheme: CardThemeData(
      color: p.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
        side: BorderSide(color: p.surface2),
      ),
    ),
    dividerTheme: DividerThemeData(color: p.surface2, space: 1),
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
      backgroundColor: dark ? p.surface2 : const Color(0xFF17231C),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
  );
}

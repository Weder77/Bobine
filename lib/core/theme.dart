import 'package:flutter/material.dart';

/// "Nuit ambrée" design tokens (see the Lumen design canvas).
class AppColors {
  // Grounds
  static const bg = Color(0xFF07080B); // ink
  static const surface = Color(0xFF11141B); // cards
  static const surface2 = Color(0xFF161922); // menus, blocks
  static const surface3 = Color(0xFF1E222C); // logos, chips
  static const selected = Color(0xFF1A1D25); // selected rows
  static const field = Color(0xFF0F1116); // inputs
  static const border = Color(0xFF1C1F27); // hairlines
  static const borderStrong = Color(0xFF2B2F3A); // outlined controls

  // Text
  static const text = Color(0xFFF4F1EA);
  static const textSoft = Color(0xFFC9CED8);
  static const muted = Color(0xFFA3A9B5);
  static const faint = Color(0xFF8B92A0);

  // Accent: the only action colour.
  static const accent = Color(0xFFFFB547);
  static const onAccent = Color(0xFF1A1204);
  static Color get accentTint => accent.withValues(alpha: 0.14);

  // Status
  static const live = Color(0xFFFF4D5E);
  static const liveBadge = Color(0xFFE5293B);
  static const success = Color(0xFF3DDC97);

  // Content cues (icons of the quick-access tiles).
  static const cueLive = Color(0xFF7FA6FF);
  static const cueFilms = Color(0xFFB39DFF);
  static const cueSeries = Color(0xFFFF8FA8);

  /// Kept for the app icon only.
  static const accent2 = Color(0xFFFF7A59);
  static const accentGradient = LinearGradient(
    colors: [accent, accent2],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

/// Typefaces: Bricolage Grotesque for titles, Inter for the interface.
class AppFonts {
  static const display = 'Bricolage';
  static const body = 'Inter';
}

/// Title style in Bricolage Grotesque.
TextStyle displayStyle(double size, {FontWeight weight = FontWeight.w700, Color? color, double? height}) =>
    TextStyle(
      fontFamily: AppFonts.display,
      fontSize: size,
      fontWeight: weight,
      color: color ?? AppColors.text,
      height: height,
      letterSpacing: size >= 40 ? -0.01 * size : null,
    );

/// Small uppercase label ("MAINTENANT · 20:30").
TextStyle labelStyle({Color color = AppColors.muted, double size = 12}) => TextStyle(
      fontSize: size,
      fontWeight: FontWeight.w700,
      letterSpacing: size * 0.12,
      color: color,
    );

const tabularFigures = [FontFeature.tabularFigures()];

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    secondary: AppColors.accent,
    onSecondary: AppColors.onAccent,
    surface: AppColors.surface,
    onSurface: AppColors.text,
    surfaceContainerHighest: AppColors.surface3,
    surfaceContainerHigh: AppColors.surface2,
    surfaceContainer: AppColors.surface,
    surfaceContainerLow: AppColors.surface,
    outline: AppColors.borderStrong,
    outlineVariant: AppColors.border,
    error: AppColors.live,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: AppFonts.body,
    scaffoldBackgroundColor: AppColors.bg,
    canvasColor: AppColors.bg,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.compact,
  );
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
  return base.copyWith(
    textTheme: base.textTheme.apply(
      fontFamily: AppFonts.body,
      bodyColor: AppColors.text,
      displayColor: AppColors.text,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1, space: 1),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.field,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: const TextStyle(color: AppColors.faint),
      labelStyle: const TextStyle(color: AppColors.muted),
      prefixIconColor: AppColors.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF23262F)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF23262F)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: buttonShape,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w700, fontSize: 16),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        backgroundColor: Colors.white.withValues(alpha: 0.06),
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 22),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.22)),
        shape: buttonShape,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600, fontSize: 16),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.textSoft,
        minimumSize: const Size(44, 44),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.surface3 : AppColors.surface),
        foregroundColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected) ? AppColors.text : AppColors.muted),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.border)),
        textStyle: const WidgetStatePropertyAll(
            TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600, fontSize: 14)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.onAccent : AppColors.muted),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.accent : AppColors.surface3),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: AppColors.accentTint,
      side: const BorderSide(color: AppColors.borderStrong),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600, fontSize: 14),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface2,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.borderStrong),
      ),
      textStyle: const TextStyle(fontFamily: AppFonts.body, color: AppColors.text, fontSize: 14),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surface3,
      contentTextStyle: const TextStyle(fontFamily: AppFonts.body, color: AppColors.text),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      width: 520,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surface3,
        borderRadius: BorderRadius.circular(8),
      ),
      textStyle: const TextStyle(fontFamily: AppFonts.body, color: AppColors.text, fontSize: 12),
      waitDuration: const Duration(milliseconds: 500),
    ),
    sliderTheme: const SliderThemeData(
      activeTrackColor: AppColors.accent,
      thumbColor: AppColors.accent,
      inactiveTrackColor: Color(0x33FFFFFF),
      trackHeight: 3,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(const Color(0x40FFFFFF)),
      thickness: WidgetStateProperty.all(6),
      radius: const Radius.circular(3),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

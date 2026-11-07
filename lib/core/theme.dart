import 'package:flutter/material.dart';

/// "Salle obscure" design tokens (streaming direction, see the design canvas):
/// the image comes first, actions are white, amber is only the brand mark and
/// progress.
class AppColors {
  // Grounds
  static const bg = Color(0xFF111114);
  static const surface = Color(0xFF1C1C21); // cards
  static const surface2 = Color(0xFF232329); // menus, panels
  static const surface3 = Color(0xFF2C2C33); // logos, chips
  static const selected = Color(0xFF26262C); // selected rows
  static const field = Color(0xFF18181C); // inputs
  static const border = Color(0xFF26262C); // hairlines
  static const borderStrong = Color(0xFF3A3A42); // outlined controls

  // Text
  static const text = Color(0xFFFFFFFF);
  static const textSoft = Color(0xFFE6E7EB);
  static const muted = Color(0xFFA9AAB1);
  static const faint = Color(0xFF8C8D94);

  // Brand: logo, progress bars, ratings.
  static const accent = Color(0xFFFFB547);
  static const onAccent = Color(0xFF1A1204);
  static Color get accentTint => accent.withValues(alpha: 0.14);

  // Actions: white primary buttons, frosted secondary ones.
  static const action = Color(0xFFFFFFFF);
  static const onAction = Color(0xFF0B0B0D);
  static const frosted = Color(0x33FFFFFF);

  // Status
  static const live = Color(0xFFF23B4C);
  static const liveBadge = Color(0xFFD81F33);
  static const success = Color(0xFF3DDC97);

  // Content cues.
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

/// Typefaces: Inter for the interface, Bebas Neue for poster titles.
class AppFonts {
  static const body = 'Inter';
  static const poster = 'BebasNeue';
}

/// Heading style (Inter, heavy, slightly tightened).
TextStyle displayStyle(double size, {FontWeight weight = FontWeight.w800, Color? color, double? height}) => TextStyle(
  fontFamily: AppFonts.body,
  fontSize: size,
  fontWeight: weight,
  color: color ?? AppColors.text,
  height: height,
  letterSpacing: size >= 24 ? -0.02 * size : null,
);

/// Condensed capitals for titles over images ("LES VEILLEURS").
TextStyle posterStyle(double size, {Color? color, double height = 0.9, List<Shadow>? shadows}) => TextStyle(
  fontFamily: AppFonts.poster,
  fontSize: size,
  fontWeight: FontWeight.w400,
  color: color ?? AppColors.text,
  height: height,
  letterSpacing: size * 0.01,
  shadows: shadows,
);

/// Small uppercase label ("À SUIVRE").
TextStyle labelStyle({Color color = AppColors.muted, double size = 12}) =>
    TextStyle(fontSize: size, fontWeight: FontWeight.w700, letterSpacing: size * 0.14, color: color);

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
    focusColor: const Color(0x29FFFFFF),
  );
  const buttonShape = StadiumBorder();
  // Keyboard / remote / gamepad focus: an amber ring, visible on white and
  // dark buttons alike (mouse clicks never show it).
  WidgetStateProperty<BorderSide?> focusSide([BorderSide? rest]) => WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.focused) ? const BorderSide(color: AppColors.accent, width: 2.5) : rest,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: AppFonts.body, bodyColor: AppColors.text, displayColor: AppColors.text),
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
        borderSide: const BorderSide(color: AppColors.borderStrong),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.borderStrong),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: AppColors.text, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.action,
        foregroundColor: AppColors.onAction,
        disabledBackgroundColor: AppColors.surface3,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 26),
        shape: buttonShape,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w700, fontSize: 16),
      ).copyWith(side: focusSide()),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        backgroundColor: AppColors.frosted,
        minimumSize: const Size(0, 52),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: buttonShape,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w700, fontSize: 16),
      ).copyWith(side: focusSide(BorderSide.none)),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.text,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600, fontSize: 15),
      ).copyWith(side: focusSide()),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: AppColors.textSoft,
        minimumSize: const Size(44, 44),
        shape: const CircleBorder(),
      ).copyWith(side: focusSide()),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.action : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? AppColors.onAction : AppColors.textSoft,
        ),
        side: const WidgetStatePropertyAll(BorderSide(color: AppColors.borderStrong)),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.onAccent : AppColors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.accent : AppColors.surface3,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: AppColors.action,
      side: WidgetStateBorderSide.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? const BorderSide(color: AppColors.action)
            : const BorderSide(color: AppColors.borderStrong),
      ),
      shape: const StadiumBorder(),
      labelStyle: const TextStyle(
        fontFamily: AppFonts.body,
        fontWeight: FontWeight.w600,
        fontSize: 14,
        color: AppColors.textSoft,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: AppFonts.body,
        fontWeight: FontWeight.w700,
        fontSize: 14,
        color: AppColors.onAction,
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: AppColors.surface2,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
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
      actionTextColor: AppColors.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      width: 520,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: AppColors.surface3, borderRadius: BorderRadius.circular(8)),
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
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

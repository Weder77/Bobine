import 'package:flutter/material.dart';

/// "Bobine" design tokens (design_handoff_bobine): a warm near-black, cream
/// and a vermilion accent; images come first, actions are white.
class AppColors {
  // Grounds
  static const bg = Color(0xFF0D0C0B);
  static const surface = Color(0xFF1A1816); // cards, inputs
  static const surface2 = Color(0xFF141311); // menus, panels
  static const surface3 = Color(0xFF26221F); // programme on air (guide), chips
  static const selected = Color(0xFF26221F);
  static const field = Color(0xFF1A1816);
  static const border = Color(0xFF24211E); // hairlines
  static const borderSoft = Color(0xFF1E1C1A);
  static const borderFaint = Color(0xFF161513);
  static const borderInput = Color(0xFF2E2A26);
  static const borderStrong = Color(0xFF3A3530); // outlined controls

  // Text
  static const text = Color(0xFFFFFFFF);
  static const textSoft = Color(0xFFD9D4CE);
  static const muted = Color(0xFFB5AFA8); // tertiary, inactive nav
  static const faint = Color(0xFF9A948D); // meta, mono
  static const disabled = Color(0xFF7D766F); // past programmes
  static const disabled2 = Color(0xFF5E5852);
  static const placeholder = Color(0xFF6F6862);
  static const outlineDigit = Color(0xFF57514B); // Top 10 numbers

  // Brand: vermilion accent (live, progress, selection), cream marks.
  static const accent = Color(0xFFFF5A36);
  static const accentHover = Color(0xFFFF7A5C);
  static const onAccent = Color(0xFF1A0A05);
  static const accentSelected = Color(0xFF2B1A13); // guide selection
  static Color get accentTint => accent.withValues(alpha: 0.16);
  static const cream = Color(0xFFF3EEE8); // channel badges, reel flanks
  static const reelShadow = Color(0xFFB83A1D);

  // Actions: white primary buttons, warm translucent secondary ones.
  static const action = Color(0xFFFFFFFF);
  static const onAction = Color(0xFF0D0C0B);
  static const frosted = Color(0x73787068); // rgba(120,112,104,.45)
  static const frostedHover = Color(0xA6787068); // .65
  static const glass = Color(0xA8201D1A); // rgba(32,29,26,.66)

  // Status
  static const live = accent;
  static const liveBadge = accent;
  static const success = Color(0xFF8FD1C2);
  static const successTint = Color(0x246FB7A8);

  // Profile colours offered in the editor.
  static const guest = Color(0xFFE8C547);
  static const kids = Color(0xFF6FB7A8);

  // Kept names (older widgets): everything points at the accent now.
  static const cueLive = accent;
  static const cueFilms = accent;
  static const cueSeries = accent;
  static const accent2 = accentHover;
  static const accentGradient = LinearGradient(
    colors: [accent, accentHover],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  /// Backdrop of a missing image, tinted per title / channel (hue 0-360).
  static Gradient placeholderGradient(double hue) => RadialGradient(
    center: const Alignment(0.48, -0.4),
    radius: 1.1,
    colors: [HSLColor.fromAHSL(1, hue, 0.48, 0.22).toColor(), HSLColor.fromAHSL(1, hue, 0.30, 0.10).toColor(), bg],
    stops: const [0, 0.45, 0.85],
  );
}

/// Typefaces: Geist for the interface, Geist Mono for times and counters,
/// Big Shoulders Display for screen and hero titles, Sacramento for the logo.
class AppFonts {
  static const body = 'Geist';
  static const mono = 'GeistMono';
  static const poster = 'BigShoulders';
  static const script = 'Sacramento';
}

/// Interface heading (Geist): row titles 20/600, dialog titles.
TextStyle displayStyle(double size, {FontWeight weight = FontWeight.w700, Color? color, double? height}) => TextStyle(
  fontFamily: AppFonts.body,
  fontSize: size,
  fontWeight: weight,
  color: color ?? AppColors.text,
  height: height,
  letterSpacing: size >= 24 ? -0.01 * size : null,
);

/// Big Shoulders Display capitals for screen and hero titles ("DIRECT").
/// Callers pass upper-case text.
TextStyle posterStyle(
  double size, {
  Color? color,
  double height = 0.86,
  List<Shadow>? shadows,
  FontWeight weight = FontWeight.w800,
}) => TextStyle(
  fontFamily: AppFonts.poster,
  fontSize: size,
  fontWeight: weight,
  color: color ?? AppColors.text,
  height: height,
  shadows: shadows,
);

/// Geist Mono: times, counters, channel numbers, quality badges.
TextStyle monoStyle(double size, {FontWeight weight = FontWeight.w500, Color? color, double? height}) => TextStyle(
  fontFamily: AppFonts.mono,
  fontSize: size,
  fontWeight: weight,
  color: color ?? AppColors.faint,
  height: height,
  fontFeatures: tabularFigures,
);

/// Kicker: small capitals with wide spacing ("FILM · NOUVEAUTÉ").
TextStyle labelStyle({Color color = AppColors.muted, double size = 12}) => TextStyle(
  fontFamily: AppFonts.body,
  fontSize: size,
  fontWeight: FontWeight.w600,
  letterSpacing: size * 0.16,
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
    focusColor: const Color(0x29FFFFFF),
  );
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
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
      hintStyle: const TextStyle(color: AppColors.disabled),
      labelStyle: const TextStyle(color: AppColors.muted),
      prefixIconColor: AppColors.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.borderInput),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.borderInput),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.action,
        foregroundColor: AppColors.onAction,
        disabledBackgroundColor: AppColors.surface3,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: buttonShape,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600, fontSize: 15),
      ).copyWith(side: focusSide()),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            foregroundColor: AppColors.text,
            backgroundColor: AppColors.frosted,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            shape: buttonShape,
            textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600, fontSize: 15),
          ).copyWith(
            side: focusSide(BorderSide.none),
            backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.hovered) ? AppColors.frostedHover : AppColors.frosted,
            ),
          ),
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
        (s) => s.contains(WidgetState.selected) ? AppColors.text : AppColors.muted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? AppColors.accent : AppColors.borderStrong,
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
      elevation: 24,
      shadowColor: const Color(0xA6000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      textStyle: const TextStyle(fontFamily: AppFonts.body, color: AppColors.text, fontSize: 14),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AppColors.surface,
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
      inactiveTrackColor: Color(0x59FFFFFF),
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

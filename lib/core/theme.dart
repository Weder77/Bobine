import 'package:flutter/material.dart';

/// Colours of one theme ("Bobine" design tokens: warm grounds, cream marks
/// and a vermilion accent).
class AppPalette {
  const AppPalette({
    required this.isLight,
    required this.bg,
    required this.surface,
    required this.surface2,
    required this.surface3,
    required this.field,
    required this.border,
    required this.borderSoft,
    required this.borderFaint,
    required this.borderInput,
    required this.borderStrong,
    required this.text,
    required this.textSoft,
    required this.muted,
    required this.faint,
    required this.disabled,
    required this.disabled2,
    required this.placeholder,
    required this.outlineDigit,
    required this.accent,
    required this.accentHover,
    required this.onAccent,
    required this.accentSelected,
    required this.action,
    required this.onAction,
    required this.frosted,
    required this.frostedHover,
    required this.glass,
    required this.glassHover,
    required this.success,
    required this.successTint,
    required this.ink,
    required this.reelFlange,
  });

  final bool isLight;

  // Grounds
  final Color bg;
  final Color surface; // cards, inputs
  final Color surface2; // menus, panels
  final Color surface3; // programme on air (guide), tooltips
  final Color field;
  final Color border; // hairlines
  final Color borderSoft;
  final Color borderFaint;
  final Color borderInput;
  final Color borderStrong; // outlined controls

  // Text
  final Color text;
  final Color textSoft;
  final Color muted; // tertiary, inactive nav
  final Color faint; // meta, mono
  final Color disabled; // past programmes
  final Color disabled2;
  final Color placeholder;
  final Color outlineDigit; // Top 10 numbers

  // Brand
  final Color accent;
  final Color accentHover;
  final Color onAccent;
  final Color accentSelected; // guide selection

  // Actions: primary buttons (white on dark, ink on light), translucent
  // secondary ones.
  final Color action;
  final Color onAction;
  final Color frosted;
  final Color frostedHover;
  final Color glass;
  final Color glassHover;

  // Status
  final Color success;
  final Color successTint;

  /// Colour of hover tints and hairlines over anything: white in the dark
  /// theme, the text colour in the light one.
  final Color ink;

  /// Flanges of the reel in the logo.
  final Color reelFlange;

  static const dark = AppPalette(
    isLight: false,
    bg: Color(0xFF0D0C0B),
    surface: Color(0xFF1A1816),
    surface2: Color(0xFF141311),
    surface3: Color(0xFF26221F),
    field: Color(0xFF1A1816),
    border: Color(0xFF24211E),
    borderSoft: Color(0xFF1E1C1A),
    borderFaint: Color(0xFF161513),
    borderInput: Color(0xFF2E2A26),
    borderStrong: Color(0xFF3A3530),
    text: Color(0xFFFFFFFF),
    textSoft: Color(0xFFD9D4CE),
    muted: Color(0xFFB5AFA8),
    faint: Color(0xFF9A948D),
    disabled: Color(0xFF7D766F),
    disabled2: Color(0xFF5E5852),
    placeholder: Color(0xFF6F6862),
    outlineDigit: Color(0xFF57514B),
    accent: Color(0xFFFF5A36),
    accentHover: Color(0xFFFF7A5C),
    onAccent: Color(0xFF1A0A05),
    accentSelected: Color(0xFF2B1A13),
    action: Color(0xFFFFFFFF),
    onAction: Color(0xFF0D0C0B),
    frosted: Color(0x73787068),
    frostedHover: Color(0xA6787068),
    glass: Color(0xA8201D1A),
    glassHover: Color(0xD9342F2A),
    success: Color(0xFF8FD1C2),
    successTint: Color(0x246FB7A8),
    ink: Color(0xFFFFFFFF),
    reelFlange: Color(0xFFF3EEE8),
  );

  static const light = AppPalette(
    isLight: true,
    bg: Color(0xFFF6F2EC),
    surface: Color(0xFFEDE7E0),
    surface2: Color(0xFFFFFFFF),
    surface3: Color(0xFFE4DCD2),
    field: Color(0xFFFFFFFF),
    border: Color(0xFFE2DAD0),
    borderSoft: Color(0xFFE7E0D7),
    borderFaint: Color(0xFFECE6DF),
    borderInput: Color(0xFFD6CDC2),
    borderStrong: Color(0xFFC4B9AD),
    text: Color(0xFF1A1613),
    textSoft: Color(0xFF3B3530),
    muted: Color(0xFF5C554F),
    faint: Color(0xFF766E67),
    disabled: Color(0xFF9D958D),
    disabled2: Color(0xFFB8B0A7),
    placeholder: Color(0xFFA0978E),
    outlineDigit: Color(0xFFC9BFB4),
    accent: Color(0xFFE5481F),
    accentHover: Color(0xFFFF5A36),
    onAccent: Color(0xFFFFFFFF),
    accentSelected: Color(0xFFFBE2D9),
    action: Color(0xFF1A1613),
    onAction: Color(0xFFFFFFFF),
    frosted: Color(0x1A1A1613),
    frostedHover: Color(0x2E1A1613),
    glass: Color(0xC7FFFFFF),
    glassHover: Color(0xF2FFFFFF),
    success: Color(0xFF2B7F6D),
    successTint: Color(0x1F2B7F6D),
    ink: Color(0xFF1A1613),
    reelFlange: Color(0xFF2A2420),
  );
}

/// Colours of the current theme ([AppPalette.dark] or [AppPalette.light]).
/// They are read while building, so switching theme rebuilds the app.
class AppColors {
  static AppPalette current = AppPalette.dark;

  static bool get isLight => current.isLight;

  // Grounds
  static Color get bg => current.bg;
  static Color get surface => current.surface;
  static Color get surface2 => current.surface2;
  static Color get surface3 => current.surface3;
  static Color get selected => current.surface3;
  static Color get field => current.field;
  static Color get border => current.border;
  static Color get borderSoft => current.borderSoft;
  static Color get borderFaint => current.borderFaint;
  static Color get borderInput => current.borderInput;
  static Color get borderStrong => current.borderStrong;

  // Text
  static Color get text => current.text;
  static Color get textSoft => current.textSoft;
  static Color get muted => current.muted;
  static Color get faint => current.faint;
  static Color get disabled => current.disabled;
  static Color get disabled2 => current.disabled2;
  static Color get placeholder => current.placeholder;
  static Color get outlineDigit => current.outlineDigit;

  // Brand
  static Color get accent => current.accent;
  static Color get accentHover => current.accentHover;
  static Color get onAccent => current.onAccent;
  static Color get accentSelected => current.accentSelected;
  static Color get accentTint => accent.withValues(alpha: 0.16);
  static const cream = Color(0xFFF3EEE8); // channel badges (same in both themes)
  static const reelShadow = Color(0xFFB83A1D);
  static Color get reelFlange => current.reelFlange;

  // Actions
  static Color get action => current.action;
  static Color get onAction => current.onAction;
  static Color get frosted => current.frosted;
  static Color get frostedHover => current.frostedHover;
  static Color get glass => current.glass;
  static Color get glassHover => current.glassHover;

  /// Hover tints and hairlines (white on dark, ink on light).
  static Color get ink => current.ink;

  /// Black shadow of [alpha] (0-255) on the dark theme, much lighter on
  /// the light one.
  static Color shadow(int alpha) => Color.fromARGB(isLight ? (alpha * 0.3).round() : alpha, 0, 0, 0);

  // Status
  static Color get live => accent;
  static Color get liveBadge => accent;
  static Color get success => current.success;
  static Color get successTint => current.successTint;

  // Profile colours offered in the editor.
  static const guest = Color(0xFFE8C547);
  static const kids = Color(0xFF6FB7A8);

  // Kept names (older widgets): everything points at the accent now.
  static Color get cueLive => accent;
  static Color get cueFilms => accent;
  static Color get cueSeries => accent;
  static Color get accent2 => accentHover;

  /// Backdrop of a missing image, tinted per title / channel (hue 0-360).
  static Gradient placeholderGradient(double hue) => RadialGradient(
    center: const Alignment(0.48, -0.4),
    radius: 1.1,
    colors: isLight
        ? [HSLColor.fromAHSL(1, hue, 0.42, 0.80).toColor(), HSLColor.fromAHSL(1, hue, 0.28, 0.89).toColor(), bg]
        : [HSLColor.fromAHSL(1, hue, 0.48, 0.22).toColor(), HSLColor.fromAHSL(1, hue, 0.30, 0.10).toColor(), bg],
    stops: const [0, 0.45, 0.85],
  );
}

/// The dark colours, fixed: video surfaces (player, mini-player) stay dark
/// whatever the theme.
class DarkColors {
  static const bg = Color(0xFF0D0C0B);
  static const surface = Color(0xFF1A1816);
  static const surface2 = Color(0xFF141311);
  static const surface3 = Color(0xFF26221F);
  static const border = Color(0xFF24211E);
  static const borderSoft = Color(0xFF1E1C1A);
  static const borderInput = Color(0xFF2E2A26);
  static const borderStrong = Color(0xFF3A3530);
  static const text = Color(0xFFFFFFFF);
  static const textSoft = Color(0xFFD9D4CE);
  static const muted = Color(0xFFB5AFA8);
  static const faint = Color(0xFF9A948D);
  static const disabled = Color(0xFF7D766F);
  static const accent = Color(0xFFFF5A36);
  static const accentHover = Color(0xFFFF7A5C);
  static const onAccent = Color(0xFF1A0A05);
  static const cream = Color(0xFFF3EEE8);
  static const action = Color(0xFFFFFFFF);
  static const onAction = Color(0xFF0D0C0B);
  static const live = accent;
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
TextStyle labelStyle({Color? color, double size = 12}) => TextStyle(
  fontFamily: AppFonts.body,
  fontSize: size,
  fontWeight: FontWeight.w600,
  letterSpacing: size * 0.16,
  color: color ?? AppColors.muted,
);

const tabularFigures = [FontFeature.tabularFigures()];

// Styles of the video surfaces (player, mini-player): always dark.
TextStyle darkMono(double size, {FontWeight weight = FontWeight.w500, Color? color, double? height}) =>
    monoStyle(size, weight: weight, color: color ?? DarkColors.faint, height: height);

TextStyle darkPoster(
  double size, {
  Color? color,
  double height = 0.86,
  List<Shadow>? shadows,
  FontWeight weight = FontWeight.w800,
}) => posterStyle(size, color: color ?? DarkColors.text, height: height, shadows: shadows, weight: weight);

TextStyle darkLabel({Color? color, double size = 12}) => labelStyle(color: color ?? DarkColors.muted, size: size);

/// Material theme of the video surfaces.
final ThemeData darkTheme = buildTheme(AppPalette.dark);

/// Material theme for [p]. [p.current] must already be [p].
ThemeData buildTheme([AppPalette p = AppPalette.dark]) {
  final scheme = (p.isLight ? ColorScheme.light : ColorScheme.dark)(
    primary: p.accent,
    onPrimary: p.onAccent,
    secondary: p.accent,
    onSecondary: p.onAccent,
    surface: p.surface,
    onSurface: p.text,
    surfaceContainerHighest: p.surface3,
    surfaceContainerHigh: p.surface2,
    surfaceContainer: p.surface,
    surfaceContainerLow: p.surface,
    outline: p.borderStrong,
    outlineVariant: p.border,
    error: p.accent,
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: p.isLight ? Brightness.light : Brightness.dark,
    colorScheme: scheme,
    fontFamily: AppFonts.body,
    scaffoldBackgroundColor: p.bg,
    canvasColor: p.bg,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.compact,
    focusColor: p.ink.withValues(alpha: 0.16),
  );
  final buttonShape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
  // Keyboard / remote / gamepad focus: an amber ring, visible on white and
  // dark buttons alike (mouse clicks never show it).
  WidgetStateProperty<BorderSide?> focusSide([BorderSide? rest]) => WidgetStateProperty.resolveWith(
    (s) => s.contains(WidgetState.focused) ? BorderSide(color: p.accent, width: 2.5) : rest,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: AppFonts.body, bodyColor: p.text, displayColor: p.text),
    dividerTheme: DividerThemeData(color: p.border, thickness: 1, space: 1),
    cardTheme: CardThemeData(
      color: p.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16))),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: p.field,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      hintStyle: TextStyle(color: p.disabled),
      labelStyle: TextStyle(color: p.muted),
      prefixIconColor: p.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: p.borderInput),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: p.borderInput),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: p.accent, width: 1.2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: p.action,
        foregroundColor: p.onAction,
        disabledBackgroundColor: p.surface3,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        shape: buttonShape,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600, fontSize: 15),
      ).copyWith(side: focusSide()),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style:
          OutlinedButton.styleFrom(
            foregroundColor: p.text,
            backgroundColor: p.frosted,
            minimumSize: const Size(0, 48),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            shape: buttonShape,
            textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600, fontSize: 15),
          ).copyWith(
            side: focusSide(BorderSide.none),
            backgroundColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.hovered) ? p.frostedHover : p.frosted,
            ),
          ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: p.text,
        textStyle: const TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600, fontSize: 15),
      ).copyWith(side: focusSide()),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: p.textSoft,
        minimumSize: const Size(44, 44),
        shape: const CircleBorder(),
      ).copyWith(side: focusSide()),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.action : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? p.onAction : p.textSoft,
        ),
        side: WidgetStatePropertyAll(BorderSide(color: p.borderStrong)),
        shape: const WidgetStatePropertyAll(StadiumBorder()),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : p.muted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? p.accent : p.borderStrong),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: p.action,
      side: WidgetStateBorderSide.resolveWith(
        (s) => s.contains(WidgetState.selected) ? BorderSide(color: p.action) : BorderSide(color: p.borderStrong),
      ),
      shape: const StadiumBorder(),
      labelStyle: TextStyle(fontFamily: AppFonts.body, fontWeight: FontWeight.w600, fontSize: 14, color: p.textSoft),
      secondaryLabelStyle: TextStyle(
        fontFamily: AppFonts.body,
        fontWeight: FontWeight.w700,
        fontSize: 14,
        color: p.onAction,
      ),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: p.surface2,
      surfaceTintColor: Colors.transparent,
      elevation: 24,
      shadowColor: p.isLight ? const Color(0x30000000) : const Color(0xA6000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.border),
      ),
      textStyle: TextStyle(fontFamily: AppFonts.body, color: p.text, fontSize: 14),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: p.surface2,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: p.border),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: p.surface,
      contentTextStyle: TextStyle(fontFamily: AppFonts.body, color: p.text),
      actionTextColor: p.accent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      width: 520,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: p.surface3, borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(fontFamily: AppFonts.body, color: p.text, fontSize: 12),
      waitDuration: const Duration(milliseconds: 500),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: p.accent,
      thumbColor: p.accent,
      inactiveTrackColor: p.ink.withValues(alpha: 0.35),
      trackHeight: 3,
      overlayShape: RoundSliderOverlayShape(overlayRadius: 12),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: p.accent),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStateProperty.all(p.ink.withValues(alpha: 0.25)),
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

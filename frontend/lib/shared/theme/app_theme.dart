import 'package:flutter/material.dart';

// Brand palette from the Safernotes design system sheet.
const _brandSeed = Color(0xff85b9c9);
const _brandAccent = Color(0xffb49ae6);
const brandTeal = Color(0xff85b9c9);
const brandLavender = Color(0xffb49ae6);
const brandAmber = Color(0xfffad349);
const brandOffWhite = Color(0xfff6f6f6);

abstract final class AppSpacing {
  static const double xxs = 4;
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

abstract final class AppRadii {
  static const double xs = 6;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 22;
  static const double xxl = 28;
  static const double hero = 34;
  static const double card = 38;
  static const double pill = 999;
}

/// Base canvas colours the translucent surfaces are composited over.
const canvasBaseDark = Color(0xff101a1d);
const canvasBaseLight = Color(0xfff2eee9);

Color canvasBaseColor(Brightness brightness) =>
    brightness == Brightness.dark ? canvasBaseDark : canvasBaseLight;

/// Soft ambient colour washes painted behind the frosted surfaces.
List<Color> ambientMeshColors(Brightness brightness) {
  if (brightness == Brightness.dark) {
    return const [
      Color(0xff3f6b48),
      Color(0xff2f6b78),
      Color(0xff294f63),
      Color(0xff4d7550),
    ];
  }
  return const [
    Color(0xffd9c8f2),
    Color(0xfff6d3b4),
    Color(0xffc9dfd2),
    Color(0xffbfd8e4),
  ];
}

@immutable
class SafernotesTheme extends ThemeExtension<SafernotesTheme> {
  const SafernotesTheme({
    required this.isApple,
    required this.glassFill,
    required this.glassStroke,
    required this.glassShadow,
    required this.glassBlur,
    required this.heroGradientStart,
    required this.heroGradientEnd,
    required this.noteCardRadius,
    required this.controlRadius,
  });

  final bool isApple;
  final Color glassFill;
  final Color glassStroke;
  final Color glassShadow;
  final double glassBlur;
  final Color heroGradientStart;
  final Color heroGradientEnd;
  final double noteCardRadius;
  final double controlRadius;

  @override
  SafernotesTheme copyWith({
    bool? isApple,
    Color? glassFill,
    Color? glassStroke,
    Color? glassShadow,
    double? glassBlur,
    Color? heroGradientStart,
    Color? heroGradientEnd,
    double? noteCardRadius,
    double? controlRadius,
  }) {
    return SafernotesTheme(
      isApple: isApple ?? this.isApple,
      glassFill: glassFill ?? this.glassFill,
      glassStroke: glassStroke ?? this.glassStroke,
      glassShadow: glassShadow ?? this.glassShadow,
      glassBlur: glassBlur ?? this.glassBlur,
      heroGradientStart: heroGradientStart ?? this.heroGradientStart,
      heroGradientEnd: heroGradientEnd ?? this.heroGradientEnd,
      noteCardRadius: noteCardRadius ?? this.noteCardRadius,
      controlRadius: controlRadius ?? this.controlRadius,
    );
  }

  @override
  SafernotesTheme lerp(ThemeExtension<SafernotesTheme>? other, double t) {
    if (other is! SafernotesTheme) return this;
    return SafernotesTheme(
      isApple: t < 0.5 ? isApple : other.isApple,
      glassFill: Color.lerp(glassFill, other.glassFill, t)!,
      glassStroke: Color.lerp(glassStroke, other.glassStroke, t)!,
      glassShadow: Color.lerp(glassShadow, other.glassShadow, t)!,
      glassBlur: _lerpDouble(glassBlur, other.glassBlur, t),
      heroGradientStart:
          Color.lerp(heroGradientStart, other.heroGradientStart, t)!,
      heroGradientEnd: Color.lerp(heroGradientEnd, other.heroGradientEnd, t)!,
      noteCardRadius: _lerpDouble(noteCardRadius, other.noteCardRadius, t),
      controlRadius: _lerpDouble(controlRadius, other.controlRadius, t),
    );
  }
}

extension SafernotesThemeAccess on BuildContext {
  SafernotesTheme get safernotesTheme {
    final theme = Theme.of(this);
    return theme.extension<SafernotesTheme>() ??
        _fallbackSafernotesTheme(theme);
  }
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

SafernotesTheme _fallbackSafernotesTheme(ThemeData theme) {
  final dark = theme.brightness == Brightness.dark;
  final isApple = theme.platform == TargetPlatform.iOS ||
      theme.platform == TargetPlatform.macOS;
  return SafernotesTheme(
    isApple: isApple,
    glassFill: dark
        ? const Color(0xff1b2523).withValues(alpha: 0.86)
        : Colors.white.withValues(alpha: 0.88),
    glassStroke: Colors.transparent,
    glassShadow: Colors.black.withValues(alpha: dark ? 0.34 : 0.10),
    glassBlur: 26,
    heroGradientStart: theme.colorScheme.primary,
    heroGradientEnd: theme.colorScheme.secondary,
    noteCardRadius: AppRadii.card,
    controlRadius: AppRadii.xxl,
  );
}

// Keep persisted color identifiers stable; the displayed palette is themed below.
const brandNoteColors = [
  0xffffffff,
  0xfffff1d8,
  0xffffe5db,
  0xffeee6fa,
  0xfff8e3eb,
  0xfff3e4f2,
];

int normalizeBrandNoteColor(int color) {
  return switch (color) {
    0xfffef3c7 => 0xfffff1d8,
    0xffdcfce7 || 0xffddf7fb => 0xffffe5db,
    0xffdbeafe || 0xffe5efff => 0xffeee6fa,
    0xfffce7f3 || 0xffffe9f4 => 0xfff8e3eb,
    0xffede9fe || 0xffeee9ff => 0xfff3e4f2,
    _ => color,
  };
}

Color brandNoteSurfaceColor(BuildContext context, int color) {
  final normalized = normalizeBrandNoteColor(color);
  final scheme = Theme.of(context).colorScheme;
  if (scheme.brightness != Brightness.dark) {
    return switch (normalized) {
      0xffffffff => Colors.white.withValues(alpha: 0.90),
      0xfffff1d8 => const Color(0xfffae6c8).withValues(alpha: 0.92),
      0xffffe5db => const Color(0xffdcece1).withValues(alpha: 0.92),
      0xffeee6fa => const Color(0xffd7e6ef).withValues(alpha: 0.92),
      0xfff8e3eb => const Color(0xfff6e2e6).withValues(alpha: 0.92),
      0xfff3e4f2 => const Color(0xffe6dbf7).withValues(alpha: 0.92),
      _ => Colors.white.withValues(alpha: 0.90),
    };
  }
  return switch (normalized) {
    0xfffff1d8 => const Color(0xff3d3122).withValues(alpha: 0.88),
    0xffffe5db => const Color(0xff1f3529).withValues(alpha: 0.88),
    0xffeee6fa => const Color(0xff1d3540).withValues(alpha: 0.88),
    0xfff8e3eb => const Color(0xff37252c).withValues(alpha: 0.88),
    0xfff3e4f2 => const Color(0xff2b2440).withValues(alpha: 0.88),
    _ => const Color(0xff1b2523).withValues(alpha: 0.88),
  };
}

/// The opaque colour a note card effectively renders as once its translucent
/// glass fill is composited over the app canvas. Use this — not
/// [brandNoteSurfaceColor] — when reasoning about text contrast.
Color effectiveNoteSurfaceColor(BuildContext context, int color) {
  return Color.alphaBlend(
    brandNoteSurfaceColor(context, color),
    canvasBaseColor(Theme.of(context).brightness),
  );
}

LinearGradient brandNoteGradient(BuildContext context, int color) {
  final normalized = normalizeBrandNoteColor(color);
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (dark) {
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: switch (normalized) {
        0xfffff1d8 => [
            const Color(0xff4c3c26).withValues(alpha: 0.92),
            const Color(0xff31291d).withValues(alpha: 0.88),
          ],
        0xffffe5db => [
            const Color(0xff26432f).withValues(alpha: 0.92),
            const Color(0xff1b2c24).withValues(alpha: 0.88),
          ],
        0xffeee6fa => [
            const Color(0xff204450).withValues(alpha: 0.92),
            const Color(0xff1a2c35).withValues(alpha: 0.88),
          ],
        0xfff8e3eb => [
            const Color(0xff432a33).withValues(alpha: 0.92),
            const Color(0xff2b1f25).withValues(alpha: 0.88),
          ],
        0xfff3e4f2 => [
            const Color(0xff322a4d).withValues(alpha: 0.92),
            const Color(0xff231e33).withValues(alpha: 0.88),
          ],
        _ => [
            const Color(0xff202b28).withValues(alpha: 0.92),
            const Color(0xff17201f).withValues(alpha: 0.88),
          ],
      },
    );
  }
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: switch (normalized) {
      0xfffff1d8 => [
          const Color(0xfffdeed6).withValues(alpha: 0.95),
          const Color(0xfff8dcbb).withValues(alpha: 0.9),
        ],
      0xffffe5db => [
          const Color(0xffe4f0e8).withValues(alpha: 0.95),
          const Color(0xffd0e4dc).withValues(alpha: 0.9),
        ],
      0xffeee6fa => [
          const Color(0xffe0edf4).withValues(alpha: 0.95),
          const Color(0xffcbdeeb).withValues(alpha: 0.9),
        ],
      0xfff8e3eb => [
          const Color(0xfffbeaed).withValues(alpha: 0.95),
          const Color(0xfff4d8dd).withValues(alpha: 0.9),
        ],
      0xfff3e4f2 => [
          const Color(0xffeee5fb).withValues(alpha: 0.95),
          const Color(0xffdfd1f5).withValues(alpha: 0.9),
        ],
      _ => [
          Colors.white.withValues(alpha: 0.94),
          Colors.white.withValues(alpha: 0.86),
        ],
    },
  );
}

/// Base wash behind the ambient mesh. Prefer [AppCanvas] for full screens.
BoxDecoration appCanvasDecoration(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0, 0.55, 1],
      colors: dark
          ? const [Color(0xff0d1513), canvasBaseDark, Color(0xff0f1417)]
          : const [Color(0xffefeaf2), canvasBaseLight, Color(0xfff3ece3)],
    ),
  );
}

ThemeData buildAppTheme(
  Brightness brightness, {
  Color? dynamicSeed,
  TargetPlatform platform = TargetPlatform.android,
}) {
  final dark = brightness == Brightness.dark;
  final isApple =
      platform == TargetPlatform.iOS || platform == TargetPlatform.macOS;
  final seedColor = dynamicSeed ?? _brandSeed;
  final baseScheme = ColorScheme.fromSeed(
    seedColor: seedColor,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.expressive,
    contrastLevel: 0.08,
  );
  final surface = dark ? const Color(0xff0f1615) : const Color(0xfff1ecf0);
  final field = dark ? const Color(0xff232e2c) : Colors.white;
  final typography = Typography.material2021(platform: platform);
  final scheme = baseScheme.copyWith(
    primary: dynamicSeed != null
        ? baseScheme.primary
        : dark
            ? const Color(0xff9fd0da)
            : const Color(0xff3f7f91),
    onPrimary: dynamicSeed != null
        ? baseScheme.onPrimary
        : dark
            ? const Color(0xff10343a)
            : Colors.white,
    primaryContainer: dynamicSeed != null
        ? baseScheme.primaryContainer
        : dark
            ? const Color(0xff22474f)
            : const Color(0xffd3e7ec),
    onPrimaryContainer: dynamicSeed != null
        ? baseScheme.onPrimaryContainer
        : dark
            ? const Color(0xffc9ecf1)
            : const Color(0xff21525d),
    secondary: dynamicSeed != null
        ? baseScheme.secondary
        : dark
            ? const Color(0xffc6b0f0)
            : const Color(0xff6f57a6),
    onSecondary: dynamicSeed != null
        ? baseScheme.onSecondary
        : dark
            ? const Color(0xff2f2352)
            : Colors.white,
    secondaryContainer: dynamicSeed != null
        ? baseScheme.secondaryContainer
        : dark
            ? const Color(0xff3a3060)
            : const Color(0xffe4d9f7),
    onSecondaryContainer: dynamicSeed != null
        ? baseScheme.onSecondaryContainer
        : dark
            ? const Color(0xffe6dbff)
            : const Color(0xff453573),
    tertiary: dynamicSeed != null
        ? baseScheme.tertiary
        : dark
            ? const Color(0xfff2cf8a)
            : const Color(0xff8a6a1f),
    onTertiary: dynamicSeed != null
        ? baseScheme.onTertiary
        : dark
            ? const Color(0xff3d2f0a)
            : Colors.white,
    tertiaryContainer: dynamicSeed != null
        ? baseScheme.tertiaryContainer
        : dark
            ? const Color(0xff4a3c14)
            : const Color(0xfffaeec4),
    onTertiaryContainer: dynamicSeed != null
        ? baseScheme.onTertiaryContainer
        : dark
            ? const Color(0xfffbe6b4)
            : const Color(0xff5b4611),
    surface: surface,
    surfaceContainerLowest:
        dark ? const Color(0xff0a1110) : const Color(0xffffffff),
    surfaceContainerLow:
        dark ? const Color(0xff161d1c) : const Color(0xfffbf9fb),
    surfaceContainer: dark ? const Color(0xff1c2423) : const Color(0xffeae5ec),
    surfaceContainerHigh:
        dark ? const Color(0xff232c2b) : const Color(0xffe2dce6),
    surfaceContainerHighest:
        dark ? const Color(0xff2c3634) : const Color(0xffd8d1de),
    onSurface: dark ? const Color(0xffecf1ee) : const Color(0xff211f26),
    onSurfaceVariant: dark ? const Color(0xffb2bfba) : const Color(0xff56515e),
    outline: dark ? const Color(0xff7a8783) : const Color(0xff7d7787),
    outlineVariant: dark ? const Color(0xff333e3b) : const Color(0xffcfc8d6),
    inverseSurface: dark ? const Color(0xffe6eae6) : const Color(0xff2a2830),
    onInverseSurface: dark ? const Color(0xff272e29) : const Color(0xfff4f2f6),
    surfaceTint: Colors.transparent,
  );
  final appTheme = SafernotesTheme(
    isApple: isApple,
    glassFill: dark
        ? const Color(0xff1b2523).withValues(alpha: 0.86)
        : Colors.white.withValues(alpha: 0.88),
    glassStroke: Colors.transparent,
    glassShadow: Colors.black.withValues(alpha: dark ? 0.34 : 0.10),
    glassBlur: 26,
    heroGradientStart: dynamicSeed ?? _brandSeed,
    heroGradientEnd: _brandAccent,
    noteCardRadius: AppRadii.card,
    controlRadius: AppRadii.xxl,
  );
  return ThemeData(
    platform: platform,
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Urbanist',
    fontFamilyFallback: const [
      'SF Pro Text',
      'Roboto',
      'Helvetica Neue',
      'Arial'
    ],
    scaffoldBackgroundColor: surface,
    visualDensity: VisualDensity.standard,
    splashFactory: isApple ? NoSplash.splashFactory : InkSparkle.splashFactory,
    extensions: [appTheme],
    textTheme: (dark ? typography.white : typography.black)
        .apply(
          fontFamily: 'Urbanist',
          fontFamilyFallback: const [
            'SF Pro Text',
            'Roboto',
            'Helvetica Neue',
            'Arial'
          ],
          bodyColor: scheme.onSurface,
          displayColor: scheme.onSurface,
        )
        .copyWith(
          displayLarge: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 62,
            height: 0.98,
            fontWeight: FontWeight.w300,
            letterSpacing: -0.5,
            color: scheme.onSurface,
          ),
          displayMedium: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 48,
            height: 1.0,
            fontWeight: FontWeight.w300,
            letterSpacing: -0.4,
            color: scheme.onSurface,
          ),
          headlineLarge: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 40,
            height: 1.04,
            fontWeight: FontWeight.w300,
            letterSpacing: -0.3,
            color: scheme.onSurface,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 34,
            height: 1.08,
            fontWeight: FontWeight.w300,
            letterSpacing: -0.2,
            color: scheme.onSurface,
          ),
          titleLarge: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 21,
            height: 1.2,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            color: scheme.onSurface,
          ),
          titleMedium: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 17,
            height: 1.25,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            color: scheme.onSurface,
          ),
          bodyLarge: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 16,
            height: 1.5,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
            color: scheme.onSurface,
          ),
          bodyMedium: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 15,
            height: 1.45,
            fontWeight: FontWeight.w400,
            letterSpacing: 0,
            color: scheme.onSurface,
          ),
          labelLarge: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 15,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
            color: scheme.onSurface,
          ),
        ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.45),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark
          ? const Color(0xff161d1c).withValues(alpha: 0.92)
          : Colors.white.withValues(alpha: 0.9),
      modalBackgroundColor: dark
          ? const Color(0xff161d1c).withValues(alpha: 0.92)
          : Colors.white.withValues(alpha: 0.9),
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadii.card)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: appTheme.glassFill,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(appTheme.noteCardRadius),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark
          ? const Color(0xff181f1e).withValues(alpha: 0.94)
          : Colors.white.withValues(alpha: 0.94),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.card),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.7)),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.lg,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        minimumSize: const Size(48, 54),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        minimumSize: const Size(48, 54),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: const CircleBorder(),
        visualDensity: VisualDensity.compact,
        iconSize: 19,
        minimumSize: const Size(38, 38),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 0,
      highlightElevation: 0,
      backgroundColor: dark ? Colors.white : scheme.onSurface,
      foregroundColor: dark ? const Color(0xff17201f) : Colors.white,
      shape: const CircleBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 74,
      elevation: 0,
      backgroundColor: Colors.transparent,
      indicatorColor: scheme.primary.withValues(alpha: 0.16),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 21,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(
        color: scheme.onSurface.withValues(alpha: 0.45),
        width: 1.5,
      ),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? brandLavender
            : Colors.transparent,
      ),
      checkColor: WidgetStatePropertyAll(
        dark ? const Color(0xff231a38) : Colors.white,
      ),
      shape: const CircleBorder(),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xl),
      ),
      contentTextStyle: TextStyle(
        color: scheme.onInverseSurface,
        fontWeight: FontWeight.w500,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      textStyle: TextStyle(
        color: scheme.onInverseSurface,
        fontSize: 12,
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.24),
      selectionHandleColor: scheme.primary,
    ),
  );
}

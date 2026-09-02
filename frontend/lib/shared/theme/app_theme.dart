import 'package:flutter/material.dart';

const _brandSeed = Color(0xff4f7f86);
const _brandAccent = Color(0xffd39a78);

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
  static const double xl = 20;
  static const double xxl = 24;
  static const double hero = 30;
  static const double pill = 999;
}

@immutable
class SafernotesTheme extends ThemeExtension<SafernotesTheme> {
  const SafernotesTheme({
    required this.isApple,
    required this.glassFill,
    required this.glassStroke,
    required this.glassShadow,
    required this.heroGradientStart,
    required this.heroGradientEnd,
    required this.noteCardRadius,
    required this.controlRadius,
  });

  final bool isApple;
  final Color glassFill;
  final Color glassStroke;
  final Color glassShadow;
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
        ? Colors.white.withValues(alpha: isApple ? 0.12 : 0.08)
        : Colors.white.withValues(alpha: isApple ? 0.68 : 0.86),
    glassStroke: dark
        ? Colors.white.withValues(alpha: 0.1)
        : Colors.white.withValues(alpha: 0.38),
    glassShadow: Colors.black.withValues(alpha: dark ? 0.2 : 0.06),
    heroGradientStart: theme.colorScheme.primary,
    heroGradientEnd: theme.colorScheme.secondary,
    noteCardRadius: AppRadii.hero,
    controlRadius: isApple ? AppRadii.xxl : AppRadii.xl,
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
      0xffffffff => scheme.surfaceContainerLow,
      0xfffff1d8 => const Color(0xfff3e6be),
      0xffffe5db => const Color(0xffd8e8db),
      0xffeee6fa => const Color(0xffdce7ee),
      0xfff8e3eb => const Color(0xffefdadd),
      0xfff3e4f2 => const Color(0xffe5dff0),
      _ => Color(normalized),
    };
  }
  return switch (normalized) {
    0xfffff1d8 => const Color(0xff373225),
    0xffffe5db => const Color(0xff25352c),
    0xffeee6fa => const Color(0xff26343b),
    0xfff8e3eb => const Color(0xff392a30),
    0xfff3e4f2 => const Color(0xff302b3b),
    _ => scheme.surfaceContainerLow,
  };
}

LinearGradient brandNoteGradient(BuildContext context, int color) {
  final normalized = normalizeBrandNoteColor(color);
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (dark) {
    final surface = brandNoteSurfaceColor(context, normalized);
    final tint = switch (normalized) {
      0xfffff1d8 => const Color(0xff4a3c2d),
      0xffffe5db => const Color(0xff29433b),
      0xffeee6fa => const Color(0xff2d4350),
      0xfff8e3eb => const Color(0xff49323b),
      0xfff3e4f2 => const Color(0xff3c3150),
      _ => const Color(0xff263332),
    };
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color.lerp(surface, tint, 0.46)!, surface],
    );
  }
  return LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: switch (normalized) {
      0xfffff1d8 => const [Color(0xfff4e9c9), Color(0xffefd9c9)],
      0xffffe5db => const [Color(0xffdcebdc), Color(0xffd4e7e9)],
      0xffeee6fa => const [Color(0xffdce9ef), Color(0xffe4def0)],
      0xfff8e3eb => const [Color(0xfff1dfe2), Color(0xfff1e3d9)],
      0xfff3e4f2 => const [Color(0xffe8e1f2), Color(0xffdce8ef)],
      _ => const [Color(0xfffcfcfb), Color(0xffedf4f3)],
    },
  );
}

BoxDecoration appCanvasDecoration(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final dark = scheme.brightness == Brightness.dark;
  return BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      stops: const [0, 0.5, 1],
      colors: dark
          ? const [Color(0xff111514), Color(0xff151817), Color(0xff171519)]
          : const [Color(0xfff7f8f7), Color(0xfff1f5f4), Color(0xfff7f2f0)],
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
  final surface = dark ? const Color(0xff111414) : const Color(0xfff3f5f4);
  final field = dark ? const Color(0xff232827) : const Color(0xffe7edeb);
  final typography = Typography.material2021(platform: platform);
  final scheme = baseScheme.copyWith(
    primary: dynamicSeed != null
        ? baseScheme.primary
        : dark
            ? const Color(0xff9fd5d9)
            : const Color(0xff396c74),
    onPrimary: dynamicSeed != null
        ? baseScheme.onPrimary
        : dark
            ? const Color(0xff12383d)
            : Colors.white,
    primaryContainer: dynamicSeed != null
        ? baseScheme.primaryContainer
        : dark
            ? const Color(0xff244347)
            : const Color(0xffd7e9e8),
    onPrimaryContainer: dynamicSeed != null
        ? baseScheme.onPrimaryContainer
        : dark
            ? const Color(0xffc6ecee)
            : const Color(0xff244f55),
    secondary: dynamicSeed != null
        ? baseScheme.secondary
        : dark
            ? const Color(0xfff3c5a8)
            : const Color(0xff956344),
    onSecondary: dynamicSeed != null
        ? baseScheme.onSecondary
        : dark
            ? const Color(0xff4d2e1e)
            : Colors.white,
    secondaryContainer: dynamicSeed != null
        ? baseScheme.secondaryContainer
        : dark
            ? const Color(0xff4b382d)
            : const Color(0xfff3e2d7),
    onSecondaryContainer: dynamicSeed != null
        ? baseScheme.onSecondaryContainer
        : dark
            ? const Color(0xffffe1cf)
            : const Color(0xff67442f),
    tertiary: dynamicSeed != null
        ? baseScheme.tertiary
        : dark
            ? const Color(0xffd8b7e9)
            : const Color(0xff77558f),
    onTertiary: dynamicSeed != null
        ? baseScheme.onTertiary
        : dark
            ? const Color(0xff402451)
            : Colors.white,
    tertiaryContainer: dynamicSeed != null
        ? baseScheme.tertiaryContainer
        : dark
            ? const Color(0xff44344e)
            : const Color(0xffeadff1),
    onTertiaryContainer: dynamicSeed != null
        ? baseScheme.onTertiaryContainer
        : dark
            ? const Color(0xfff1d9fc)
            : const Color(0xff553968),
    surface: surface,
    surfaceContainerLowest:
        dark ? const Color(0xff0c0f0f) : const Color(0xffffffff),
    surfaceContainerLow:
        dark ? const Color(0xff1a1f1e) : const Color(0xfffbfcfb),
    surfaceContainer: dark ? const Color(0xff202524) : const Color(0xffebefed),
    surfaceContainerHigh:
        dark ? const Color(0xff282e2c) : const Color(0xffe3e9e6),
    surfaceContainerHighest:
        dark ? const Color(0xff323937) : const Color(0xffd9e1dd),
    onSurface: dark ? const Color(0xffedf1ef) : const Color(0xff1c2422),
    onSurfaceVariant: dark ? const Color(0xffb4bfbb) : const Color(0xff505b57),
    outline: dark ? const Color(0xff788580) : const Color(0xff798681),
    outlineVariant: dark ? const Color(0xff35403c) : const Color(0xffccd6d1),
    inverseSurface: dark ? const Color(0xffe6eae6) : const Color(0xff2b302c),
    onInverseSurface: dark ? const Color(0xff272e29) : const Color(0xfff3f5f2),
    surfaceTint: Colors.transparent,
  );
  final appTheme = SafernotesTheme(
    isApple: isApple,
    glassFill: dark
        ? Colors.white.withValues(alpha: isApple ? 0.10 : 0.06)
        : Colors.white.withValues(alpha: isApple ? 0.64 : 0.82),
    glassStroke: dark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.24),
    glassShadow: Colors.black.withValues(alpha: dark ? 0.14 : 0.045),
    heroGradientStart: dynamicSeed ?? _brandSeed,
    heroGradientEnd: _brandAccent,
    noteCardRadius: AppRadii.hero,
    controlRadius: isApple ? AppRadii.xxl : AppRadii.xl,
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
            fontSize: 56,
            height: 1.02,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            color: scheme.onSurface,
          ),
          displayMedium: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 44,
            height: 1.06,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            color: scheme.onSurface,
          ),
          headlineLarge: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 34,
            height: 1.12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            color: scheme.onSurface,
          ),
          headlineMedium: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 28,
            height: 1.16,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            color: scheme.onSurface,
          ),
          titleLarge: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 22,
            height: 1.2,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            color: scheme.onSurface,
          ),
          titleMedium: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 17,
            height: 1.25,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
            color: scheme.onSurface,
          ),
          bodyLarge: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 17,
            height: 1.45,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            color: scheme.onSurface,
          ),
          bodyMedium: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 15,
            height: 1.42,
            fontWeight: FontWeight.w500,
            letterSpacing: 0,
            color: scheme.onSurface,
          ),
          labelLarge: TextStyle(
            fontFamily: 'Urbanist',
            fontSize: 15,
            height: 1.2,
            fontWeight: FontWeight.w700,
            letterSpacing: 0,
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
      color: scheme.outlineVariant.withValues(alpha: 0.55),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      modalBackgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(AppRadii.hero)),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(appTheme.noteCardRadius),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.hero),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(appTheme.controlRadius),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(appTheme.controlRadius),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(appTheme.controlRadius),
        borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.8)),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(appTheme.controlRadius),
        ),
        minimumSize: const Size(48, 52),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(appTheme.controlRadius),
        ),
        minimumSize: const Size(48, 52),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.pill),
        ),
        visualDensity: VisualDensity.compact,
        iconSize: 19,
        minimumSize: const Size(36, 36),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: isApple ? 0 : 2,
      highlightElevation: isApple ? 0 : 3,
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.xxl),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: isApple ? 74 : 72,
      elevation: 0,
      backgroundColor:
          isApple ? Colors.transparent : scheme.surfaceContainerLow,
      indicatorColor: isApple
          ? scheme.primary.withValues(alpha: 0.14)
          : scheme.primaryContainer.withValues(alpha: 0.92),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w600,
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          size: 21,
          color: states.contains(WidgetState.selected)
              ? scheme.primary
              : scheme.onSurfaceVariant,
        ),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: scheme.outline, width: 1.5),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadii.xs)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(
        color: scheme.onInverseSurface,
        fontWeight: FontWeight.w500,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(6),
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

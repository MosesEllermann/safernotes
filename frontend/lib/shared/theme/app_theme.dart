import 'package:flutter/material.dart';

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
  if (Theme.of(context).brightness != Brightness.dark) {
    return Color(normalized);
  }
  return switch (normalized) {
    0xfffff1d8 => const Color(0xff3a2e19),
    0xffffe5db => const Color(0xff42271e),
    0xffeee6fa => const Color(0xff33253c),
    0xfff8e3eb => const Color(0xff3d222b),
    0xfff3e4f2 => const Color(0xff3b2639),
    _ => Theme.of(context).colorScheme.surfaceContainerLow,
  };
}

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final baseScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff8051a8),
    brightness: brightness,
  );
  final surface = dark ? const Color(0xff130f13) : const Color(0xfffbf8fa);
  final field = dark ? const Color(0xff211a20) : const Color(0xfffffdfd);
  final typography = Typography.material2021(platform: TargetPlatform.macOS);
  final scheme = baseScheme.copyWith(
    primary: dark ? const Color(0xffd7a9e8) : const Color(0xff8051a8),
    onPrimary: dark ? const Color(0xff35163f) : Colors.white,
    primaryContainer: dark ? const Color(0xff51305d) : const Color(0xfff1e4f4),
    onPrimaryContainer:
        dark ? const Color(0xffffeaff) : const Color(0xff35183d),
    secondary: dark ? const Color(0xfff2a28f) : const Color(0xff9f5146),
    onSecondary: dark ? const Color(0xff4a1711) : Colors.white,
    secondaryContainer:
        dark ? const Color(0xff63372f) : const Color(0xffffe6df),
    onSecondaryContainer:
        dark ? const Color(0xffffe9e3) : const Color(0xff4c1d19),
    tertiary: dark ? const Color(0xff9eb7a3) : const Color(0xff5d7463),
    onTertiary: dark ? const Color(0xff18311f) : Colors.white,
    tertiaryContainer: dark ? const Color(0xff344a39) : const Color(0xffe3ede5),
    onTertiaryContainer:
        dark ? const Color(0xffdfece1) : const Color(0xff213328),
    surface: surface,
    surfaceContainerLowest:
        dark ? const Color(0xff0e0b0e) : const Color(0xfffffdfd),
    surfaceContainerLow:
        dark ? const Color(0xff191319) : const Color(0xfff7f0f5),
    surfaceContainer: dark ? const Color(0xff201820) : const Color(0xfff2e9ef),
    surfaceContainerHigh:
        dark ? const Color(0xff282027) : const Color(0xffeadde6),
    surfaceContainerHighest:
        dark ? const Color(0xff332832) : const Color(0xffdfceda),
    onSurface: dark ? const Color(0xfffff5fb) : const Color(0xff21181f),
    onSurfaceVariant: dark ? const Color(0xffd8c4d1) : const Color(0xff584b54),
    outline: dark ? const Color(0xffa78f9f) : const Color(0xff75636f),
    outlineVariant: dark ? const Color(0xff554450) : const Color(0xffd7c6d1),
    surfaceTint: Colors.transparent,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Inter',
    fontFamilyFallback: const ['Roboto', 'Helvetica Neue', 'Arial'],
    scaffoldBackgroundColor: surface,
    visualDensity: VisualDensity.compact,
    textTheme: (dark ? typography.white : typography.black).apply(
      fontFamily: 'Inter',
      fontFamilyFallback: const ['Roboto', 'Helvetica Neue', 'Arial'],
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      backgroundColor: surface,
      foregroundColor: scheme.onSurface,
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.7)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(48, 44),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        minimumSize: const Size(48, 44),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: const CircleBorder(),
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        minimumSize: const Size(34, 34),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      side: BorderSide(color: scheme.outline, width: 1.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xfff5e8f0) : const Color(0xff2c222a),
      contentTextStyle: TextStyle(
        color: dark ? const Color(0xff241a21) : Colors.white,
        fontWeight: FontWeight.w500,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? const Color(0xfff5e8f0) : const Color(0xff2c222a),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(
        color: dark ? const Color(0xff241a21) : Colors.white,
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

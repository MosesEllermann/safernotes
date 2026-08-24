import 'package:flutter/material.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final baseScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff23755c),
    brightness: brightness,
  );
  final surface = dark ? const Color(0xff0b0f0d) : const Color(0xfff2f5f3);
  final field = dark ? const Color(0xff1b231f) : Colors.white;
  final typography = Typography.material2021(platform: TargetPlatform.macOS);
  final scheme = baseScheme.copyWith(
    primary: dark ? const Color(0xff79dbb4) : const Color(0xff176b50),
    onPrimary: dark ? const Color(0xff052d20) : Colors.white,
    surface: surface,
    surfaceContainerLowest:
        dark ? const Color(0xff080b0a) : const Color(0xffffffff),
    surfaceContainerLow:
        dark ? const Color(0xff141a17) : const Color(0xffeaf0ed),
    surfaceContainer: dark ? const Color(0xff19211d) : const Color(0xffe2eae6),
    surfaceContainerHigh:
        dark ? const Color(0xff202a25) : const Color(0xffd8e2dd),
    surfaceContainerHighest:
        dark ? const Color(0xff29352f) : const Color(0xffccd9d3),
    onSurface: dark ? const Color(0xfff5f8f6) : const Color(0xff121714),
    onSurfaceVariant: dark ? const Color(0xffc9d2cd) : const Color(0xff3f4b45),
    outline: dark ? const Color(0xff8b9992) : const Color(0xff596960),
    outlineVariant: dark ? const Color(0xff46534d) : const Color(0xffb8c7c0),
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
      backgroundColor: dark ? const Color(0xffe8ecea) : const Color(0xff202522),
      contentTextStyle: TextStyle(
        color: dark ? const Color(0xff171a1b) : Colors.white,
        fontWeight: FontWeight.w500,
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? const Color(0xffe8ecea) : const Color(0xff202522),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: TextStyle(
        color: dark ? const Color(0xff171a1b) : Colors.white,
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

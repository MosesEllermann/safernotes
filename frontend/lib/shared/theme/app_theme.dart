import 'package:flutter/material.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final baseScheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff23755c),
    brightness: brightness,
  );
  final surface = dark ? const Color(0xff101216) : const Color(0xfff7f8f7);
  final field = dark ? const Color(0xff1a1e23) : Colors.white;
  final typography = Typography.material2021(platform: TargetPlatform.macOS);
  final scheme = baseScheme.copyWith(
    primary: dark ? const Color(0xff6fc6a5) : const Color(0xff1f7258),
    onPrimary: dark ? const Color(0xff073828) : Colors.white,
    surface: surface,
    onSurface: dark ? const Color(0xfff2f4f3) : const Color(0xff171a1b),
    onSurfaceVariant: dark ? const Color(0xffc3c9c6) : const Color(0xff505855),
    outline: dark ? const Color(0xff77817d) : const Color(0xff68736f),
    outlineVariant: dark ? const Color(0xff3d4542) : const Color(0xffd2d8d5),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
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

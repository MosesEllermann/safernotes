import 'package:flutter/material.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xff2563eb),
    brightness: brightness,
  );
  final surface = dark ? const Color(0xff111827) : const Color(0xfff6f7f9);
  final field = dark ? const Color(0xff1f2937) : Colors.white;
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    fontFamily: 'Inter',
    fontFamilyFallback: const ['Roboto', 'Helvetica Neue', 'Arial'],
    scaffoldBackgroundColor: surface,
    visualDensity: VisualDensity.compact,
    textTheme:
        Typography.material2021(platform: TargetPlatform.macOS).black.apply(
              fontFamily: 'Roboto',
              fontFamilyFallback: const ['Helvetica Neue', 'Arial'],
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
    dividerTheme:
        DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.55)),
    cardTheme: CardThemeData(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      clipBehavior: Clip.antiAlias,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: field,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide.none,
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
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safernotes_app/shared/theme/app_theme.dart';

void main() {
  test('system font replaces Urbanist throughout light and dark themes', () {
    for (final brightness in Brightness.values) {
      final standard = buildAppTheme(brightness);
      final system = buildAppTheme(brightness, useSystemFont: true);
      expect(standard.textTheme.bodyMedium!.fontFamily, 'Urbanist');
      final typography =
          Typography.material2021(platform: TargetPlatform.android);
      final expected =
          (brightness == Brightness.dark ? typography.white : typography.black)
              .bodyMedium!
              .fontFamily;
      for (final style in [
        system.textTheme.displayLarge,
        system.textTheme.displayMedium,
        system.textTheme.headlineLarge,
        system.textTheme.headlineMedium,
        system.textTheme.titleLarge,
        system.textTheme.titleMedium,
        system.textTheme.bodyLarge,
        system.textTheme.bodyMedium,
        system.textTheme.labelLarge,
        system.textTheme.labelSmall,
        system.primaryTextTheme.bodyMedium,
      ]) {
        expect(style!.fontFamily, expected);
        expect(style.fontFamilyFallback ?? [], isNot(contains('Urbanist')));
      }
    }
  });

  test('dark ambient mesh stays deliberately subdued', () {
    expect(
      ambientMeshIntensity(Brightness.dark),
      lessThan(ambientMeshIntensity(Brightness.light)),
    );
    expect(ambientMeshIntensity(Brightness.dark), lessThan(0.5));
    for (final color in ambientMeshColors(Brightness.dark)) {
      expect(color.computeLuminance(), lessThan(0.04));
    }
  });

  for (final brightness in Brightness.values) {
    test('text contrast is readable in $brightness with custom device colors',
        () {
      for (final seed in <Color?>[
        null,
        const Color(0xffedb92e),
        const Color(0xff406bbb),
        const Color(0xffbe4778),
      ]) {
        for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
          final scheme = buildAppTheme(
            brightness,
            dynamicSeed: seed,
            platform: platform,
          ).colorScheme;
          for (final (foreground, background) in [
            (scheme.onPrimary, scheme.primary),
            (scheme.onPrimaryContainer, scheme.primaryContainer),
            (scheme.onSecondary, scheme.secondary),
            (scheme.onSecondaryContainer, scheme.secondaryContainer),
            (scheme.onTertiary, scheme.tertiary),
            (scheme.onTertiaryContainer, scheme.tertiaryContainer),
            (scheme.onSurface, scheme.surface),
            (scheme.onSurfaceVariant, scheme.surfaceContainerHighest),
            (scheme.onInverseSurface, scheme.inverseSurface),
          ]) {
            expect(_contrast(foreground, background), greaterThanOrEqualTo(4.5),
                reason: '$platform, $seed, $foreground on $background');
          }
        }
      }
    });

    testWidgets(
        'all note colors keep body and metadata readable in $brightness',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(brightness),
        home: Builder(builder: (context) {
          final scheme = Theme.of(context).colorScheme;
          final surfaces = brandNoteColors
              .map((color) => brandNoteSurfaceColor(context, color))
              .toSet();
          expect(surfaces, hasLength(brandNoteColors.length));
          // Note cards are frosted glass, so readability depends on the colour
          // they composite to over the app canvas, not on the translucent fill.
          final rendered = brandNoteColors
              .map((color) => effectiveNoteSurfaceColor(context, color))
              .toSet();
          for (final surface in rendered) {
            for (final text in [scheme.onSurface, scheme.onSurfaceVariant]) {
              expect(_contrast(text, surface), greaterThanOrEqualTo(4.5),
                  reason: '$text on $surface');
            }
          }
          expect(
            brandNoteSurfaceColor(context, 0xfffef3c7),
            brandNoteSurfaceColor(context, 0xfffff1d8),
          );
          return const SizedBox.shrink();
        }),
      ));
    });
  }
}

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
}

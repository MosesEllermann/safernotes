import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/main.dart';
import 'package:safernotes_app/shared/app/app_preferences.dart';

void main() {
  testWidgets('auth follows theme preferences at mobile and desktop widths',
      (tester) async {
    SharedPreferences.setMockInitialValues({'zk.pref.theme': 'dark'});
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const ProviderScope(child: SafernotesApp()));
    await tester.pumpAndSettle();
    final preferences = ProviderScope.containerOf(
      tester.element(find.byType(SafernotesApp)),
    ).read(appPreferencesProvider.notifier);

    for (final width in [390.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 900);
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await preferences.setThemeMode(mode);
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byType(TextFormField).first)).brightness,
          mode == ThemeMode.light ? Brightness.light : Brightness.dark,
        );
        final field = tester.widget<TextField>(find.byType(TextField).first);
        final enabledBorder = field.decoration?.enabledBorder;
        final focusedBorder = field.decoration?.focusedBorder;
        expect(field.decoration?.filled, isTrue);
        expect(enabledBorder, isA<OutlineInputBorder>());
        expect(
          (enabledBorder! as OutlineInputBorder).borderSide.style,
          BorderStyle.solid,
        );
        expect(
          (enabledBorder).borderSide.color.a,
          greaterThan(0.4),
        );
        expect(
          (focusedBorder! as OutlineInputBorder).borderSide.width,
          greaterThan((enabledBorder).borderSide.width),
        );
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('shows auth screen on first launch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: SafernotesApp()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsWidgets);
    expect(find.text('Login'), findsWidgets);
  });

  testWidgets('mobile starts directly with compact auth form', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: SafernotesApp()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile-login-page')), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Email'), findsOneWidget);

    await tester.tap(find.text('Register'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile-register-page')), findsOneWidget);
    expect(find.text('Create your vault'), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);
    expect(find.text('Workspace name'), findsOneWidget);

    await tester.tap(find.text('Login').first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile-login-page')), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Workspace name'), findsNothing);
  });
}

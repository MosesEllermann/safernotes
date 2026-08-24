import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/main.dart';

void main() {
  testWidgets('shows auth screen on first launch', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const ProviderScope(child: SafernotesApp()));
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsWidgets);
    expect(find.text('Login'), findsWidgets);
  });

  testWidgets('mobile starts with separate login and registration choices',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const ProviderScope(child: SafernotesApp()));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile-auth-landing')), findsOneWidget);
    expect(find.text('Safernotes'), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);
    expect(find.text('Email'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Register'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile-register-page')), findsOneWidget);
    expect(find.text('Create your vault'), findsOneWidget);
    expect(find.text('Welcome back'), findsNothing);
    expect(find.text('Workspace name'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile-login-page')), findsOneWidget);
    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.text('Workspace name'), findsNothing);
  });
}

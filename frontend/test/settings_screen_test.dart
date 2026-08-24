import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/settings/settings_screen.dart';
import 'package:safernotes_app/shared/models/session.dart';

void main() {
  testWidgets('desktop settings use stable category navigation',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_SignedOutAuthController.new),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('desktop-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-settings')), findsNothing);
    expect(
      tester
          .widget<IndexedStack>(
            find.byKey(const ValueKey('desktop-settings-pages')),
          )
          .index,
      0,
    );

    await tester.tap(find.byKey(const ValueKey('settings-nav-plan')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IndexedStack>(
            find.byKey(const ValueKey('desktop-settings-pages')),
          )
          .index,
      1,
    );

    await tester.tap(find.byKey(const ValueKey('settings-nav-security')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IndexedStack>(
            find.byKey(const ValueKey('desktop-settings-pages')),
          )
          .index,
      2,
    );
  });

  testWidgets('compact settings keep the single scrolling layout',
      (tester) async {
    tester.view.physicalSize = const Size(600, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_SignedOutAuthController.new),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mobile-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('desktop-settings')), findsNothing);
    expect(find.byKey(const ValueKey('settings-nav-plan')), findsNothing);
  });
}

class _SignedOutAuthController extends AuthController {
  @override
  Future<AppSession?> build() async => null;
}

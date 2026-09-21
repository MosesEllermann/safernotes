import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/settings/settings_screen.dart';
import 'package:safernotes_app/shared/app/sync_server_settings.dart';
import 'package:safernotes_app/shared/models/session.dart';
import 'package:safernotes_app/shared/providers.dart';

void main() {
  testWidgets('desktop settings exposes self-hosted sync configuration',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_SignedInAuthController.new),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('desktop-settings')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings-nav-sync')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('sync-server-settings')), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('sync-server-url-field')),
      'notes.example.test/',
    );
    await tester.tap(find.byKey(const ValueKey('save-sync-server-url')));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextField>(
            find.byKey(const ValueKey('sync-server-url-field')),
          )
          .controller
          ?.text,
      'https://notes.example.test',
    );
    expect(
      (await SharedPreferences.getInstance())
          .getString('safernotes.sync_server_url'),
      'https://notes.example.test',
    );
  });

  testWidgets('offline settings still lets users configure a future server',
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
    expect(find.byKey(const ValueKey('sync-server-settings')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-nav-security')), findsNothing);
  });

  test('server URL normalization supports HTTPS defaults and local HTTP', () {
    expect(
      normalizeSyncServerUrl('notes.example.test/'),
      'https://notes.example.test',
    );
    expect(
      normalizeSyncServerUrl('http://192.168.1.20:8080/'),
      'http://192.168.1.20:8080',
    );
    expect(
      () => normalizeSyncServerUrl('ftp://notes.example.test'),
      throwsFormatException,
    );
  });

  test('saved server URL immediately configures the API client', () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(syncServerUrlProvider.future);

    await container
        .read(syncServerUrlProvider.notifier)
        .setUrl('https://vault.example.test/');

    expect(
      container.read(apiClientProvider).baseUrl,
      'https://vault.example.test',
    );
  });
}

class _SignedOutAuthController extends AuthController {
  @override
  Future<AppSession?> build() async => null;
}

class _SignedInAuthController extends AuthController {
  @override
  Future<AppSession?> build() async => const AppSession(
        email: 'owner@example.test',
        accessToken: 'access-token',
        refreshToken: 'refresh-token',
        defaultTenant: 'tenant-id',
        masterKey: [1, 2, 3],
      );
}

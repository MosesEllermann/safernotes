import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/auth/auth_screen.dart';
import 'package:safernotes_app/main.dart';
import 'package:safernotes_app/shared/app/app_preferences.dart';
import 'package:safernotes_app/shared/models/encrypted_envelope.dart';
import 'package:safernotes_app/shared/models/session.dart';

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
    expect(find.byKey(const ValueKey('use-offline-only')), findsOneWidget);
  });

  testWidgets('offline-only entry does not validate account fields',
      (tester) async {
    final auth = _KeyboardAuthController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith(() => auth)],
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final offlineButton = find.byKey(const ValueKey('use-offline-only'));
    await tester.ensureVisible(offlineButton);
    await tester.tap(offlineButton);
    await tester.pump();

    expect(auth.offlineVaultCreations, 1);
    expect(find.text('Enter a valid email'), findsNothing);
  });

  testWidgets('login supports autofill and keyboard submission',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'safernotes.sync_server_url': 'https://notes.example.test',
    });
    await tester.pumpWidget(const ProviderScope(child: SafernotesApp()));
    await tester.pumpAndSettle();

    final fields = tester.widgetList<TextField>(find.byType(TextField));
    final email = fields.firstWhere(
      (field) => field.autofillHints?.contains(AutofillHints.email) ?? false,
    );
    final password = fields.firstWhere(
      (field) => field.autofillHints?.contains(AutofillHints.password) ?? false,
    );
    expect(email.autofillHints, contains(AutofillHints.email));
    expect(password.autofillHints, contains(AutofillHints.password));
    expect(password.textInputAction, TextInputAction.done);
    expect(password.onSubmitted, isNotNull);
  });

  testWidgets('enter submits autofilled login from either field',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'safernotes.sync_server_url': 'https://notes.example.test',
    });
    final auth = _KeyboardAuthController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith(() => auth)],
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), 'person@example.test');
    await tester.enterText(fields.at(2), 'correct horse battery staple');

    // Password managers commonly leave focus in the username field after
    // filling both values. Enter should submit there as well as on password.
    await tester.tap(fields.at(1));
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await tester.pump();

    expect(auth.loginCalls, 1);
    expect(auth.lastEmail, 'person@example.test');
  });

  testWidgets('enter on the registration password opens recovery onboarding',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      'safernotes.sync_server_url': 'https://notes.example.test',
    });
    final auth = _KeyboardAuthController();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith(() => auth)],
        child: const MaterialApp(home: AuthScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Register').first);
    await tester.pumpAndSettle();

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), 'person@example.test');
    await tester.enterText(fields.at(2), 'correct horse battery staple');
    expect(
      tester.widget<TextField>(find.byType(TextField).at(2)).textInputAction,
      TextInputAction.done,
    );

    await tester.tap(fields.at(2));
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(auth.registrationPreparations, 1);
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
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

class _KeyboardAuthController extends AuthController {
  int loginCalls = 0;
  int registrationPreparations = 0;
  int offlineVaultCreations = 0;
  String? lastEmail;

  @override
  Future<AppSession?> build() async => null;

  @override
  Future<void> login({required String email, required String password}) async {
    loginCalls += 1;
    lastEmail = email;
  }

  @override
  Future<void> createOfflineVault() async {
    offlineVaultCreations += 1;
  }

  @override
  Future<RegistrationKeyMaterial> prepareRegistration({
    required String password,
    required String workspaceName,
  }) async {
    registrationPreparations += 1;
    return _registrationMaterial;
  }
}

const _envelope = EncryptedEnvelope(
  version: 1,
  algorithm: 'AES_256_GCM',
  nonce: 'nonce',
  ciphertext: 'ciphertext',
);

const _registrationMaterial = RegistrationKeyMaterial(
  masterKey: [0, 1, 2, 3],
  recoveryKey: 'test-recovery-key',
  kdfAlgorithm: 'pbkdf2-sha256',
  kdfParams: {'iterations': 1, 'bits': 256},
  passwordSalt: 'salt',
  publicEncryptionKey: 'public-encryption-key',
  publicSigningKey: 'public-signing-key',
  publicEncryptionKeyFingerprint: 'encryption-fingerprint',
  publicSigningKeyFingerprint: 'signing-fingerprint',
  encryptedMasterKey: _envelope,
  encryptedPrivateEncryptionKey: _envelope,
  encryptedPrivateSigningKey: _envelope,
  recoveryWrapper: _envelope,
  deviceNameCiphertext: _envelope,
  defaultTenantNameCiphertext: _envelope,
);

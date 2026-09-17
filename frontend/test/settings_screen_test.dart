import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/settings/settings_screen.dart';
import 'package:safernotes_app/shared/api/api_client.dart';
import 'package:safernotes_app/shared/models/session.dart';
import 'package:safernotes_app/shared/providers.dart';

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

  testWidgets('web billing renders only Essential and Pro from the API',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_SignedInAuthController.new),
          apiClientProvider.overrideWithValue(_billingApiClient()),
          webBillingEnabledProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(home: SettingsScreen(openPlan: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('billing-plan-essential')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('billing-plan-pro')), findsOneWidget);
    expect(find.text('Team'), findsNothing);
    expect(find.text('Enterprise'), findsNothing);
    expect(
      find.byKey(const ValueKey('native-billing-unavailable')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('billing-support-email')),
      findsOneWidget,
    );
  });

  testWidgets('native billing shows status without plans or purchase links',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_SignedInAuthController.new),
          apiClientProvider.overrideWithValue(_billingApiClient()),
          webBillingEnabledProvider.overrideWithValue(false),
        ],
        child: const MaterialApp(home: SettingsScreen(openPlan: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('native-billing-unavailable')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('billing-plan-essential')), findsNothing);
    expect(find.byKey(const ValueKey('billing-plan-pro')), findsNothing);
    expect(find.byKey(const ValueKey('manage-subscription')), findsNothing);
  });

  testWidgets('web checkout opens Creem and records the pending plan',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    Uri? launchedUri;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_SignedInAuthController.new),
          apiClientProvider.overrideWithValue(_billingApiClient()),
          webBillingEnabledProvider.overrideWithValue(true),
          webUrlLauncherProvider.overrideWithValue((uri) async {
            launchedUri = uri;
            return true;
          }),
        ],
        child: const MaterialApp(home: SettingsScreen(openPlan: true)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Select').first);
    await tester.pumpAndSettle();

    expect(launchedUri, Uri.parse('https://checkout.creem.io/ch_essential'));
    final preferences = await SharedPreferences.getInstance();
    expect(
      preferences.getString(pendingBillingPlanPreferenceKey),
      'essential',
    );
  });

  testWidgets('successful checkout return enters payment activation state',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      pendingBillingPlanPreferenceKey: 'essential',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_SignedInAuthController.new),
          apiClientProvider.overrideWithValue(
            _billingApiClient(currentPlan: 'essential'),
          ),
          webBillingEnabledProvider.overrideWithValue(true),
          billingReturnStatusProvider.overrideWithValue('success'),
        ],
        child: const MaterialApp(home: SettingsScreen(openPlan: true)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump();
    expect(
      find.byKey(const ValueKey('current-plan-summary')),
      findsOneWidget,
    );
    expect(find.text('Your plan is active'), findsOneWidget);
    expect(find.text('Essential · €18/year'), findsOneWidget);
    expect(find.byKey(const ValueKey('billing-notice')), findsNothing);
  });

  testWidgets('return without success is shown as incomplete checkout',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({
      pendingBillingPlanPreferenceKey: 'pro',
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_SignedInAuthController.new),
          apiClientProvider.overrideWithValue(_billingApiClient()),
          webBillingEnabledProvider.overrideWithValue(true),
          billingReturnStatusProvider.overrideWithValue(null),
        ],
        child: const MaterialApp(home: SettingsScreen(openPlan: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Checkout was not completed.'), findsOneWidget);
  });

  testWidgets('paid web users can open Creem subscription management',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    Uri? launchedUri;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_SignedInAuthController.new),
          apiClientProvider.overrideWithValue(
            _billingApiClient(currentPlan: 'pro'),
          ),
          webBillingEnabledProvider.overrideWithValue(true),
          webUrlLauncherProvider.overrideWithValue((uri) async {
            launchedUri = uri;
            return true;
          }),
        ],
        child: const MaterialApp(home: SettingsScreen(openPlan: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('current-plan-summary')),
      findsOneWidget,
    );
    expect(find.text('Your plan is active'), findsOneWidget);
    expect(find.text('Pro · €60/year'), findsOneWidget);
    expect(find.text('Active plan'), findsOneWidget);
    expect(find.text('Select'), findsNothing);
    expect(
      tester.widget(find.byKey(const ValueKey('manage-subscription'))),
      isA<FilledButton>(),
    );

    final summaryTop = tester
        .getTopLeft(find.byKey(const ValueKey('current-plan-summary')))
        .dy;
    final proCardTop =
        tester.getTopLeft(find.byKey(const ValueKey('billing-plan-pro'))).dy;
    expect(summaryTop, lessThan(proCardTop));

    await tester.tap(find.byKey(const ValueKey('manage-subscription')));
    await tester.pumpAndSettle();

    expect(launchedUri, Uri.parse('https://creem.io/portal/customer'));
  });

  testWidgets('active plan layout remains clear on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_SignedInAuthController.new),
          apiClientProvider.overrideWithValue(
            _billingApiClient(currentPlan: 'essential'),
          ),
          webBillingEnabledProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(home: SettingsScreen(openPlan: true)),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('current-plan-summary')),
      findsOneWidget,
    );
    expect(find.text('Your plan is active'), findsOneWidget);
    expect(find.text('Active plan'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('manage-subscription')),
      findsOneWidget,
    );
  });
}

ApiClient _billingApiClient({String currentPlan = 'free'}) {
  return ApiClient(
    baseUrl: 'http://example.test',
    httpClient: MockClient((request) async {
      if (request.url.path == '/api/v1/subscription') {
        return http.Response(
          jsonEncode({'plan': currentPlan, 'status': 'active'}),
          200,
        );
      }
      if (request.url.path == '/api/v1/subscription/plans') {
        return http.Response(
          jsonEncode({
            'currency': 'EUR',
            'plans': [
              {
                'key': 'essential',
                'name': 'Essential',
                'currency': 'EUR',
                'pricing': {
                  'monthly_equivalent_cents': 150,
                  'yearly_cents': 1800,
                },
                'limits': {
                  'storage_bytes': 5368709120,
                  'max_notes': 5000,
                  'max_collaborators_per_note': 5,
                },
                'features': {'version_history_days': 90},
                'checkout_enabled': true,
              },
              {
                'key': 'pro',
                'name': 'Pro',
                'currency': 'EUR',
                'pricing': {
                  'monthly_equivalent_cents': 500,
                  'yearly_cents': 6000,
                },
                'limits': {
                  'storage_bytes': 26843545600,
                  'max_notes': null,
                  'max_collaborators_per_note': 25,
                },
                'features': {'version_history_days': 365},
                'checkout_enabled': true,
              },
            ],
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/subscription/checkout') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final plan = body['plan'] as String;
        return http.Response(
          jsonEncode({
            'status': 'ready',
            'provider': 'creem',
            'target_plan': plan,
            'checkout_url': 'https://checkout.creem.io/ch_$plan',
          }),
          200,
        );
      }
      if (request.url.path == '/api/v1/subscription/portal') {
        return http.Response(
          '{"status":"ready","portal_url":"https://creem.io/portal/customer"}',
          200,
        );
      }
      return http.Response('{}', 404);
    }),
  );
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

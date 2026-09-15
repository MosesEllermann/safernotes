import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safernotes_app/shared/api/api_client.dart';
import 'package:safernotes_app/shared/models/encrypted_envelope.dart';

void main() {
  test('login converts request timeouts to a server unreachable error',
      () async {
    final client = ApiClient(
      baseUrl: 'http://example.test',
      httpClient: MockClient((_) => Completer<http.Response>().future),
      requestTimeout: const Duration(milliseconds: 1),
    );

    await expectLater(
      client.login(email: 'user@example.test', password: 'password'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 0)
            .having((error) => error.message, 'message', 'Server unreachable.'),
      ),
    );
  });

  test('login converts client network failures to a server unreachable error',
      () async {
    final client = ApiClient(
      baseUrl: 'http://example.test',
      httpClient: MockClient((_) => throw http.ClientException('No route')),
    );

    await expectLater(
      client.login(email: 'user@example.test', password: 'password'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 0)
            .having((error) => error.message, 'message', 'Server unreachable.'),
      ),
    );
  });

  test('login converts malformed server payloads to a friendly API error',
      () async {
    final client = ApiClient(
      baseUrl: 'http://example.test',
      httpClient:
          MockClient((_) async => http.Response('<html>bad</html>', 200)),
    );

    await expectLater(
      client.login(email: 'user@example.test', password: 'password'),
      throwsA(
        isA<ApiException>()
            .having((error) => error.statusCode, 'statusCode', 200)
            .having(
              (error) => error.message,
              'message',
              'The server returned an invalid response. Please try again.',
            ),
      ),
    );
  });

  test('recovery-key update sends only the encrypted wrapper', () async {
    late http.Request captured;
    final client = ApiClient(
      baseUrl: 'http://example.test',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"configured":true}', 200);
      }),
    );
    const wrapper = EncryptedEnvelope(
      version: 1,
      algorithm: 'AES_256_GCM',
      nonce: 'nonce',
      ciphertext: 'ciphertext',
      keyId: 'key-id',
    );

    await client.updateRecoveryKey(
      accessToken: 'access-token',
      recoveryWrapper: wrapper,
    );

    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(captured.method, 'PATCH');
    expect(captured.url.path, '/api/v1/auth/recovery-key');
    expect(body.keys, ['recovery_wrapper']);
    expect(body.toString(), isNot(contains('recovery_key')));
    expect(body['recovery_wrapper'], wrapper.toJson());
  });

  test('email verification status uses the authenticated status endpoint',
      () async {
    late http.Request captured;
    final client = ApiClient(
      baseUrl: 'http://example.test',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"email_verified":true}', 200);
      }),
    );

    final response = await client.fetchEmailVerificationStatus(
      accessToken: 'access-token',
    );

    expect(captured.method, 'GET');
    expect(captured.url.path, '/api/v1/auth/email/verification/status');
    expect(captured.headers['Authorization'], 'Bearer access-token');
    expect(response['email_verified'], isTrue);
  });

  test('subscription usage parses storage and note quotas', () async {
    late http.Request captured;
    final client = ApiClient(
      baseUrl: 'http://example.test',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'plan': 'free',
            'usage': {
              'storage_bytes_used': 12828672,
              'ciphertext_bytes_used': 12828672,
              'notes_bytes_used': 245760,
              'attachments_bytes_used': 12582912,
              'attachments_count': 3,
              'notes_count': 42,
            },
            'limits': {
              'storage_bytes': 524288000,
              'max_notes': 500,
            },
          }),
          200,
        );
      }),
    );

    final usage = await client.fetchSubscriptionUsage(
      accessToken: 'access-token',
      tenant: 'tenant-id',
    );

    expect(captured.method, 'GET');
    expect(captured.url.path, '/api/v1/subscription/usage');
    expect(captured.url.queryParameters['tenant'], 'tenant-id');
    expect(captured.headers['Authorization'], 'Bearer access-token');
    expect(usage.plan, 'free');
    expect(usage.storageBytesUsed, 12828672);
    expect(usage.storageBytesLimit, 524288000);
    expect(usage.notesBytesUsed, 245760);
    expect(usage.attachmentsBytesUsed, 12582912);
    expect(usage.notesCount, 42);
    expect(usage.maxNotes, 500);
  });

  test('billing plans come from the public subscription catalogue', () async {
    late http.Request captured;
    final client = ApiClient(
      baseUrl: 'http://example.test',
      httpClient: MockClient((request) async {
        captured = request;
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
                  'billing_interval': 'year',
                },
                'limits': {
                  'storage_bytes': 5368709120,
                  'max_notes': 5000,
                  'max_collaborators_per_note': 5,
                },
                'features': {'version_history_days': 90},
                'checkout_enabled': true,
              },
            ],
          }),
          200,
        );
      }),
    );

    final catalog = await client.fetchBillingPlans(
      accessToken: 'access-token',
    );

    expect(captured.method, 'GET');
    expect(captured.url.path, '/api/v1/subscription/plans');
    expect(captured.headers['Authorization'], 'Bearer access-token');
    expect(catalog.currency, 'EUR');
    expect(catalog.plans.single.key, 'essential');
    expect(catalog.plans.single.yearlyCents, 1800);
    expect(catalog.plans.single.storageBytes, 5368709120);
    expect(catalog.plans.single.checkoutEnabled, isTrue);
  });

  test('billing portal uses the authenticated tenant endpoint', () async {
    late http.Request captured;
    final client = ApiClient(
      baseUrl: 'http://example.test',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          '{"status":"ready","portal_url":"https://creem.io/portal/1"}',
          200,
        );
      }),
    );

    final portal = await client.createBillingPortal(
      accessToken: 'access-token',
      tenant: 'tenant-id',
    );

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/v1/subscription/portal');
    expect(captured.headers['Authorization'], 'Bearer access-token');
    expect(jsonDecode(captured.body), {'tenant': 'tenant-id'});
    expect(portal.status, 'ready');
    expect(portal.portalUrl, 'https://creem.io/portal/1');
  });

  test('empty trash uses the authenticated bulk endpoint', () async {
    late http.Request captured;
    final client = ApiClient(
      baseUrl: 'http://example.test',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response('{"deleted_count":3}', 200);
      }),
    );

    final deletedCount = await client.emptyTrash('access-token');

    expect(captured.method, 'POST');
    expect(captured.url.path, '/api/v1/notes/trash/empty/');
    expect(captured.headers['Authorization'], 'Bearer access-token');
    expect(jsonDecode(captured.body), isEmpty);
    expect(deletedCount, 3);
  });
}

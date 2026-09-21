import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safernotes_app/shared/api/api_client.dart';
import 'package:safernotes_app/shared/models/encrypted_envelope.dart';

void main() {
  test('client has no hosted sync endpoint unless explicitly configured',
      () async {
    final client = ApiClient();

    await expectLater(
      client.login(email: 'user@example.test', password: 'password'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'No sync server is configured.',
        ),
      ),
    );
  });

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

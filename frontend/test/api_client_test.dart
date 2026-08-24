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
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:safernotes_app/shared/api/api_client.dart';

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
}

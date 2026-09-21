import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/shared/api/api_client.dart';
import 'package:safernotes_app/shared/crypto/crypto_service.dart';
import 'package:safernotes_app/shared/providers.dart';
import 'package:safernotes_app/shared/storage/offline_store.dart';

void main() {
  test('creates and persists an offline-only vault without server credentials',
      () async {
    final store = _MemoryOfflineStore(null);
    final container = ProviderContainer(
      overrides: [offlineStoreProvider.overrideWithValue(store)],
    );
    addTearDown(container.dispose);

    await container.read(authControllerProvider.future);
    await container.read(authControllerProvider.notifier).createOfflineVault();

    final session = container.read(authControllerProvider).requireValue!;
    expect(session.isOfflineOnly, isTrue);
    expect(session.accessToken, isEmpty);
    expect(session.defaultTenant, isEmpty);
    expect(session.masterKey, hasLength(32));
    expect(store.session?['mode'], 'offline');
  });

  test('refreshing verification updates state and the stored session',
      () async {
    final store = _MemoryOfflineStore({
      'email': 'verified@example.test',
      'accessToken': 'access-token',
      'refreshToken': 'refresh-token',
      'defaultTenant': 'tenant',
      'masterKey': [0, 1, 2, 3],
      'emailVerified': false,
    });
    final container = ProviderContainer(
      overrides: [
        offlineStoreProvider.overrideWithValue(store),
        apiClientProvider.overrideWithValue(_VerifiedApiClient()),
      ],
    );
    addTearDown(container.dispose);

    final initial = await container.read(authControllerProvider.future);
    expect(initial?.emailVerified, isFalse);

    final verified = await container
        .read(authControllerProvider.notifier)
        .refreshEmailVerificationStatus();

    expect(verified, isTrue);
    expect(
      container.read(authControllerProvider).valueOrNull?.emailVerified,
      isTrue,
    );
    expect(store.session?['emailVerified'], isTrue);
  });
}

class _VerifiedApiClient extends ApiClient {
  @override
  Future<Map<String, dynamic>> fetchEmailVerificationStatus({
    required String accessToken,
  }) async {
    expect(accessToken, 'access-token');
    return {'email_verified': true};
  }
}

class _MemoryOfflineStore extends OfflineStore {
  _MemoryOfflineStore(this.session) : super(CryptoService());

  Map<String, dynamic>? session;

  @override
  Future<Map<String, dynamic>?> loadSessionJson() async => session;

  @override
  Future<void> saveSessionJson(Map<String, dynamic> json) async {
    session = Map<String, dynamic>.from(json);
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safernotes_app/shared/api/api_client.dart';
import 'package:safernotes_app/shared/crypto/crypto_service.dart';
import 'package:safernotes_app/shared/storage/offline_store.dart';

const apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);

final cryptoServiceProvider = Provider<CryptoService>((ref) => CryptoService());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(baseUrl: apiBaseUrl),
);

final offlineStoreProvider = Provider<OfflineStore>(
  (ref) => OfflineStore(ref.watch(cryptoServiceProvider)),
);

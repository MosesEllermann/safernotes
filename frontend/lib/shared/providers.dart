import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safernotes_app/shared/api/api_client.dart';
import 'package:safernotes_app/shared/crypto/crypto_service.dart';
import 'package:safernotes_app/shared/storage/offline_store.dart';

const productionApiBaseUrl = 'https://api.safernotes.com';
const _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');

final apiBaseUrl = _resolveApiBaseUrl();

String _resolveApiBaseUrl() {
  if (_configuredApiBaseUrl.isNotEmpty) return _configuredApiBaseUrl;
  return productionApiBaseUrl;
}

final cryptoServiceProvider = Provider<CryptoService>((ref) => CryptoService());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(baseUrl: apiBaseUrl),
);

final offlineStoreProvider = Provider<OfflineStore>(
  (ref) => OfflineStore(ref.watch(cryptoServiceProvider)),
);

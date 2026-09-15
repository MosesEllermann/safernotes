import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safernotes_app/shared/api/api_client.dart';
import 'package:safernotes_app/shared/crypto/crypto_service.dart';
import 'package:safernotes_app/shared/storage/offline_store.dart';
import 'package:url_launcher/url_launcher.dart';

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

typedef WebUrlLauncher = Future<bool> Function(Uri uri);

final webBillingEnabledProvider = Provider<bool>((ref) => kIsWeb);

final billingReturnStatusProvider = Provider<String?>(
  (ref) => kIsWeb ? Uri.base.queryParameters['billing'] : null,
);

final webUrlLauncherProvider = Provider<WebUrlLauncher>(
  (ref) => (uri) => launchUrl(uri, webOnlyWindowName: '_self'),
);

final offlineStoreProvider = Provider<OfflineStore>(
  (ref) => OfflineStore(ref.watch(cryptoServiceProvider)),
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safernotes_app/shared/api/api_client.dart';
import 'package:safernotes_app/shared/app/sync_server_settings.dart';
import 'package:safernotes_app/shared/crypto/crypto_service.dart';
import 'package:safernotes_app/shared/storage/offline_store.dart';

final cryptoServiceProvider = Provider<CryptoService>((ref) => CryptoService());

final apiClientProvider = Provider<ApiClient>(
  (ref) => ApiClient(
    baseUrl:
        ref.watch(syncServerUrlProvider).valueOrNull ?? bundledSyncServerUrl,
  ),
);

final offlineStoreProvider = Provider<OfflineStore>(
  (ref) => OfflineStore(ref.watch(cryptoServiceProvider)),
);

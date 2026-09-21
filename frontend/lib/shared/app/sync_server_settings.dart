import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _configuredApiBaseUrl = String.fromEnvironment('API_BASE_URL');
const _serverUrlPreferenceKey = 'safernotes.sync_server_url';

bool get syncServerUrlIsLocked =>
    kIsWeb && _configuredApiBaseUrl == 'same-origin';

String get bundledSyncServerUrl {
  if (_configuredApiBaseUrl == 'same-origin') {
    return kIsWeb ? Uri.base.origin : '';
  }
  return normalizeSyncServerUrl(_configuredApiBaseUrl);
}

String normalizeSyncServerUrl(String input) {
  var value = input.trim();
  if (value.isEmpty) return '';
  if (!value.contains('://')) value = 'https://$value';
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasAuthority ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.query.isNotEmpty ||
      uri.fragment.isNotEmpty) {
    throw const FormatException('Enter a valid HTTP or HTTPS server URL.');
  }
  return uri.replace(path: uri.path.replaceAll(RegExp(r'/+$'), '')).toString();
}

final syncServerUrlProvider =
    AsyncNotifierProvider<SyncServerUrlController, String>(
  SyncServerUrlController.new,
);

class SyncServerUrlController extends AsyncNotifier<String> {
  @override
  Future<String> build() async {
    if (syncServerUrlIsLocked) return bundledSyncServerUrl;
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getString(_serverUrlPreferenceKey) ?? '';
    return saved.isEmpty ? bundledSyncServerUrl : normalizeSyncServerUrl(saved);
  }

  Future<String> setUrl(String value) async {
    if (syncServerUrlIsLocked) return bundledSyncServerUrl;
    final normalized = normalizeSyncServerUrl(value);
    final preferences = await SharedPreferences.getInstance();
    if (normalized.isEmpty) {
      await preferences.remove(_serverUrlPreferenceKey);
    } else {
      await preferences.setString(_serverUrlPreferenceKey, normalized);
    }
    state = AsyncData(normalized);
    return normalized;
  }
}

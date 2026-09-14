import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/shared/crypto/crypto_service.dart';
import 'package:safernotes_app/shared/models/encrypted_envelope.dart';
import 'package:safernotes_app/shared/models/note.dart';

abstract interface class LocalVaultKeyStorage {
  Future<String?> read();

  Future<void> write(String value);
}

class SecureLocalVaultKeyStorage implements LocalVaultKeyStorage {
  const SecureLocalVaultKeyStorage();

  static const _key = 'zk.localVaultKey';
  static const _storage = FlutterSecureStorage();

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

class OfflineStore {
  OfflineStore(
    this._crypto, {
    LocalVaultKeyStorage? vaultKeyStorage,
  }) : _vaultKeyStorage = vaultKeyStorage ?? const SecureLocalVaultKeyStorage();

  static const _sessionKey = 'zk.session';
  static const _notesKey = 'zk.notes';
  static const _vaultRecoveryPrefix = 'zk.localVaultRecovery';
  static const _unreadableBackupSuffix = '.unreadableBackup';
  static const _cacheFormatVersion = 2;
  static const _recoveryFormatVersion = 1;

  final CryptoService _crypto;
  final LocalVaultKeyStorage _vaultKeyStorage;
  List<int>? _cachedVaultKey;
  Future<List<int>>? _vaultKeyLoad;
  List<int>? _cachedVaultIdKey;
  String? _cachedVaultId;
  String? _preparedRecoveryScope;
  String? _preparedRecoveryVaultId;

  Future<List<int>?> storedLocalVaultKey() async {
    final encoded = await _vaultKeyStorage.read();
    if (encoded == null || encoded.isEmpty) return null;
    try {
      final key = _crypto.decodeBase64UrlNoPad(encoded);
      return key.length == 32 ? key : null;
    } on FormatException {
      return null;
    }
  }

  Future<List<int>> localVaultKey() {
    final cached = _cachedVaultKey;
    if (cached != null) return Future.value(List<int>.from(cached));
    final activeLoad = _vaultKeyLoad;
    if (activeLoad != null) return activeLoad;
    final load = _loadOrCreateLocalVaultKey();
    _vaultKeyLoad = load;
    return load.whenComplete(() {
      if (identical(_vaultKeyLoad, load)) _vaultKeyLoad = null;
    });
  }

  Future<List<int>> _loadOrCreateLocalVaultKey() async {
    final existing = await storedLocalVaultKey();
    if (existing != null) {
      _cachedVaultKey = List<int>.from(existing);
      return List<int>.from(existing);
    }
    final key = _crypto.randomBytes(32);
    await _replaceLocalVaultKey(key);
    return List<int>.from(key);
  }

  Future<void> _replaceLocalVaultKey(List<int> key) async {
    if (key.length != 32) {
      throw const FormatException('A local vault key must contain 32 bytes.');
    }
    await _vaultKeyStorage.write(_crypto.base64UrlNoPad(key));
    _cachedVaultKey = List<int>.from(key);
    _cachedVaultIdKey = null;
    _cachedVaultId = null;
    _preparedRecoveryScope = null;
    _preparedRecoveryVaultId = null;
  }

  Future<void> saveSessionJson(Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    final storedVault = await storedLocalVaultKey();
    var vault = await localVaultKey();
    final recovered = await _recoverVaultForSession(
      prefs,
      json,
      currentVault: vault,
      currentWasMissing: storedVault == null,
    );
    if (!_sameBytes(vault, recovered)) {
      await _replaceLocalVaultKey(recovered);
      vault = recovered;
    }

    // Persist the recovery wrapper first. A crash can therefore never leave a
    // newly encrypted session without a master-key-protected copy of its key.
    await _ensureVaultRecovery(prefs, json, vault);
    await prefs.setString(
      _sessionKey,
      await _encryptCacheValue(jsonEncode(json), vault),
    );
  }

  Future<Map<String, dynamic>?> loadSessionJson() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null) return null;
    try {
      var vault = await localVaultKey();
      final decoded = await _decryptCacheValue(raw, vault);
      final session =
          Map<String, dynamic>.from(jsonDecode(decoded.value) as Map);
      final originalVault = vault;
      final recovered = await _recoverVaultForSession(
        prefs,
        session,
        currentVault: vault,
        currentWasMissing: false,
      );
      if (!_sameBytes(vault, recovered)) {
        await _replaceLocalVaultKey(recovered);
        vault = recovered;
      }
      await _ensureVaultRecovery(prefs, session, vault);
      if (decoded.legacy || !_sameBytes(originalVault, vault)) {
        await prefs.setString(
          _sessionKey,
          await _encryptCacheValue(jsonEncode(session), vault),
        );
      }
      return session;
    } catch (error) {
      if (!_isUnreadableEnvelope(error)) rethrow;
      await _quarantineUnreadableValue(prefs, _sessionKey, raw);
      return null;
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where(
          (key) =>
              key == _sessionKey ||
              key.startsWith('$_sessionKey.') ||
              key == _notesKey ||
              key.startsWith('$_notesKey.') ||
              key == _vaultRecoveryPrefix ||
              key.startsWith('$_vaultRecoveryPrefix.'),
        );
    for (final key in keys.toList(growable: false)) {
      await prefs.remove(key);
    }
  }

  Future<List<PlainNote>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final notesKey = await _currentNotesKey();
    final raw = prefs.getString(notesKey);
    if (raw == null) return [];
    try {
      final vault = await localVaultKey();
      final decoded = await _decryptCacheValue(raw, vault);
      final list = decoded.value.length >= _isolateJsonThreshold
          ? await compute(_decodeJsonList, decoded.value)
          : jsonDecode(decoded.value) as List;
      final notes = list
          .map((item) =>
              PlainNote.fromPlainJson(Map<String, dynamic>.from(item as Map)))
          .toList();
      if (decoded.legacy) {
        await prefs.setString(
          notesKey,
          await _encryptCacheValue(decoded.value, vault),
        );
      }
      return notes;
    } catch (error) {
      if (!_isUnreadableEnvelope(error)) rethrow;
      await _quarantineUnreadableValue(prefs, notesKey, raw);
      return [];
    }
  }

  Future<void> saveNotes(List<PlainNote> notes) async {
    final prefs = await SharedPreferences.getInstance();
    final notesKey = await _currentNotesKey();
    final vault = await localVaultKey();
    final serialized = notes.map((note) => note.toPlainJson()).toList();
    final value = notes.length >= _isolateNoteThreshold
        ? await compute(_encodeJsonList, serialized)
        : jsonEncode(serialized);
    await prefs.setString(
      notesKey,
      await _encryptCacheValue(value, vault),
    );
  }

  Future<String> _currentNotesKey() async {
    final session = await loadSessionJson();
    if (session == null) return _notesKey;
    return _notesKeyForScope(_scopeForSession(session));
  }

  String _scopeForSession(Map<String, dynamic> session) {
    final email = session['email'] as String? ?? '';
    final tenant = session['defaultTenant'] as String? ?? '';
    return _crypto.base64UrlNoPad(utf8.encode('$email:$tenant'));
  }

  String _notesKeyForScope(String scope) => '$_notesKey.$scope';

  String _recoveryKeyForScope(String scope) => '$_vaultRecoveryPrefix.$scope';

  Future<_DecodedCacheValue> _decryptCacheValue(
    String raw,
    List<int> vault,
  ) async {
    final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    final version = json['cacheVersion'];
    final legacy = version == null;
    late final Map<String, dynamic> envelopeJson;
    if (legacy) {
      envelopeJson = json;
    } else {
      if (version != _cacheFormatVersion || json['payload'] is! Map) {
        throw const FormatException('Unsupported local cache format.');
      }
      final expectedKeyId = json['keyId'];
      if (expectedKeyId is! String ||
          expectedKeyId != await _vaultKeyId(vault)) {
        throw const _LocalCacheKeyMismatch();
      }
      envelopeJson = Map<String, dynamic>.from(json['payload'] as Map);
    }
    final envelope = EncryptedEnvelope.fromJson(envelopeJson);
    return _DecodedCacheValue(
      await _crypto.decryptString(envelope, vault),
      legacy: legacy,
    );
  }

  Future<String> _encryptCacheValue(String value, List<int> vault) async {
    final envelope = await _crypto.encryptString(value, vault);
    return jsonEncode({
      'cacheVersion': _cacheFormatVersion,
      'keyId': await _vaultKeyId(vault),
      'payload': envelope.toJson(),
    });
  }

  Future<String> _vaultKeyId(List<int> vault) async {
    final cachedKey = _cachedVaultIdKey;
    final cachedId = _cachedVaultId;
    if (cachedKey != null && cachedId != null && _sameBytes(cachedKey, vault)) {
      return cachedId;
    }
    final id = await _crypto.sha256Text(
      'safernotes-local-vault-key-id-v1:${_crypto.base64UrlNoPad(vault)}',
    );
    _cachedVaultIdKey = List<int>.from(vault);
    _cachedVaultId = id;
    return id;
  }

  _SessionRecoveryContext? _recoveryContext(
    Map<String, dynamic> session,
  ) {
    final rawMasterKey = session['masterKey'];
    if (rawMasterKey is! List) return null;
    final masterKey =
        rawMasterKey.whereType<num>().map((e) => e.toInt()).toList();
    if (masterKey.length != rawMasterKey.length ||
        masterKey.length != 32 ||
        masterKey.any((byte) => byte < 0 || byte > 255)) {
      return null;
    }
    final scope = _scopeForSession(session);
    if (scope.isEmpty) return null;
    return _SessionRecoveryContext(scope: scope, masterKey: masterKey);
  }

  Future<void> _ensureVaultRecovery(
    SharedPreferences prefs,
    Map<String, dynamic> session,
    List<int> vault,
  ) async {
    final context = _recoveryContext(session);
    if (context == null) return;
    final vaultId = await _vaultKeyId(vault);
    if (_preparedRecoveryScope == context.scope &&
        _preparedRecoveryVaultId == vaultId) {
      return;
    }
    final recoveryStorageKey = _recoveryKeyForScope(context.scope);
    final existing = prefs.getString(recoveryStorageKey);
    if (existing != null) {
      final recovered = await _readRecoveryVault(existing, context);
      if (recovered != null && _sameBytes(recovered, vault)) {
        _preparedRecoveryScope = context.scope;
        _preparedRecoveryVaultId = vaultId;
        return;
      }
    }
    final wrappingKey = await _crypto.deriveLocalVaultRecoveryKey(
      masterKey: context.masterKey,
      accountScope: context.scope,
    );
    final envelope = await _crypto.encryptString(
      _crypto.base64UrlNoPad(vault),
      wrappingKey,
    );
    await prefs.setString(
      recoveryStorageKey,
      jsonEncode({
        'version': _recoveryFormatVersion,
        'vaultKeyId': vaultId,
        'payload': envelope.toJson(),
      }),
    );
    _preparedRecoveryScope = context.scope;
    _preparedRecoveryVaultId = vaultId;
  }

  Future<List<int>> _recoverVaultForSession(
    SharedPreferences prefs,
    Map<String, dynamic> session, {
    required List<int> currentVault,
    required bool currentWasMissing,
  }) async {
    final context = _recoveryContext(session);
    if (context == null) return currentVault;
    final currentVaultId = await _vaultKeyId(currentVault);
    if (_preparedRecoveryScope == context.scope &&
        _preparedRecoveryVaultId == currentVaultId) {
      return currentVault;
    }
    final recoveryRaw = prefs.getString(_recoveryKeyForScope(context.scope));
    if (recoveryRaw == null) return currentVault;
    final recoveredVault = await _readRecoveryVault(recoveryRaw, context);
    if (recoveredVault == null || _sameBytes(recoveredVault, currentVault)) {
      return currentVault;
    }

    final notesKey = _notesKeyForScope(context.scope);
    for (final key in [notesKey, _notesKey]) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      if (await _canDecryptCacheValue(raw, currentVault)) return currentVault;
      if (await _canDecryptCacheValue(raw, recoveredVault)) {
        return recoveredVault;
      }
    }

    for (final key in [
      '$notesKey$_unreadableBackupSuffix',
      '$_notesKey$_unreadableBackupSuffix',
    ]) {
      final raw = prefs.getString(key);
      if (raw == null) continue;
      if (await _canDecryptCacheValue(raw, recoveredVault)) {
        final activeKey = key.substring(
          0,
          key.length - _unreadableBackupSuffix.length,
        );
        if (!prefs.containsKey(activeKey)) {
          await prefs.setString(activeKey, raw);
        }
        return recoveredVault;
      }
    }

    final sessionBackup = prefs.getString(
      '$_sessionKey$_unreadableBackupSuffix',
    );
    if (sessionBackup != null &&
        await _canDecryptCacheValue(sessionBackup, recoveredVault)) {
      return recoveredVault;
    }
    return currentWasMissing ? recoveredVault : currentVault;
  }

  Future<List<int>?> _readRecoveryVault(
    String raw,
    _SessionRecoveryContext context,
  ) async {
    try {
      final json = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (json['version'] != _recoveryFormatVersion ||
          json['payload'] is! Map ||
          json['vaultKeyId'] is! String) {
        return null;
      }
      final wrappingKey = await _crypto.deriveLocalVaultRecoveryKey(
        masterKey: context.masterKey,
        accountScope: context.scope,
      );
      final encoded = await _crypto.decryptString(
        EncryptedEnvelope.fromJson(
          Map<String, dynamic>.from(json['payload'] as Map),
        ),
        wrappingKey,
      );
      final vault = _crypto.decodeBase64UrlNoPad(encoded);
      if (vault.length != 32 ||
          json['vaultKeyId'] != await _vaultKeyId(vault)) {
        return null;
      }
      return vault;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _canDecryptCacheValue(String raw, List<int> vault) async {
    try {
      await _decryptCacheValue(raw, vault);
      return true;
    } catch (_) {
      return false;
    }
  }

  bool _isUnreadableEnvelope(Object error) =>
      error is SecretBoxAuthenticationError ||
      error is FormatException ||
      error is TypeError ||
      error is _LocalCacheKeyMismatch;

  Future<void> _quarantineUnreadableValue(
    SharedPreferences prefs,
    String key,
    String value,
  ) async {
    final backupKey = '$key$_unreadableBackupSuffix';
    if (!prefs.containsKey(backupKey)) {
      await prefs.setString(backupKey, value);
    }
    await prefs.remove(key);
  }

  bool _sameBytes(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i += 1) {
      difference |= a[i] ^ b[i];
    }
    return difference == 0;
  }
}

class _DecodedCacheValue {
  const _DecodedCacheValue(this.value, {required this.legacy});

  final String value;
  final bool legacy;
}

class _SessionRecoveryContext {
  const _SessionRecoveryContext({
    required this.scope,
    required this.masterKey,
  });

  final String scope;
  final List<int> masterKey;
}

class _LocalCacheKeyMismatch implements Exception {
  const _LocalCacheKeyMismatch();
}

const _isolateNoteThreshold = 48;
const _isolateJsonThreshold = 128 * 1024;

String _encodeJsonList(List<Map<String, dynamic>> value) => jsonEncode(value);

List<dynamic> _decodeJsonList(String value) => jsonDecode(value) as List;

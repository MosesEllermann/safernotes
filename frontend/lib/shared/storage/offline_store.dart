import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/shared/crypto/crypto_service.dart';
import 'package:safernotes_app/shared/models/encrypted_envelope.dart';
import 'package:safernotes_app/shared/models/note.dart';

class OfflineStore {
  OfflineStore(this._crypto);

  static const _sessionKey = 'zk.session';
  static const _vaultKeyStorage = 'zk.localVaultKey';
  static const _notesKey = 'zk.notes';

  final CryptoService _crypto;
  final _secureStorage = const FlutterSecureStorage();

  Future<List<int>> localVaultKey() async {
    final existing = await _secureStorage.read(key: _vaultKeyStorage);
    if (existing != null) return _crypto.decodeBase64UrlNoPad(existing);
    final key = _crypto.randomBytes(32);
    await _secureStorage.write(
        key: _vaultKeyStorage, value: _crypto.base64UrlNoPad(key));
    return key;
  }

  Future<void> saveSessionJson(Map<String, dynamic> json) async {
    final prefs = await SharedPreferences.getInstance();
    final vault = await localVaultKey();
    final envelope = await _crypto.encryptString(jsonEncode(json), vault);
    await prefs.setString(_sessionKey, jsonEncode(envelope.toJson()));
  }

  Future<Map<String, dynamic>?> loadSessionJson() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null) return null;
    final vault = await localVaultKey();
    final envelope = EncryptedEnvelope.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map));
    final decoded = await _crypto.decryptString(envelope, vault);
    return Map<String, dynamic>.from(jsonDecode(decoded) as Map);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    final notesKey = await _currentNotesKey();
    await prefs.remove(_sessionKey);
    await prefs.remove(notesKey);
    await prefs.remove(_notesKey);
  }

  Future<List<PlainNote>> loadNotes() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _currentNotesKey());
    if (raw == null) return [];
    final vault = await localVaultKey();
    final envelope = EncryptedEnvelope.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as Map));
    final decoded = await _crypto.decryptString(envelope, vault);
    final list = jsonDecode(decoded) as List;
    return list
        .map((item) =>
            PlainNote.fromPlainJson(Map<String, dynamic>.from(item as Map)))
        .toList();
  }

  Future<void> saveNotes(List<PlainNote> notes) async {
    final prefs = await SharedPreferences.getInstance();
    final vault = await localVaultKey();
    final envelope = await _crypto.encryptString(
      jsonEncode(notes.map((note) => note.toPlainJson()).toList()),
      vault,
    );
    await prefs.setString(
        await _currentNotesKey(), jsonEncode(envelope.toJson()));
  }

  Future<String> _currentNotesKey() async {
    final session = await loadSessionJson();
    if (session == null) return _notesKey;
    final email = session['email'] as String? ?? '';
    final tenant = session['defaultTenant'] as String? ?? '';
    final scope = _crypto.base64UrlNoPad(utf8.encode('$email:$tenant'));
    return '$_notesKey.$scope';
  }
}

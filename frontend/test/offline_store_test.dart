import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:safernotes_app/shared/crypto/crypto_service.dart';
import 'package:safernotes_app/shared/models/note.dart';
import 'package:safernotes_app/shared/storage/offline_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('unreadable note cache is preserved and no longer blocks startup',
      () async {
    SharedPreferences.setMockInitialValues({});
    final crypto = CryptoService();
    final encrypted = await crypto.encryptString('[]', List.filled(32, 1));
    final raw = jsonEncode(encrypted.toJson());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zk.notes', raw);
    final storage = _MemoryVaultKeyStorage(
      crypto.base64UrlNoPad(List.filled(32, 2)),
    );
    final store = OfflineStore(crypto, vaultKeyStorage: storage);

    expect(await store.loadNotes(), isEmpty);
    expect(prefs.getString('zk.notes'), isNull);
    expect(prefs.getString('zk.notes.unreadableBackup'), raw);
  });

  test('unreadable session cache falls back to signed-out state', () async {
    SharedPreferences.setMockInitialValues({});
    final crypto = CryptoService();
    final encrypted = await crypto.encryptString('{}', List.filled(32, 3));
    final raw = jsonEncode(encrypted.toJson());
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zk.session', raw);
    final storage = _MemoryVaultKeyStorage(
      crypto.base64UrlNoPad(List.filled(32, 4)),
    );
    final store = OfflineStore(crypto, vaultKeyStorage: storage);

    expect(await store.loadSessionJson(), isNull);
    expect(prefs.getString('zk.session'), isNull);
    expect(prefs.getString('zk.session.unreadableBackup'), raw);
  });

  test('new cache records include a format version and vault key id', () async {
    SharedPreferences.setMockInitialValues({});
    final crypto = CryptoService();
    final vault = List<int>.generate(32, (index) => index);
    final storage = _MemoryVaultKeyStorage(crypto.base64UrlNoPad(vault));
    final store = OfflineStore(crypto, vaultKeyStorage: storage);
    final session = _session(masterKey: List.filled(32, 7));

    await store.saveSessionJson(session);
    await store.saveNotes([_offlineOnlyNote]);

    final prefs = await SharedPreferences.getInstance();
    final sessionRecord = _json(prefs.getString('zk.session')!);
    final notesRecord = _json(prefs.getString(_notesKey(crypto))!);
    final recoveryRecord = _json(prefs.getString(_recoveryKey(crypto))!);
    for (final record in [sessionRecord, notesRecord]) {
      expect(record['cacheVersion'], 2);
      expect(record['keyId'], isA<String>());
      expect(record['payload'], isA<Map>());
    }
    expect(recoveryRecord['version'], 1);
    expect(recoveryRecord['vaultKeyId'], sessionRecord['keyId']);
    expect((await store.loadNotes()).single.title, _offlineOnlyNote.title);
  });

  test('legacy session and note envelopes migrate without losing data',
      () async {
    SharedPreferences.setMockInitialValues({});
    final crypto = CryptoService();
    final vault = List.filled(32, 8);
    final session = _session(masterKey: List.filled(32, 9));
    final legacySession =
        await crypto.encryptString(jsonEncode(session), vault);
    final legacyNotes = await crypto.encryptString(
      jsonEncode([_offlineOnlyNote.toPlainJson()]),
      vault,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zk.session', jsonEncode(legacySession.toJson()));
    await prefs.setString(_notesKey(crypto), jsonEncode(legacyNotes.toJson()));
    final storage = _MemoryVaultKeyStorage(crypto.base64UrlNoPad(vault));
    final store = OfflineStore(crypto, vaultKeyStorage: storage);

    expect((await store.loadSessionJson())?['email'], _email);
    expect((await store.loadNotes()).single.localId, _offlineOnlyNote.localId);
    expect(_json(prefs.getString('zk.session')!)['cacheVersion'], 2);
    expect(_json(prefs.getString(_notesKey(crypto))!)['cacheVersion'], 2);
    expect(prefs.getString(_recoveryKey(crypto)), isNotNull);
  });

  test('login restores the device key and offline-only notes after key loss',
      () async {
    SharedPreferences.setMockInitialValues({});
    final crypto = CryptoService();
    final originalVault = List<int>.generate(32, (index) => 31 - index);
    final session = _session(masterKey: List.filled(32, 10));
    final originalStorage =
        _MemoryVaultKeyStorage(crypto.base64UrlNoPad(originalVault));
    final originalStore = OfflineStore(
      crypto,
      vaultKeyStorage: originalStorage,
    );
    await originalStore.saveSessionJson(session);
    await originalStore.saveNotes([_offlineOnlyNote]);

    // Simulate a restored app container whose Keychain item is unavailable.
    final replacementStorage = _MemoryVaultKeyStorage(null);
    final restoredStore = OfflineStore(
      crypto,
      vaultKeyStorage: replacementStorage,
    );
    expect(await restoredStore.loadSessionJson(), isNull);
    expect(replacementStorage.value, isNotNull);
    expect(
        replacementStorage.value, isNot(crypto.base64UrlNoPad(originalVault)));

    // A normal login supplies the master key. Saving that session restores the
    // old device key before touching the offline cache.
    await restoredStore.saveSessionJson(session);

    expect(replacementStorage.value, crypto.base64UrlNoPad(originalVault));
    final recovered = await restoredStore.loadNotes();
    expect(recovered.single.localId, _offlineOnlyNote.localId);
    expect(recovered.single.dirty, isTrue);
  });

  test('login can promote a previously quarantined offline cache', () async {
    SharedPreferences.setMockInitialValues({});
    final crypto = CryptoService();
    final originalVault = List<int>.filled(32, 13);
    final session = _session(masterKey: List.filled(32, 14));
    final originalStore = OfflineStore(
      crypto,
      vaultKeyStorage: _MemoryVaultKeyStorage(
        crypto.base64UrlNoPad(originalVault),
      ),
    );
    await originalStore.saveSessionJson(session);
    await originalStore.saveNotes([_offlineOnlyNote]);
    final prefs = await SharedPreferences.getInstance();
    final notesKey = _notesKey(crypto);
    final encryptedNotes = prefs.getString(notesKey)!;
    await prefs.setString('$notesKey.unreadableBackup', encryptedNotes);
    await prefs.remove(notesKey);

    final replacementStorage = _MemoryVaultKeyStorage(null);
    final restoredStore = OfflineStore(
      crypto,
      vaultKeyStorage: replacementStorage,
    );
    expect(await restoredStore.loadSessionJson(), isNull);
    await restoredStore.saveSessionJson(session);

    expect(replacementStorage.value, crypto.base64UrlNoPad(originalVault));
    expect((await restoredStore.loadNotes()).single.dirty, isTrue);
    expect(prefs.getString(notesKey), encryptedNotes);
  });

  test('concurrent first reads create only one device vault key', () async {
    SharedPreferences.setMockInitialValues({});
    final crypto = CryptoService();
    final storage = _MemoryVaultKeyStorage(null, readDelay: true);
    final store = OfflineStore(crypto, vaultKeyStorage: storage);

    final keys = await Future.wait(
      List.generate(20, (_) => store.localVaultKey()),
    );

    expect(keys, everyElement(keys.first));
    expect(storage.writeCount, 1);
  });

  test('sign out removes cache backups and recovery wrappers', () async {
    SharedPreferences.setMockInitialValues({});
    final crypto = CryptoService();
    final storage = _MemoryVaultKeyStorage(
      crypto.base64UrlNoPad(List.filled(32, 11)),
    );
    final store = OfflineStore(crypto, vaultKeyStorage: storage);
    await store.saveSessionJson(_session(masterKey: List.filled(32, 12)));
    await store.saveNotes([_offlineOnlyNote]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('zk.notes.unreadableBackup', 'ciphertext');
    await prefs.setString('zk.session.unreadableBackup', 'ciphertext');

    await store.clear();

    expect(
      prefs.getKeys().where(
            (key) =>
                key.startsWith('zk.notes') ||
                key.startsWith('zk.session') ||
                key.startsWith('zk.localVaultRecovery'),
          ),
      isEmpty,
    );
  });
}

const _email = 'owner@example.test';
const _tenant = 'personal-vault';

Map<String, dynamic> _session({required List<int> masterKey}) => {
      'email': _email,
      'accessToken': 'access-token',
      'refreshToken': 'refresh-token',
      'defaultTenant': _tenant,
      'masterKey': masterKey,
      'userId': 'user-id',
      'publicEncryptionKey': '',
      'privateEncryptionKey': '',
      'emailVerified': true,
    };

final _offlineOnlyNote = PlainNote(
  localId: 'offline-only-note',
  title: 'Unsynced draft',
  body: 'This must survive a device-key recovery.',
  checklist: const [],
  updatedAt: DateTime.utc(2026, 9, 9),
  pinned: false,
  color: 0,
  sortOrder: 0,
  dirty: true,
  version: 0,
);

Map<String, dynamic> _json(String value) =>
    Map<String, dynamic>.from(jsonDecode(value) as Map);

String _scope(CryptoService crypto) =>
    crypto.base64UrlNoPad(utf8.encode('$_email:$_tenant'));

String _notesKey(CryptoService crypto) => 'zk.notes.${_scope(crypto)}';

String _recoveryKey(CryptoService crypto) =>
    'zk.localVaultRecovery.${_scope(crypto)}';

class _MemoryVaultKeyStorage implements LocalVaultKeyStorage {
  _MemoryVaultKeyStorage(this.value, {this.readDelay = false});

  String? value;
  final bool readDelay;
  int writeCount = 0;

  @override
  Future<String?> read() async {
    if (readDelay) await Future<void>.delayed(const Duration(milliseconds: 5));
    return value;
  }

  @override
  Future<void> write(String value) async {
    writeCount += 1;
    this.value = value;
  }
}

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/notes/notes_controller.dart';
import 'package:safernotes_app/shared/api/api_client.dart';
import 'package:safernotes_app/shared/crypto/crypto_service.dart';
import 'package:safernotes_app/shared/models/encrypted_envelope.dart';
import 'package:safernotes_app/shared/models/note.dart';
import 'package:safernotes_app/shared/models/session.dart';
import 'package:safernotes_app/shared/providers.dart';
import 'package:safernotes_app/shared/storage/offline_store.dart';

void main() {
  test('coalesces a save during sync and advances the expected version',
      () async {
    final initial = _note(body: 'first change', dirty: true);
    final store = _MemoryOfflineStore([initial]);
    final api = _VersionedApiClient(serverVersion: 1, blockFirstRequest: true);
    final auth = Completer<AppSession?>();
    final container = _container(store: store, api: api, auth: auth);
    addTearDown(container.dispose);

    await container.read(notesControllerProvider.future);
    auth.complete(_session);
    await container.read(authControllerProvider.future);

    final controller = container.read(notesControllerProvider.notifier);
    final firstSync = controller.syncNow();
    await api.firstRequestStarted.future;

    await controller.saveDraft(
      draft: initial.copyWith(body: 'newer change while syncing'),
    );
    final coalescedSync = controller.syncNow();
    expect(identical(firstSync, coalescedSync), isTrue);

    api.releaseFirstRequest.complete();
    await Future.wait([firstSync, coalescedSync]);

    expect(api.expectedVersions, [1, 2]);
    expect(api.sentBodies, ['first change', 'newer change while syncing']);
    expect(api.conflictResponses, 0);

    final saved = container.read(notesControllerProvider).requireValue.single;
    expect(saved.body, 'newer change while syncing');
    expect(saved.remoteId, 'remote-note');
    expect(saved.version, 3);
    expect(saved.dirty, isFalse);
    expect(saved.conflicted, isFalse);
    expect(container.read(syncStatusProvider), SyncStatus.saved);
  });

  test('preserves a genuine server version conflict', () async {
    final initial = _note(body: 'local edit', dirty: true);
    final store = _MemoryOfflineStore([initial]);
    final api = _VersionedApiClient(serverVersion: 2);
    final auth = Completer<AppSession?>();
    final container = _container(store: store, api: api, auth: auth);
    addTearDown(container.dispose);

    await container.read(notesControllerProvider.future);
    auth.complete(_session);
    await container.read(authControllerProvider.future);

    await container.read(notesControllerProvider.notifier).syncNow();

    expect(api.expectedVersions, [1]);
    expect(api.conflictResponses, 1);
    final conflicted =
        container.read(notesControllerProvider).requireValue.single;
    expect(conflicted.body, 'local edit');
    expect(conflicted.dirty, isTrue);
    expect(conflicted.conflicted, isTrue);
    expect(container.read(syncStatusProvider), SyncStatus.conflict);
  });

  test('does not restore a stale editor version after a successful sync',
      () async {
    final staleEditorDraft = _note(body: 'first change', dirty: true);
    final store = _MemoryOfflineStore([staleEditorDraft]);
    final api = _VersionedApiClient(serverVersion: 1);
    final auth = Completer<AppSession?>();
    final container = _container(store: store, api: api, auth: auth);
    addTearDown(container.dispose);

    await container.read(notesControllerProvider.future);
    auth.complete(_session);
    await container.read(authControllerProvider.future);

    final controller = container.read(notesControllerProvider.notifier);
    await controller.syncNow();
    expect(
      container.read(notesControllerProvider).requireValue.single.version,
      2,
    );

    await controller.saveDraft(
      draft: staleEditorDraft.copyWith(body: 'edit after acknowledgement'),
    );
    await controller.syncNow();

    expect(api.expectedVersions, [1, 2]);
    expect(api.conflictResponses, 0);
    final saved = container.read(notesControllerProvider).requireValue.single;
    expect(saved.body, 'edit after acknowledgement');
    expect(saved.version, 3);
    expect(saved.dirty, isFalse);
    expect(saved.conflicted, isFalse);
    expect(container.read(syncStatusProvider), SyncStatus.saved);
  });

  test('state changes preserve the latest note and can be undone', () async {
    final initial = _note(body: 'old body', dirty: false);
    final store = _MemoryOfflineStore([initial]);
    final api = _VersionedApiClient(serverVersion: 1);
    final auth = Completer<AppSession?>();
    final container = _container(store: store, api: api, auth: auth);
    addTearDown(container.dispose);

    await container.read(notesControllerProvider.future);
    final controller = container.read(notesControllerProvider.notifier);
    await controller.saveDraft(
      draft: initial.copyWith(body: 'latest body'),
    );
    await controller.changeState(initial, 'trashed');
    var saved = container.read(notesControllerProvider).requireValue.single;
    expect(saved.body, 'latest body');
    expect(saved.state, 'trashed');

    await controller.changeState(initial, 'active');
    saved = container.read(notesControllerProvider).requireValue.single;
    expect(saved.body, 'latest body');
    expect(saved.state, 'active');
  });

  test('empty trash deletes local tombstones after the server confirms',
      () async {
    final initial = _note(body: 'discard me', dirty: false, state: 'trashed');
    final store = _MemoryOfflineStore([initial]);
    final api = _VersionedApiClient(serverVersion: 1);
    final auth = Completer<AppSession?>();
    final container = _container(store: store, api: api, auth: auth);
    addTearDown(container.dispose);

    await container.read(notesControllerProvider.future);
    auth.complete(_session);
    await container.read(authControllerProvider.future);

    final deletedCount =
        await container.read(notesControllerProvider.notifier).emptyTrash();

    expect(deletedCount, 1);
    expect(api.emptyTrashCalls, 1);
    final saved = container.read(notesControllerProvider).requireValue.single;
    expect(saved.state, 'deleted');
    expect(saved.dirty, isFalse);
    expect(container.read(syncStatusProvider), SyncStatus.saved);
  });

  test('coalesces a burst of draft updates into one encrypted cache write',
      () async {
    final initial = _note(body: 'initial', dirty: false);
    final store = _MemoryOfflineStore([initial]);
    final api = _VersionedApiClient(serverVersion: 1);
    final auth = Completer<AppSession?>();
    final container = _container(store: store, api: api, auth: auth);
    addTearDown(container.dispose);

    await container.read(notesControllerProvider.future);
    final controller = container.read(notesControllerProvider.notifier);
    final saves = <Future<void>>[];
    for (var index = 0; index < 250; index += 1) {
      saves.add(
        controller.saveDraft(
          draft: initial.copyWith(body: 'rapid edit $index'),
        ),
      );
    }
    await Future.wait(saves);

    expect(store.saveWrites, 1);
    expect(
      container.read(notesControllerProvider).requireValue.single.body,
      'rapid edit 249',
    );
    expect(container.read(syncStatusProvider), SyncStatus.saving);
  });
}

ProviderContainer _container({
  required _MemoryOfflineStore store,
  required _VersionedApiClient api,
  required Completer<AppSession?> auth,
}) {
  return ProviderContainer(
    overrides: [
      authControllerProvider.overrideWith(() => _DelayedAuthController(auth)),
      offlineStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(api),
      cryptoServiceProvider.overrideWithValue(_TestCryptoService()),
    ],
  );
}

const _session = AppSession(
  email: 'sync@example.test',
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  defaultTenant: 'tenant-id',
  masterKey: [0, 1, 2, 3],
);

PlainNote _note({
  required String body,
  required bool dirty,
  String state = 'active',
}) {
  return PlainNote(
    localId: 'local-note',
    remoteId: 'remote-note',
    title: 'Sync test',
    body: body,
    checklist: const [],
    updatedAt: DateTime.utc(2026, 8, 24, 10),
    pinned: false,
    color: 0xffffffff,
    sortOrder: 0,
    dirty: dirty,
    version: 1,
    state: state,
  );
}

class _DelayedAuthController extends AuthController {
  _DelayedAuthController(this.session);

  final Completer<AppSession?> session;

  @override
  Future<AppSession?> build() => session.future;
}

class _MemoryOfflineStore extends OfflineStore {
  _MemoryOfflineStore(List<PlainNote> notes)
      : _notes = [...notes],
        super(_TestCryptoService());

  List<PlainNote> _notes;
  int saveWrites = 0;

  @override
  Future<List<PlainNote>> loadNotes() async => [..._notes];

  @override
  Future<void> saveNotes(List<PlainNote> notes) async {
    saveWrites += 1;
    _notes = [...notes];
  }
}

class _TestCryptoService extends CryptoService {
  @override
  Future<EncryptedEnvelope> encryptNotePayload({
    required PlainNote note,
    required List<int> masterKey,
  }) async {
    return EncryptedEnvelope(
      version: 1,
      algorithm: 'test',
      nonce: 'nonce',
      ciphertext: note.body,
    );
  }

  @override
  Future<String> sha256Text(String value) async => 'hash-$value';
}

class _VersionedApiClient extends ApiClient {
  _VersionedApiClient({
    required this.serverVersion,
    this.blockFirstRequest = false,
  });

  int serverVersion;
  final bool blockFirstRequest;
  final firstRequestStarted = Completer<void>();
  final releaseFirstRequest = Completer<void>();
  final expectedVersions = <int?>[];
  final sentBodies = <String>[];
  int conflictResponses = 0;
  int emptyTrashCalls = 0;

  @override
  Future<int> emptyTrash(String accessToken) async {
    emptyTrashCalls += 1;
    return 1;
  }

  @override
  Future<Map<String, dynamic>> syncBatch({
    required String accessToken,
    required List<Map<String, dynamic>> operations,
  }) async {
    final operation = operations.single;
    final payload = Map<String, dynamic>.from(operation['payload'] as Map);
    final envelope =
        Map<String, dynamic>.from(payload['encrypted_payload'] as Map);
    final expectedVersion = payload['expected_version'] as int?;
    expectedVersions.add(expectedVersion);
    sentBodies.add(envelope['ciphertext'] as String);

    if (expectedVersions.length == 1) {
      firstRequestStarted.complete();
      if (blockFirstRequest) await releaseFirstRequest.future;
    }

    if (expectedVersion != serverVersion) {
      conflictResponses += 1;
      return {
        'results': [
          {'status': 'conflict'},
        ],
      };
    }

    serverVersion += 1;
    return {
      'results': [
        {
          'status': 'ok',
          'note_id': operation['note_id'] as String? ?? 'remote-note',
          'version': serverVersion,
        },
      ],
    };
  }

  @override
  Future<List<RemoteEncryptedNote>> fetchNotes(String accessToken) async => [];

  @override
  Future<List<CollaboratorPresence>> fetchPresence(String accessToken) async =>
      [];
}

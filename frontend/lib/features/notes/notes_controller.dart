import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/shared/app/app_l10n.dart';
import 'package:safernotes_app/shared/api/api_client.dart';
import 'package:safernotes_app/shared/models/note.dart';
import 'package:safernotes_app/shared/providers.dart';

final notesControllerProvider =
    AsyncNotifierProvider<NotesController, List<PlainNote>>(
  NotesController.new,
);

final selectedNoteIdProvider = StateProvider<String?>((ref) => null);
final noteBucketProvider = StateProvider<String>((ref) => 'active');
final syncStatusProvider = StateProvider<SyncStatus>((ref) => SyncStatus.saved);
final presenceProvider =
    StateProvider<List<CollaboratorPresence>>((ref) => const []);

enum SyncStatus { saved, saving, syncing, offline, conflict }

class NotesController extends AsyncNotifier<List<PlainNote>>
    with WidgetsBindingObserver {
  static const _automaticSyncInterval = Duration(seconds: 8);
  static const _maximumAutomaticSyncBackoff = Duration(minutes: 2);

  final _uuid = const Uuid();
  Timer? _syncTimer;
  Timer? _debounce;
  Future<void> _saveQueue = Future.value();
  final List<_PendingDraftSave> _pendingDraftSaves = [];
  bool _saveDrainActive = false;
  Future<void>? _syncFuture;
  bool _syncRequested = false;
  bool _pullAfterPushRequested = false;
  int _consecutiveSyncFailures = 0;
  DateTime? _automaticSyncBlockedUntil;

  @override
  Future<List<PlainNote>> build() async {
    final offlineOnly =
        ref.read(authControllerProvider).valueOrNull?.isOfflineOnly ?? false;
    final binding = WidgetsFlutterBinding.ensureInitialized();
    binding.addObserver(this);
    ref.onDispose(() {
      binding.removeObserver(this);
      _syncTimer?.cancel();
      _debounce?.cancel();
    });
    if (!offlineOnly) {
      _syncTimer = Timer.periodic(_automaticSyncInterval, (_) {
        if (_canRunAutomaticSync()) {
          unawaited(syncNow(pullAfterPush: true));
        }
      });
    }
    final notes = await ref.watch(offlineStoreProvider).loadNotes();
    if (offlineOnly) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.saved;
    } else {
      unawaited(syncNow(pullAfterPush: true));
    }
    return notes;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(syncNow(pullAfterPush: true));
    }
  }

  PlainNote createEmptyNote() {
    return _createNote();
  }

  PlainNote createChecklistNote() {
    return _createNote(
      checklist: [
        ChecklistItem(id: _uuid.v4(), text: '', done: false, indent: 0),
      ],
    );
  }

  PlainNote _createNote({
    DateTime? reminderAt,
    List<ChecklistItem> checklist = const [],
  }) {
    return PlainNote(
      localId: _uuid.v4(),
      title: '',
      body: '',
      checklist: checklist,
      updatedAt: DateTime.now().toUtc(),
      pinned: false,
      color: 0xffffffff,
      sortOrder: -DateTime.now().toUtc().microsecondsSinceEpoch,
      dirty: !_offlineOnly,
      version: 1,
      state: 'active',
      reminderAt: reminderAt,
    );
  }

  Future<void> saveDraft({
    required PlainNote draft,
    bool syncImmediately = false,
  }) {
    final snapshot = draft.copyWith(checklist: [...draft.checklist]);
    final pending = _PendingDraftSave(
      draft: snapshot,
      syncImmediately: syncImmediately,
    );
    _pendingDraftSaves.add(pending);
    if (!_saveDrainActive) {
      _saveDrainActive = true;
      _saveQueue = Future<void>.microtask(_drainPendingDraftSaves);
    }
    return pending.completer.future;
  }

  Future<void> _drainPendingDraftSaves() async {
    while (_pendingDraftSaves.isNotEmpty) {
      final batch = List<_PendingDraftSave>.of(_pendingDraftSaves);
      _pendingDraftSaves.clear();
      try {
        await _saveDraftBatch(batch);
        for (final pending in batch) {
          pending.completer.complete();
        }
      } catch (error, stackTrace) {
        for (final pending in batch) {
          pending.completer.completeError(error, stackTrace);
        }
      }
    }
    _saveDrainActive = false;
  }

  Future<void> _saveDraftBatch(List<_PendingDraftSave> batch) async {
    var next = List<PlainNote>.of(
      state.valueOrNull ?? await ref.read(offlineStoreProvider).loadNotes(),
    );
    for (final pending in batch) {
      final draft = pending.draft;
      PlainNote? previous;
      for (final item in next) {
        if (item.localId == draft.localId) {
          previous = item;
          break;
        }
      }
      final remoteId = draft.remoteId ?? previous?.remoteId;
      final version = remoteId != null &&
              previous?.remoteId == remoteId &&
              previous!.version > draft.version
          ? previous.version
          : draft.version;
      final nextDraft = draft.copyWith(
        remoteId: remoteId,
        title: draft.title.trim(),
        updatedAt: DateTime.now().toUtc(),
        dirty: !_offlineOnly,
        version: version,
        conflicted: false,
      );
      next = [
        nextDraft,
        ...next.where((item) => item.localId != nextDraft.localId),
      ];
    }
    next.sort(_sortNotes);
    await _persist(next);
    if (_offlineOnly) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.saved;
      return;
    }
    ref.read(syncStatusProvider.notifier).state = SyncStatus.saving;
    if (_syncFuture != null) {
      _syncRequested = true;
      _pullAfterPushRequested = true;
    }
    _debounce?.cancel();
    _debounce = Timer(
        batch.any((pending) => pending.syncImmediately)
            ? Duration.zero
            : const Duration(milliseconds: 900), () {
      unawaited(syncNow(pullAfterPush: true));
    });
  }

  Future<PlainNote> ensureSynced(PlainNote draft) async {
    if (_offlineOnly) {
      throw StateError('Sharing is unavailable in an offline-only vault.');
    }
    await saveDraft(draft: draft, syncImmediately: false);
    _debounce?.cancel();
    await syncNow(pullAfterPush: true);
    final notes =
        state.valueOrNull ?? await ref.read(offlineStoreProvider).loadNotes();
    final synced = notes.firstWhere(
      (note) => note.localId == draft.localId,
      orElse: () => draft,
    );
    if (synced.remoteId == null) {
      throw StateError(ref.read(l10nProvider).t('noteNotSynced'));
    }
    return synced;
  }

  Future<void> pullRemote({String? requiredNoteId}) async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || session.isOfflineOnly) return;
    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    try {
      final remote =
          await ref.read(apiClientProvider).fetchNotes(session.accessToken);
      final local = await ref.read(offlineStoreProvider).loadNotes();
      final merged = Map<String, PlainNote>.fromEntries(
        local.map((note) => MapEntry(note.remoteId ?? note.localId, note)),
      );
      final remoteIds = remote.map((note) => note.id).toSet();
      merged.removeWhere((id, note) =>
          note.remoteId != null &&
          note.shareRole != null &&
          note.shareRole != 'owner' &&
          !remoteIds.contains(note.remoteId) &&
          !note.dirty);
      Object? requiredNoteError;
      for (final item in remote) {
        final localMatch = merged[item.id];
        if (localMatch != null && localMatch.dirty) continue;
        try {
          final crypto = ref.read(cryptoServiceProvider);
          List<int>? noteKey;
          final grant = item.currentKeyGrant;
          if (grant != null) {
            if (grant.role == 'owner') {
              final encoded = await crypto.decryptString(
                grant.encryptedNoteKey,
                session.masterKey,
              );
              noteKey = crypto.decodeBase64UrlNoPad(encoded);
            } else if (session.privateEncryptionKey.isNotEmpty &&
                session.publicEncryptionKey.isNotEmpty) {
              noteKey = await crypto.unwrapNoteKey(
                envelope: grant.encryptedNoteKey,
                privateEncryptionKey: session.privateEncryptionKey,
                publicEncryptionKey: session.publicEncryptionKey,
              );
            }
          }
          String decoded;
          try {
            decoded = await crypto.decryptString(
              item.encryptedPayload,
              noteKey ?? session.masterKey,
            );
          } catch (_) {
            decoded = await crypto.decryptString(
              item.encryptedPayload,
              session.masterKey,
            );
          }
          final plain = Map<String, dynamic>.from(jsonDecode(decoded) as Map);
          final remoteNote = PlainNote.fromEncryptedPayload(
            localId: localMatch?.localId ?? item.id,
            remoteId: item.id,
            updatedAt: item.updatedAt,
            version: item.version,
            json: plain,
          ).copyWith(
            state: item.state,
            reminderAt: localMatch?.reminderAt,
            shared: item.isShared || item.currentUserRole != 'owner',
            noteKey: noteKey == null
                ? localMatch?.noteKey
                : crypto.base64UrlNoPad(noteKey),
            shareRole: item.currentUserRole,
          );
          merged[item.id] = remoteNote;
        } catch (error) {
          if (item.id == requiredNoteId) requiredNoteError = error;
          if (localMatch != null) merged[item.id] = localMatch;
        }
      }
      final notes = merged.values.toList()..sort(_sortNotes);
      await ref.read(offlineStoreProvider).saveNotes(notes);
      state = AsyncData(notes);
      await refreshPresence();
      _recordSyncSuccess();
      ref.read(syncStatusProvider.notifier).state = SyncStatus.saved;
      if (requiredNoteId != null &&
          (requiredNoteError != null ||
              !notes.any((note) => note.remoteId == requiredNoteId))) {
        throw StateError(
          'Shared note import failed: ${requiredNoteError ?? 'note missing'}',
        );
      }
    } catch (error) {
      _recordSyncFailure();
      ref.read(syncStatusProvider.notifier).state =
          error is ApiException && error.statusCode == 409
              ? SyncStatus.conflict
              : SyncStatus.offline;
      if (requiredNoteId != null) rethrow;
    }
  }

  Future<void> syncNow({bool pullAfterPush = false}) {
    if (_offlineOnly) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.saved;
      return Future.value();
    }
    _syncRequested = true;
    _pullAfterPushRequested |= pullAfterPush;

    final activeSync = _syncFuture;
    if (activeSync != null) return activeSync;

    late final Future<void> sync;
    sync = _runSyncLoop().whenComplete(() {
      if (identical(_syncFuture, sync)) _syncFuture = null;
    });
    _syncFuture = sync;
    return sync;
  }

  Future<void> _runSyncLoop() async {
    while (_syncRequested) {
      _syncRequested = false;
      await _saveQueue;

      final outcome = await _syncOnce();
      if (outcome != _SyncOutcome.success) {
        _syncRequested = false;
        _pullAfterPushRequested = false;
        return;
      }

      final latest = state.valueOrNull ?? const <PlainNote>[];
      if (latest.any((note) => note.dirty)) {
        if (_syncRequested) continue;
        return;
      }

      if (_pullAfterPushRequested) {
        _pullAfterPushRequested = false;
        await pullRemote();
      }
    }
  }

  Future<_SyncOutcome> _syncOnce() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || session.isOfflineOnly) return _SyncOutcome.skipped;
    final notes =
        state.valueOrNull ?? await ref.read(offlineStoreProvider).loadNotes();
    final dirty = notes.where((note) => note.dirty).toList();
    if (dirty.isEmpty) {
      _recordSyncSuccess();
      return _SyncOutcome.success;
    }

    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    try {
      final operations = <Map<String, dynamic>>[];
      for (final note in dirty) {
        final encryptionKey = note.noteKey == null
            ? session.masterKey
            : ref
                .read(cryptoServiceProvider)
                .decodeBase64UrlNoPad(note.noteKey!);
        final encrypted =
            await ref.read(cryptoServiceProvider).encryptNotePayload(
                  note: note,
                  masterKey: encryptionKey,
                );
        operations.add(
          noteUpsertOperation(
            idempotencyKey:
                '${note.localId}-${note.updatedAt.microsecondsSinceEpoch}',
            tenant: session.defaultTenant,
            encryptedPayload: encrypted,
            payloadHash: await ref
                .read(cryptoServiceProvider)
                .sha256Text(encrypted.ciphertext),
            updatedAt: note.updatedAt,
            remoteId: note.remoteId,
            expectedVersion: note.remoteId == null ? null : note.version,
          ),
        );
      }
      final response = await ref.read(apiClientProvider).syncBatch(
            accessToken: session.accessToken,
            operations: operations,
          );
      final results = (response['results'] as List? ?? []).cast<Map>();
      await _saveQueue;
      final latestNotes =
          state.valueOrNull ?? await ref.read(offlineStoreProvider).loadNotes();
      final byLocalId = {
        for (final note in latestNotes) note.localId: note,
      };
      var sawConflict = false;
      for (var i = 0; i < dirty.length && i < results.length; i += 1) {
        final result = Map<String, dynamic>.from(results[i]);
        final sentNote = dirty[i];
        final latestNote = byLocalId[sentNote.localId] ?? sentNote;
        if (result['status'] == 'ok') {
          final changedWhileSyncing = !_sameSyncRevision(latestNote, sentNote);
          byLocalId[sentNote.localId] = latestNote.copyWith(
            remoteId: result['note_id'] as String? ?? latestNote.remoteId,
            version: result['version'] as int? ?? latestNote.version,
            dirty: changedWhileSyncing,
            conflicted: false,
          );
        } else if (result['status'] == 'conflict') {
          sawConflict = true;
          byLocalId[sentNote.localId] = latestNote.copyWith(conflicted: true);
        }
      }
      final next = byLocalId.values.toList()..sort(_sortNotes);
      await ref.read(offlineStoreProvider).saveNotes(next);
      state = AsyncData(next);
      ref.read(syncStatusProvider.notifier).state =
          sawConflict || next.any((note) => note.conflicted)
              ? SyncStatus.conflict
              : next.any((note) => note.dirty)
                  ? SyncStatus.saving
                  : SyncStatus.saved;
      _recordSyncSuccess();
      return sawConflict ? _SyncOutcome.conflict : _SyncOutcome.success;
    } catch (error) {
      _recordSyncFailure();
      final conflict = error is ApiException && error.statusCode == 409;
      ref.read(syncStatusProvider.notifier).state =
          conflict ? SyncStatus.conflict : SyncStatus.offline;
      return conflict ? _SyncOutcome.conflict : _SyncOutcome.offline;
    }
  }

  Future<void> changeState(PlainNote note, String nextState) async {
    final existing =
        state.valueOrNull ?? await ref.read(offlineStoreProvider).loadNotes();
    final current = existing.cast<PlainNote?>().firstWhere(
              (item) => item?.localId == note.localId,
              orElse: () => null,
            ) ??
        note;
    final updated = current.copyWith(
      state: nextState,
      dirty: !_offlineOnly && current.remoteId == null,
    );
    final next = [
      updated,
      ...existing.where((item) => item.localId != note.localId),
    ]..sort(_sortNotes);
    await _persist(next);
    if (_offlineOnly) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.saved;
      return;
    }
    if (current.remoteId == null) return;

    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) return;
    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    try {
      await ref.read(apiClientProvider).syncBatch(
        accessToken: session.accessToken,
        operations: [
          noteStateOperation(
            idempotencyKey:
                '${current.localId}-state-$nextState-${DateTime.now().microsecondsSinceEpoch}',
            remoteId: current.remoteId!,
            state: nextState,
          ),
        ],
      );
      ref.read(syncStatusProvider.notifier).state = SyncStatus.saved;
    } catch (error) {
      ref.read(syncStatusProvider.notifier).state =
          error is ApiException && error.statusCode == 409
              ? SyncStatus.conflict
              : SyncStatus.offline;
    }
  }

  Future<int> emptyTrash() async {
    await _saveQueue;
    final existing =
        state.valueOrNull ?? await ref.read(offlineStoreProvider).loadNotes();
    final trashed = existing.where((note) => note.state == 'trashed').toList();
    if (trashed.isEmpty) return 0;

    final session = ref.read(authControllerProvider).valueOrNull;
    if (session?.isOfflineOnly ?? false) {
      final next = [
        for (final note in existing)
          if (note.state == 'trashed')
            note.copyWith(state: 'deleted', dirty: false)
          else
            note,
      ]..sort(_sortNotes);
      await _persist(next);
      ref.read(syncStatusProvider.notifier).state = SyncStatus.saved;
      return trashed.length;
    }
    final hasRemoteNotes = trashed.any((note) => note.remoteId != null);
    if (hasRemoteNotes && session == null) {
      throw StateError(ref.read(l10nProvider).t('emptyTrashFailed'));
    }

    if (session != null) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
      try {
        await ref.read(apiClientProvider).emptyTrash(session.accessToken);
      } catch (error) {
        ref.read(syncStatusProvider.notifier).state = SyncStatus.offline;
        rethrow;
      }
    }

    final next = [
      for (final note in existing)
        if (note.state == 'trashed')
          note.copyWith(state: 'deleted', dirty: false)
        else
          note,
    ]..sort(_sortNotes);
    await _persist(next);
    if (session != null) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.saved;
    }
    return trashed.length;
  }

  Future<void> togglePinned(PlainNote note) {
    return saveDraft(
      draft: note.copyWith(pinned: !note.pinned),
      syncImmediately: true,
    );
  }

  Future<void> setReminder(PlainNote note, DateTime? reminderAt) {
    return saveDraft(
      draft: note.copyWith(
        reminderAt: reminderAt,
        clearReminder: reminderAt == null,
      ),
      syncImmediately: true,
    );
  }

  Future<PlainNote> duplicateAsReminder({
    required PlainNote source,
    required DateTime reminderAt,
  }) async {
    final duplicate = source.copyWith(
      remoteId: null,
      title: source.title,
      updatedAt: DateTime.now().toUtc(),
      sortOrder: -DateTime.now().toUtc().microsecondsSinceEpoch,
      dirty: !_offlineOnly,
      version: 1,
      state: 'active',
      reminderAt: reminderAt,
      shared: false,
    );
    final personal = PlainNote(
      localId: _uuid.v4(),
      remoteId: null,
      title: duplicate.title,
      body: duplicate.body,
      richTextDelta: duplicate.richTextDelta,
      checklist: duplicate.checklist,
      updatedAt: duplicate.updatedAt,
      pinned: duplicate.pinned,
      color: duplicate.color,
      sortOrder: duplicate.sortOrder,
      dirty: !_offlineOnly,
      version: 1,
      state: 'active',
      reminderAt: reminderAt,
      shared: false,
    );
    await saveDraft(draft: personal, syncImmediately: false);
    return personal;
  }

  Future<void> reorderNotes({
    required String draggedId,
    required int targetIndex,
    required String bucket,
  }) async {
    final existing =
        state.valueOrNull ?? await ref.read(offlineStoreProvider).loadNotes();
    final bucketNotes = existing.where((note) => note.state == bucket).toList()
      ..sort(_sortNotes);
    final oldIndex =
        bucketNotes.indexWhere((note) => note.localId == draggedId);
    if (oldIndex < 0) return;

    final moved = bucketNotes.removeAt(oldIndex);
    final insertionIndex = targetIndex.clamp(0, bucketNotes.length).toInt();
    if (insertionIndex == oldIndex) return;
    bucketNotes.insert(insertionIndex, moved);
    final now = DateTime.now().toUtc();
    final reordered = <String, PlainNote>{};
    for (var index = 0; index < bucketNotes.length; index += 1) {
      final note = bucketNotes[index];
      reordered[note.localId] = note.copyWith(
        sortOrder: index * 1000,
        updatedAt: now,
        dirty: !_offlineOnly,
        conflicted: false,
      );
    }
    final next = [
      for (final note in existing) reordered[note.localId] ?? note,
    ]..sort(_sortNotes);
    // The drag preview already shows this exact order. Publish it before the
    // disk write so releasing the pointer settles in place instead of briefly
    // rebuilding the old order and then animating to the committed one.
    state = AsyncData(next);
    try {
      await ref.read(offlineStoreProvider).saveNotes(next);
    } catch (_) {
      state = AsyncData(existing);
      rethrow;
    }
    if (_offlineOnly) {
      ref.read(syncStatusProvider.notifier).state = SyncStatus.saved;
      return;
    }
    ref.read(syncStatusProvider.notifier).state = SyncStatus.saving;
    if (_syncFuture != null) {
      _syncRequested = true;
      _pullAfterPushRequested = true;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), () {
      unawaited(syncNow(pullAfterPush: true));
    });
  }

  Future<void> refreshPresence() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || session.isOfflineOnly) return;
    try {
      final all =
          await ref.read(apiClientProvider).fetchPresence(session.accessToken);
      ref.read(presenceProvider.notifier).state = all;
    } catch (_) {
      // Presence is best-effort; note sync status is more important.
    }
  }

  Future<void> inviteCollaborator({
    required PlainNote note,
    required String recipientUserId,
    required String role,
  }) async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || session.isOfflineOnly) {
      throw StateError('Sharing is unavailable in an offline-only vault.');
    }
    if (note.remoteId == null) return;
    if (session.privateEncryptionKey.isEmpty ||
        session.publicEncryptionKey.isEmpty) {
      throw StateError('Please sign in again before sharing a note.');
    }
    final crypto = ref.read(cryptoServiceProvider);
    final recipient = await ref.read(apiClientProvider).fetchPublicKeys(
          accessToken: session.accessToken,
          email: recipientUserId,
        );
    final noteKey = note.noteKey == null
        ? crypto.randomBytes(32)
        : crypto.decodeBase64UrlNoPad(note.noteKey!);
    final encodedNoteKey = crypto.base64UrlNoPad(noteKey);
    if (note.noteKey == null) {
      final ownerEnvelope = await crypto.encryptString(
        encodedNoteKey,
        session.masterKey,
      );
      await ref.read(apiClientProvider).storeOwnerNoteKey(
            accessToken: session.accessToken,
            noteId: note.remoteId!,
            encryptedNoteKey: ownerEnvelope,
            grantSignature: await crypto.sha256Text('${note.remoteId}:owner'),
          );
      await saveDraft(
        draft: note.copyWith(
          shared: true,
          noteKey: encodedNoteKey,
          shareRole: 'owner',
        ),
        syncImmediately: false,
      );
      _debounce?.cancel();
      await syncNow(pullAfterPush: false);
    }
    final encryptedKey = await crypto.wrapNoteKey(
      noteKey: noteKey,
      recipientPublicKey: recipient['public_encryption_key'] as String,
    );
    await ref.read(apiClientProvider).createShareInvitation(
          accessToken: session.accessToken,
          noteId: note.remoteId!,
          recipientUserId: recipientUserId,
          role: role,
          encryptedNoteKey: encryptedKey,
          invitationSignature: await crypto
              .sha256Text('${note.remoteId}:$recipientUserId:$role'),
        );
    await pullRemote();
  }

  Future<void> _persist(List<PlainNote> notes) async {
    await ref.read(offlineStoreProvider).saveNotes(notes);
    state = AsyncData(notes);
  }

  bool get _offlineOnly =>
      ref.read(authControllerProvider).valueOrNull?.isOfflineOnly ?? false;

  bool _canRunAutomaticSync() {
    final lifecycle = WidgetsFlutterBinding.ensureInitialized().lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      return false;
    }
    final blockedUntil = _automaticSyncBlockedUntil;
    return blockedUntil == null || !DateTime.now().isBefore(blockedUntil);
  }

  void _recordSyncSuccess() {
    _consecutiveSyncFailures = 0;
    _automaticSyncBlockedUntil = null;
  }

  void _recordSyncFailure() {
    _consecutiveSyncFailures += 1;
    final exponent = (_consecutiveSyncFailures - 1).clamp(0, 4);
    final seconds = _automaticSyncInterval.inSeconds * (1 << exponent);
    final cappedSeconds = seconds.clamp(
      _automaticSyncInterval.inSeconds,
      _maximumAutomaticSyncBackoff.inSeconds,
    );
    _automaticSyncBlockedUntil =
        DateTime.now().add(Duration(seconds: cappedSeconds));
  }
}

class _PendingDraftSave {
  _PendingDraftSave({
    required this.draft,
    required this.syncImmediately,
  });

  final PlainNote draft;
  final bool syncImmediately;
  final Completer<void> completer = Completer<void>();
}

enum _SyncOutcome { success, conflict, offline, skipped }

bool _sameSyncRevision(PlainNote a, PlainNote b) {
  return a.remoteId == b.remoteId &&
      a.version == b.version &&
      jsonEncode(a.encryptedPayloadJson()) ==
          jsonEncode(b.encryptedPayloadJson());
}

int _sortNotes(PlainNote a, PlainNote b) {
  if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
  if (a.sortOrder != b.sortOrder) return a.sortOrder.compareTo(b.sortOrder);
  return b.updatedAt.compareTo(a.updatedAt);
}

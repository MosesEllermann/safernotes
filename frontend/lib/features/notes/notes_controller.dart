import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:zknotes_app/features/auth/auth_controller.dart';
import 'package:zknotes_app/shared/api/api_client.dart';
import 'package:zknotes_app/shared/models/note.dart';
import 'package:zknotes_app/shared/providers.dart';

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

class NotesController extends AsyncNotifier<List<PlainNote>> {
  final _uuid = const Uuid();
  Timer? _syncTimer;
  Timer? _debounce;

  @override
  Future<List<PlainNote>> build() async {
    ref.onDispose(() {
      _syncTimer?.cancel();
      _debounce?.cancel();
    });
    _syncTimer = Timer.periodic(
        const Duration(seconds: 8), (_) => syncNow(pullAfterPush: true));
    final notes = await ref.watch(offlineStoreProvider).loadNotes();
    unawaited(syncNow(pullAfterPush: true));
    return notes;
  }

  PlainNote createEmptyNote() {
    return _createNote();
  }

  PlainNote createReminderNote() {
    return _createNote(
      reminderAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
    );
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
      dirty: true,
      version: 1,
      state: 'active',
      reminderAt: reminderAt,
    );
  }

  Future<void> saveDraft({
    required PlainNote draft,
    bool syncImmediately = false,
  }) async {
    final existing =
        state.valueOrNull ?? await ref.read(offlineStoreProvider).loadNotes();
    final nextDraft = draft.copyWith(
      title: draft.title.trim().isEmpty ? 'Untitled note' : draft.title.trim(),
      updatedAt: DateTime.now().toUtc(),
      dirty: true,
      conflicted: false,
    );
    final next = [
      nextDraft,
      ...existing.where((item) => item.localId != nextDraft.localId),
    ]..sort(_sortNotes);
    await _persist(next);
    ref.read(syncStatusProvider.notifier).state = SyncStatus.saving;
    _debounce?.cancel();
    _debounce = Timer(
        syncImmediately ? Duration.zero : const Duration(milliseconds: 900),
        () {
      unawaited(syncNow(pullAfterPush: true));
    });
  }

  Future<PlainNote> ensureSynced(PlainNote draft) async {
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
      throw StateError('Die Notiz konnte noch nicht synchronisiert werden.');
    }
    return synced;
  }

  Future<void> pullRemote() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) return;
    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    try {
      final remote =
          await ref.read(apiClientProvider).fetchNotes(session.accessToken);
      final local = await ref.read(offlineStoreProvider).loadNotes();
      final merged = Map<String, PlainNote>.fromEntries(
        local.map((note) => MapEntry(note.remoteId ?? note.localId, note)),
      );
      for (final item in remote) {
        final localMatch = merged[item.id];
        if (localMatch != null && localMatch.dirty) continue;
        try {
          final decoded = await ref.read(cryptoServiceProvider).decryptString(
                item.encryptedPayload,
                session.masterKey,
              );
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
            shared: localMatch?.shared,
          );
          merged[item.id] = remoteNote;
        } catch (_) {
          if (localMatch != null) merged[item.id] = localMatch;
        }
      }
      final notes = merged.values.toList()..sort(_sortNotes);
      await ref.read(offlineStoreProvider).saveNotes(notes);
      state = AsyncData(notes);
      await refreshPresence();
      ref.read(syncStatusProvider.notifier).state = SyncStatus.saved;
    } catch (error) {
      ref.read(syncStatusProvider.notifier).state =
          error is ApiException && error.statusCode == 409
              ? SyncStatus.conflict
              : SyncStatus.saved;
    }
  }

  Future<void> syncNow({bool pullAfterPush = false}) async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) return;
    final notes =
        state.valueOrNull ?? await ref.read(offlineStoreProvider).loadNotes();
    final dirty = notes.where((note) => note.dirty).toList();
    if (dirty.isEmpty) {
      if (pullAfterPush) await pullRemote();
      return;
    }

    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    try {
      final operations = <Map<String, dynamic>>[];
      for (final note in dirty) {
        final encrypted =
            await ref.read(cryptoServiceProvider).encryptNotePayload(
                  note: note,
                  masterKey: session.masterKey,
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
      final byLocalId = {for (final note in notes) note.localId: note};
      var sawConflict = false;
      for (var i = 0; i < dirty.length && i < results.length; i += 1) {
        final result = Map<String, dynamic>.from(results[i]);
        final note = dirty[i];
        if (result['status'] == 'ok') {
          byLocalId[note.localId] = note.copyWith(
            remoteId: result['note_id'] as String?,
            version: result['version'] as int? ?? note.version,
            dirty: false,
            conflicted: false,
          );
        } else if (result['status'] == 'conflict') {
          sawConflict = true;
          byLocalId[note.localId] = note.copyWith(conflicted: true);
        }
      }
      final next = byLocalId.values.toList()..sort(_sortNotes);
      await ref.read(offlineStoreProvider).saveNotes(next);
      state = AsyncData(next);
      ref.read(syncStatusProvider.notifier).state =
          sawConflict ? SyncStatus.conflict : SyncStatus.saved;
      if (pullAfterPush) await pullRemote();
    } catch (error) {
      ref.read(syncStatusProvider.notifier).state =
          error is ApiException && error.statusCode == 409
              ? SyncStatus.conflict
              : SyncStatus.offline;
    }
  }

  Future<void> changeState(PlainNote note, String nextState) async {
    final existing =
        state.valueOrNull ?? await ref.read(offlineStoreProvider).loadNotes();
    final updated =
        note.copyWith(state: nextState, dirty: note.remoteId == null);
    final next = [
      updated,
      ...existing.where((item) => item.localId != note.localId),
    ]..sort(_sortNotes);
    await _persist(next);
    if (note.remoteId == null) return;

    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) return;
    ref.read(syncStatusProvider.notifier).state = SyncStatus.syncing;
    try {
      await ref.read(apiClientProvider).syncBatch(
        accessToken: session.accessToken,
        operations: [
          noteStateOperation(
            idempotencyKey:
                '${note.localId}-state-$nextState-${DateTime.now().microsecondsSinceEpoch}',
            remoteId: note.remoteId!,
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
      dirty: true,
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
      checklist: duplicate.checklist,
      updatedAt: duplicate.updatedAt,
      pinned: duplicate.pinned,
      color: duplicate.color,
      sortOrder: duplicate.sortOrder,
      dirty: true,
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
        dirty: true,
        conflicted: false,
      );
    }
    final next = [
      for (final note in existing) reordered[note.localId] ?? note,
    ]..sort(_sortNotes);
    await _persist(next);
    ref.read(syncStatusProvider.notifier).state = SyncStatus.saving;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 900), () {
      unawaited(syncNow(pullAfterPush: true));
    });
  }

  Future<void> refreshPresence() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) return;
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
    if (session == null || note.remoteId == null) return;
    final encryptedKey = await ref.read(cryptoServiceProvider).encryptString(
          ref.read(cryptoServiceProvider).base64UrlNoPad(session.masterKey),
          session.masterKey,
        );
    await ref.read(apiClientProvider).createShareInvitation(
          accessToken: session.accessToken,
          noteId: note.remoteId!,
          recipientUserId: recipientUserId,
          role: role,
          encryptedNoteKey: encryptedKey,
          invitationSignature: await ref
              .read(cryptoServiceProvider)
              .sha256Text('${note.remoteId}:$recipientUserId:$role'),
        );
    await saveDraft(
      draft: note.copyWith(shared: true),
      syncImmediately: true,
    );
  }

  Future<void> _persist(List<PlainNote> notes) async {
    await ref.read(offlineStoreProvider).saveNotes(notes);
    state = AsyncData(notes);
  }
}

int _sortNotes(PlainNote a, PlainNote b) {
  if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
  if (a.sortOrder != b.sortOrder) return a.sortOrder.compareTo(b.sortOrder);
  return b.updatedAt.compareTo(a.updatedAt);
}

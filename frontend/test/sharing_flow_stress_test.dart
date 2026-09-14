import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/notes/notes_controller.dart';
import 'package:safernotes_app/features/notes/notes_screen.dart';
import 'package:safernotes_app/shared/api/api_client.dart';
import 'package:safernotes_app/shared/models/note.dart';
import 'package:safernotes_app/shared/models/session.dart';
import 'package:safernotes_app/shared/providers.dart';

void main() {
  testWidgets(
      'a lost acceptance response and delayed note visibility recover in one flow',
      (tester) async {
    final api = _FlakyInvitationApi();
    final notes = _DelayedSharedNoteController();
    final invitationRevision = ValueNotifier(1);
    addTearDown(invitationRevision.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          authControllerProvider.overrideWith(_ReadyAuthController.new),
          notesControllerProvider.overrideWith(() => notes),
        ],
        child: MaterialApp(
          home: ValueListenableBuilder<int>(
            valueListenable: invitationRevision,
            builder: (_, revision, __) => NotesScreen(
              invitationId: _invitationId,
              invitationRevision: revision,
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Note invitation'), findsOneWidget);
    for (var revision = 2; revision <= 101; revision += 1) {
      invitationRevision.value = revision;
      await tester.pump();
    }
    expect(find.text('Note invitation'), findsOneWidget);
    expect(api.fetchAttempts, 1);
    await tester.tap(find.text('Accept'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();

    expect(api.decisionAttempts, 3);
    expect(api.fetchAttempts, 1);
    expect(notes.importAttempts, 3);
    expect(notes.lastRequiredNoteId, _noteId);
    expect(find.text('Recovered shared note'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

const _invitationId = '123e4567-e89b-42d3-a456-426614174000';
const _noteId = '123e4567-e89b-42d3-a456-426614174001';

const _session = AppSession(
  email: 'recipient@example.test',
  accessToken: 'access-token',
  refreshToken: 'refresh-token',
  defaultTenant: 'tenant-id',
  masterKey: [0, 1, 2, 3],
  publicEncryptionKey: 'public-key',
  privateEncryptionKey: 'private-key',
  emailVerified: true,
);

class _ReadyAuthController extends AuthController {
  @override
  Future<AppSession?> build() async => _session;

  @override
  Future<AppSession> ensureEncryptionKeys() async => _session;
}

class _FlakyInvitationApi extends ApiClient {
  int fetchAttempts = 0;
  int decisionAttempts = 0;

  @override
  Future<Map<String, dynamic>> fetchShareInvitation({
    required String accessToken,
    required String invitationId,
  }) async {
    fetchAttempts += 1;
    return {
      'id': invitationId,
      'note': _noteId,
      'role': 'editor',
      'status': 'pending',
    };
  }

  @override
  Future<Map<String, dynamic>> decideShareInvitation({
    required String accessToken,
    required String invitationId,
    required String decision,
  }) async {
    decisionAttempts += 1;
    if (decisionAttempts < 3) {
      throw ApiException('acceptance response lost', 0);
    }
    return {
      'invitation': {
        'id': invitationId,
        'note': _noteId,
        'role': 'editor',
        'status': 'accepted',
      },
    };
  }

  @override
  Future<SubscriptionUsage> fetchSubscriptionUsage({
    required String accessToken,
    required String tenant,
  }) async {
    return const SubscriptionUsage(
      plan: 'free',
      storageBytesUsed: 0,
      storageBytesLimit: 524288000,
      notesCount: 1,
      maxNotes: 500,
    );
  }
}

class _DelayedSharedNoteController extends NotesController {
  int importAttempts = 0;
  String? lastRequiredNoteId;

  @override
  Future<List<PlainNote>> build() async => const [];

  @override
  Future<void> pullRemote({String? requiredNoteId}) async {
    importAttempts += 1;
    lastRequiredNoteId = requiredNoteId;
    if (importAttempts < 3) {
      throw StateError('grant is not visible yet');
    }
    state = AsyncData([
      PlainNote(
        localId: _noteId,
        remoteId: _noteId,
        title: 'Recovered shared note',
        body: 'Encrypted content was imported.',
        checklist: const [],
        updatedAt: DateTime.utc(2026, 9, 14),
        pinned: false,
        color: 0xffffffff,
        sortOrder: 0,
        dirty: false,
        version: 1,
        shared: true,
        shareRole: 'editor',
      ),
    ]);
  }
}

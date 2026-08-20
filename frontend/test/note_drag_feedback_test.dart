import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/notes/notes_controller.dart';
import 'package:safernotes_app/features/notes/notes_screen.dart';
import 'package:safernotes_app/shared/models/note.dart';
import 'package:safernotes_app/shared/models/session.dart';

void main() {
  testWidgets('note drag feedback keeps the rendered card size',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final note = _note(
      localId: 'note-long',
      title: 'Long measured note',
      body: List.filled(8, 'A line with enough text to wrap naturally.')
          .join('\n'),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
          notesControllerProvider.overrideWith(
            () => _TestNotesController([note]),
          ),
        ],
        child: const MaterialApp(home: NotesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final cardFinder =
        find.byKey(const ValueKey('compact-note-drag-note-long'));
    expect(cardFinder, findsOneWidget);
    final cardSize = tester.getSize(cardFinder);

    final gesture = await tester.startGesture(tester.getCenter(cardFinder));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await tester.pump();

    final feedbackFinder =
        find.byKey(const ValueKey('note-drag-feedback-note-long'));
    expect(feedbackFinder, findsOneWidget);
    expect(tester.getSize(feedbackFinder), cardSize);

    await gesture.up();
  });
}

PlainNote _note({
  required String localId,
  required String title,
  required String body,
}) {
  return PlainNote(
    localId: localId,
    title: title,
    body: body,
    checklist: const [],
    updatedAt: DateTime.utc(2026, 8, 20),
    pinned: false,
    color: 0xffffffff,
    sortOrder: 0,
    dirty: false,
    version: 1,
  );
}

class _TestAuthController extends AuthController {
  @override
  Future<AppSession?> build() async {
    return const AppSession(
      email: 'local@example.test',
      accessToken: 'local-access',
      refreshToken: 'local-refresh',
      defaultTenant: 'local-tenant',
      masterKey: [0, 1, 2, 3],
    );
  }
}

class _TestNotesController extends NotesController {
  _TestNotesController(this._notes);

  final List<PlainNote> _notes;

  @override
  Future<List<PlainNote>> build() async => _notes;

  @override
  Future<void> reorderNotes({
    required String draggedId,
    required int targetIndex,
    required String bucket,
  }) async {}
}

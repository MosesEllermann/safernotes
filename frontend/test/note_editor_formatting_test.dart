import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/notes/note_editor_screen.dart';
import 'package:safernotes_app/features/notes/notes_controller.dart';
import 'package:safernotes_app/shared/models/note.dart';
import 'package:safernotes_app/shared/models/session.dart';

void main() {
  testWidgets('editor shows the reduced reliable formatting toolbar',
      (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
          notesControllerProvider.overrideWith(
            () => _TestNotesController([_note()]),
          ),
        ],
        child: MaterialApp(home: NoteEditorPanel(note: _note())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Fett'), findsOneWidget);
    expect(find.byTooltip('Kursiv'), findsOneWidget);
    expect(find.byTooltip('Durchstreichen'), findsOneWidget);
    expect(find.byTooltip('Link'), findsOneWidget);
    expect(find.byTooltip('Codeblock'), findsOneWidget);
    expect(find.byTooltip('Checkliste'), findsOneWidget);
    expect(find.byTooltip('Formatierung löschen'), findsOneWidget);
    expect(find.byTooltip('Hintergrund'), findsOneWidget);

    expect(find.byTooltip('underline'), findsNothing);
  });
}

PlainNote _note() {
  return PlainNote(
    localId: 'format-note',
    title: 'Formatting',
    body: 'A note with **bold**, _italic_, and [link](https://example.com).',
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
  Future<void> saveDraft({
    required PlainNote draft,
    bool syncImmediately = false,
  }) async {}
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/notes/note_editor_screen.dart';
import 'package:safernotes_app/features/notes/rich_text_document.dart';
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
        child: _editorApp(_note()),
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
    expect(find.byTooltip('Rückgängig'), findsOneWidget);
    expect(find.byTooltip('Wiederholen'), findsOneWidget);

    expect(find.byTooltip('underline'), findsNothing);
  });

  testWidgets('undo and redo restore body edits', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final note = _note();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
          notesControllerProvider.overrideWith(
            () => _TestNotesController([note]),
          ),
        ],
        child: _editorApp(note),
      ),
    );
    await tester.pumpAndSettle();

    final editor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    final original = documentPlainText(editor.controller.document);
    editor.controller.replaceText(
      0,
      editor.controller.document.length - 1,
      'Updated body',
      const TextSelection.collapsed(offset: 12),
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Rückgängig'));
    await tester.pump();
    expect(documentPlainText(editor.controller.document), original);

    await tester.tap(find.byTooltip('Wiederholen'));
    await tester.pump();
    expect(documentPlainText(editor.controller.document), 'Updated body');
  });

  testWidgets('formatting is WYSIWYG and never inserts markdown markers',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final note = _note().copyWith(body: 'Gute Kaese', clearRichTextDelta: true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
          notesControllerProvider.overrideWith(
            () => _TestNotesController([note]),
          ),
        ],
        child: _editorApp(note),
      ),
    );
    await tester.pumpAndSettle();

    final editor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    editor.controller.updateSelection(
      const TextSelection(baseOffset: 0, extentOffset: 10),
      quill.ChangeSource.local,
    );
    await tester.pump();
    await tester.tap(find.byTooltip('Kursiv'));
    await tester.pump();

    expect(documentPlainText(editor.controller.document), 'Gute Kaese');
    expect(editor.controller.document.toPlainText(), isNot(contains('_')));
    expect(
      editor.controller.document.toDelta().toJson().first['attributes'],
      {'italic': true},
    );
  });

  testWidgets('checklist add control sits between open and checked items',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final note = _checklistNote();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
          notesControllerProvider.overrideWith(
            () => _TestNotesController([note]),
          ),
        ],
        child: _editorApp(note),
      ),
    );
    await tester.pumpAndSettle();

    final openY = tester.getCenter(find.widgetWithText(TextField, 'Open')).dy;
    final addY =
        tester.getCenter(find.byKey(const ValueKey('checklist-add'))).dy;
    final doneY = tester.getCenter(find.widgetWithText(TextField, 'Done')).dy;
    expect(openY, lessThan(addY));
    expect(addY, lessThan(doneY));
  });

  testWidgets('checked rows animate below the add row and back up',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final note = _checklistNote();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
          notesControllerProvider.overrideWith(
            () => _TestNotesController([note]),
          ),
        ],
        child: _editorApp(note),
      ),
    );
    await tester.pumpAndSettle();

    final openField = find.widgetWithText(TextField, 'Open');
    final startY = tester.getCenter(openField).dy;
    await tester.tap(find.byWidgetPredicate(
      (widget) => widget is Checkbox && widget.value == false,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    expect(tester.getCenter(openField).dy, greaterThan(startY));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(openField).dy,
      greaterThan(
          tester.getCenter(find.byKey(const ValueKey('checklist-add'))).dy),
    );

    final openCheckbox = find.byWidgetPredicate(
      (widget) => widget is Checkbox && widget.value == true,
    );
    await tester.tap(openCheckbox.last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 140));
    expect(tester.getCenter(openField).dy,
        lessThan(tester.getCenter(find.text('Done')).dy));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(openField).dy,
      lessThan(
          tester.getCenter(find.byKey(const ValueKey('checklist-add'))).dy),
    );
  });
}

Widget _editorApp(PlainNote note) {
  return MaterialApp(
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      quill.FlutterQuillLocalizations.delegate,
    ],
    home: NoteEditorPanel(note: note),
  );
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

PlainNote _checklistNote() {
  return PlainNote(
    localId: 'checklist-note',
    title: 'Checklist',
    body: '',
    checklist: const [
      ChecklistItem(id: 'done', text: 'Done', done: true, indent: 0),
      ChecklistItem(id: 'open', text: 'Open', done: false, indent: 0),
    ],
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

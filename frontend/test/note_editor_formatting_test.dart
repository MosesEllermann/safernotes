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

    expect(find.byTooltip('Bold'), findsOneWidget);
    expect(find.byTooltip('Italic'), findsOneWidget);
    expect(find.byTooltip('Strikethrough'), findsOneWidget);
    expect(find.byTooltip('Link'), findsOneWidget);
    expect(find.byTooltip('Code block'), findsOneWidget);
    expect(find.byTooltip('Bullet list'), findsOneWidget);
    expect(find.byTooltip('Checklist'), findsOneWidget);
    expect(find.byTooltip('Clear formatting'), findsOneWidget);
    expect(find.byTooltip('Background'), findsOneWidget);
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Redo'), findsOneWidget);

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
    await tester.tap(find.byTooltip('Undo'));
    await tester.pump();
    expect(documentPlainText(editor.controller.document), original);

    await tester.tap(find.byTooltip('Redo'));
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
    await tester.tap(find.byTooltip('Italic'));
    await tester.pump();

    expect(documentPlainText(editor.controller.document), 'Gute Kaese');
    expect(editor.controller.document.toPlainText(), isNot(contains('_')));
    expect(
      editor.controller.document.toDelta().toJson().first['attributes'],
      {'italic': true},
    );
  });

  testWidgets('body keeps focus and scroll state while typing', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final note = _note().copyWith(body: '', clearRichTextDelta: true);
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

    final initialEditor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    initialEditor.focusNode.requestFocus();
    initialEditor.controller.replaceText(
      0,
      0,
      'A',
      const TextSelection.collapsed(offset: 1),
    );
    await tester.pump();

    final rebuiltEditor = tester.widget<quill.QuillEditor>(
      find.byType(quill.QuillEditor),
    );
    expect(rebuiltEditor.focusNode, same(initialEditor.focusNode));
    expect(
        rebuiltEditor.scrollController, same(initialEditor.scrollController));
    expect(rebuiltEditor.focusNode.hasFocus, isTrue);

    rebuiltEditor.controller.replaceText(
      1,
      0,
      'B',
      const TextSelection.collapsed(offset: 2),
    );
    await tester.pump();

    expect(documentPlainText(rebuiltEditor.controller.document), 'AB');
    expect(rebuiltEditor.controller.selection.extentOffset, 2);
    expect(rebuiltEditor.focusNode.hasFocus, isTrue);
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

  testWidgets('checklist starts at the top and hides rich text actions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final note = _checklistNote().copyWith(
      checklist: const [
        ChecklistItem(id: 'open-1', text: 'Open one', done: false, indent: 0),
        ChecklistItem(id: 'open-2', text: 'Open two', done: false, indent: 0),
      ],
    );
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

    final editorTop =
        tester.getTopLeft(find.byKey(const ValueKey('editor-content'))).dy;
    final checklistTop =
        tester.getTopLeft(find.byKey(const ValueKey('checklist'))).dy;
    final openCheckboxes = find.byWidgetPredicate(
      (widget) => widget is Checkbox && widget.value == false,
    );
    final firstCheckboxTop = tester.getTopLeft(openCheckboxes.first).dy;
    final firstRowY =
        tester.getCenter(find.widgetWithText(TextField, 'Open one')).dy;
    final secondRowY =
        tester.getCenter(find.widgetWithText(TextField, 'Open two')).dy;

    expect(checklistTop, editorTop);
    expect(firstCheckboxTop - editorTop, inInclusiveRange(14, 22));
    expect(secondRowY - firstRowY, 42);
    expect(find.byTooltip('Indent'), findsNWidgets(2));
    expect(find.byTooltip('Outdent'), findsNWidgets(2));
    expect(find.byTooltip('Delete task'), findsNWidgets(2));
    expect(find.byTooltip('Reorder task'), findsNWidgets(2));
    expect(
      tester.getSize(find.byKey(const ValueKey('indent-open-1'))),
      const Size(40, 40),
    );

    final firstField = find.widgetWithText(TextField, 'Open one');
    final initialX = tester.getTopLeft(firstField).dx;
    await tester.tap(find.byKey(const ValueKey('indent-open-1')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(firstField).dx, initialX + 18);

    await tester.tap(find.byKey(const ValueKey('outdent-open-1')));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(firstField).dx, initialX);
    expect(find.byTooltip('Bold'), findsNothing);
    expect(find.byTooltip('Italic'), findsNothing);
    expect(find.byTooltip('Strikethrough'), findsNothing);
    expect(find.byTooltip('Link'), findsNothing);
    expect(find.byTooltip('Code block'), findsNothing);
    expect(find.byTooltip('Bullet list'), findsNothing);
    expect(find.byTooltip('Checklist'), findsNothing);
    expect(find.byTooltip('Clear formatting'), findsNothing);
    expect(find.byTooltip('Undo'), findsOneWidget);
    expect(find.byTooltip('Redo'), findsOneWidget);
    expect(find.byTooltip('Background'), findsOneWidget);
  });

  testWidgets('mobile header exposes all five actions directly',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

    expect(tester.getSize(find.byTooltip('Pin')), const Size(40, 40));
    expect(find.byTooltip('Invite collaborator'), findsOneWidget);
    expect(find.byTooltip('Reminder'), findsOneWidget);
    expect(find.byTooltip('Archive note'), findsOneWidget);
    expect(find.byTooltip('Move to trash'), findsOneWidget);
    expect(find.byTooltip('More actions'), findsNothing);
  });

  testWidgets('mobile checklist uses swipe gestures instead of indent buttons',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

    expect(find.byTooltip('Indent'), findsNothing);
    expect(find.byTooltip('Outdent'), findsNothing);
    expect(find.byTooltip('Reorder task'), findsNWidgets(2));
    final field = find.widgetWithText(TextField, 'Open');
    final initialX = tester.getTopLeft(field).dx;

    await tester.drag(
      find.byTooltip('Reorder task').last,
      const Offset(120, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(field).dx, initialX);

    await tester.drag(
      find.byKey(const ValueKey('swipe-indent-open')),
      const Offset(120, 0),
    );
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(field).dx, initialX + 18);
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

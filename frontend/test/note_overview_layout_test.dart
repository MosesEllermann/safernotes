import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/notes/notes_controller.dart';
import 'package:safernotes_app/features/notes/notes_screen.dart';
import 'package:safernotes_app/shared/models/note.dart';
import 'package:safernotes_app/shared/models/session.dart';
import 'package:safernotes_app/shared/widgets/animated_icon_button.dart';

void main() {
  testWidgets('cards remain the default note overview', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotes(tester);

    expect(find.byKey(const ValueKey('cards-note-overview')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-note-list')), findsNothing);
  });

  testWidgets('mobile list preference renders a compact note list',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'zk.pref.note_overview_layout': 'list',
    });
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotes(tester);

    expect(find.byKey(const ValueKey('mobile-note-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('cards-note-overview')), findsNothing);
    expect(
        find.byKey(const ValueKey('note-list-item-note-one')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('note-list-item-note-two')), findsOneWidget);
  });

  testWidgets('desktop toggle persists and opens a 30/70 split layout',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotes(tester);
    await tester.tap(
      find.byKey(const ValueKey('note-overview-layout-toggle')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('desktop-split-layout')),
      findsOneWidget,
    );
    final listSize = tester.getSize(
      find.byKey(const ValueKey('desktop-note-list-pane')),
    );
    final editorSize = tester.getSize(
      find.byKey(const ValueKey('desktop-note-editor-pane')),
    );
    expect(editorSize.width / listSize.width, closeTo(7 / 3, 0.04));
    expect(
      tester
          .getSize(find.byKey(const ValueKey('note-list-item-note-one')))
          .height,
      lessThan(75),
    );
    final selectedItem = find.byKey(
      const ValueKey('note-list-item-note-one'),
    );
    final selectedMaterial = tester.widget<Material>(
      find.descendant(of: selectedItem, matching: find.byType(Material)).first,
    );
    expect(selectedMaterial.borderRadius, BorderRadius.circular(12));
    final selectedContent = tester.widget<Padding>(
      find.byKey(const ValueKey('note-list-content-note-one')),
    );
    expect(selectedContent.padding, const EdgeInsets.fromLTRB(12, 9, 10, 9));
    final editorFrame = tester.widget<ClipRRect>(
      find.byKey(const ValueKey('desktop-note-editor-frame')),
    );
    expect(
      editorFrame.borderRadius,
      const BorderRadius.only(topLeft: Radius.circular(12)),
    );
    expect(
      find.byKey(const ValueKey('desktop-note-editor-border')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('note-list-divider-hidden-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('note-list-divider-0')),
      findsNothing,
    );
    final layoutToggle = tester.widget<AppIconButton>(
      find.byKey(const ValueKey('note-overview-layout-toggle')),
    );
    expect(layoutToggle.selected, isFalse);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('zk.pref.note_overview_layout'), 'list');
  });

  testWidgets('long pressing a list note reorders it between rows',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'zk.pref.note_overview_layout': 'list',
    });
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _TestNotesController([
      _note('note-one', 'First note', 'A short first preview.'),
      _note('note-two', 'Second note', 'A short second preview.'),
    ]);
    await _pumpNotesWithController(tester, controller);

    final first = find.byKey(const ValueKey('note-list-item-note-one'));
    final second = find.byKey(const ValueKey('note-list-item-note-two'));
    final gesture = await tester.startGesture(tester.getCenter(first));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.moveTo(tester.getCenter(second) + const Offset(0, 18));
    await tester.pump(const Duration(milliseconds: 220));
    await gesture.up();
    await tester.pump();

    expect(controller.reorderedNoteId, 'note-one');
    expect(controller.reorderedTargetIndex, greaterThan(0));
  });

  testWidgets('long pressing a list note exposes the trash drop target',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'zk.pref.note_overview_layout': 'list',
    });
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _TestNotesController([
      _note('note-one', 'First note', 'A short first preview.'),
      _note('note-two', 'Second note', 'A short second preview.'),
    ]);
    await _pumpNotesWithController(tester, controller);

    final first = find.byKey(const ValueKey('note-list-item-note-one'));
    final gesture = await tester.startGesture(tester.getCenter(first));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));
    final trash = find.byKey(const ValueKey('overview-trash-drop-target'));
    expect(trash, findsOneWidget);

    await gesture.moveTo(tester.getCenter(trash));
    await tester.pump(const Duration(milliseconds: 220));
    await gesture.up();
    await tester.pump();

    expect(controller.changedNoteId, 'note-one');
    expect(controller.changedState, 'trashed');
  });
}

Future<void> _pumpNotes(WidgetTester tester) async {
  await _pumpNotesWithController(
    tester,
    _TestNotesController([
      _note('note-one', 'First note', 'A short first preview.'),
      _note('note-two', 'Second note', 'A short second preview.'),
    ]),
  );
}

Future<void> _pumpNotesWithController(
  WidgetTester tester,
  _TestNotesController controller,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_TestAuthController.new),
        notesControllerProvider.overrideWith(() => controller),
      ],
      child: const MaterialApp(home: NotesScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

PlainNote _note(String localId, String title, String body) {
  return PlainNote(
    localId: localId,
    title: title,
    body: body,
    checklist: const [],
    updatedAt: DateTime.utc(2026, 8, 24),
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
      emailVerified: true,
    );
  }
}

class _TestNotesController extends NotesController {
  _TestNotesController(this.notes);

  final List<PlainNote> notes;
  String? reorderedNoteId;
  int? reorderedTargetIndex;
  String? changedNoteId;
  String? changedState;

  @override
  Future<List<PlainNote>> build() async => notes;

  @override
  Future<void> reorderNotes({
    required String draggedId,
    required int targetIndex,
    required String bucket,
  }) async {
    reorderedNoteId = draggedId;
    reorderedTargetIndex = targetIndex;
  }

  @override
  Future<void> changeState(PlainNote note, String nextState) async {
    changedNoteId = note.localId;
    changedState = nextState;
  }
}

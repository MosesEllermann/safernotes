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
  testWidgets('desktop note drag feedback keeps the rendered card size',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final shortNote = _note(
      localId: 'note-short',
      title: 'Short measured note',
      body: 'Tiny body.',
    );
    final longNote = _note(
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
            () => _TestNotesController([shortNote, longNote]),
          ),
        ],
        child: const MaterialApp(home: NotesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final shortCardFinder =
        find.byKey(const ValueKey('compact-note-drag-note-short'));
    final longCardFinder =
        find.byKey(const ValueKey('compact-note-drag-note-long'));
    expect(shortCardFinder, findsOneWidget);
    expect(longCardFinder, findsOneWidget);
    final shortCardSize = tester.getSize(shortCardFinder);
    final longCardSize = tester.getSize(longCardFinder);
    expect(longCardSize.height, greaterThan(shortCardSize.height));

    final gesture = await tester.startGesture(tester.getCenter(longCardFinder));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await tester.pump();

    final feedbackFinder =
        find.byKey(const ValueKey('note-drag-feedback-note-long'));
    expect(feedbackFinder, findsOneWidget);
    expect(tester.getSize(feedbackFinder), longCardSize);
    expect(tester.getSize(feedbackFinder), isNot(shortCardSize));

    await gesture.up();
  });

  testWidgets('dragging a note onto the overview bin moves it to trash',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final note = _note(
      localId: 'note-to-trash',
      title: 'Drop me',
      body: 'A note ready for the trash target.',
    );
    final controller = _TestNotesController([note]);
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

    final card = find.byKey(const ValueKey('compact-note-drag-note-to-trash'));
    final gesture = await tester.startGesture(tester.getCenter(card));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 200));

    final target = find.byKey(const ValueKey('overview-trash-drop-target'));
    expect(target, findsOneWidget);
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 220));
    expect(
        find.byKey(const ValueKey('overview-trash-hovered')), findsOneWidget);
    final feedbackOpacity = tester.widget<AnimatedOpacity>(
      find.byKey(
        const ValueKey('note-drag-trash-opacity-note-to-trash'),
      ),
    );
    expect(feedbackOpacity.opacity, 0.52);

    await gesture.up();
    await tester.pump();
    expect(controller.changedNoteId, 'note-to-trash');
    expect(controller.changedState, 'trashed');
    expect(find.text('Note moved to trash.'), findsOneWidget);
  });

  testWidgets('cards glide into their preview positions while reordering',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final notes = [
      for (var index = 1; index <= 4; index += 1)
        _note(
          localId: 'note-$index',
          title: 'Note $index',
          body: 'Preview $index',
        ),
    ];
    final controller = _TestNotesController(notes);
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

    final first = find.byKey(const ValueKey('compact-note-drag-note-1'));
    final fourth = find.byKey(const ValueKey('compact-note-drag-note-4'));
    final secondPlacement =
        find.byKey(const ValueKey('animated-note-placement-note-2'));
    final firstStart = tester.getTopLeft(first);
    final fourthCenter = tester.getCenter(fourth);
    final secondStart = tester.getTopLeft(secondPlacement);
    final motion = tester.widget<AnimatedPositioned>(secondPlacement);
    expect(motion.duration, const Duration(milliseconds: 190));
    expect(motion.curve, Curves.easeOutCubic);
    final draggable = tester.widget<LongPressDraggable<PlainNote>>(
      find
          .descendant(
            of: first,
            matching: find.byWidgetPredicate(
              (widget) => widget is LongPressDraggable<PlainNote>,
            ),
          )
          .first,
    );
    expect(draggable.delay, const Duration(milliseconds: 260));
    expect(
        find.byKey(const ValueKey('card-grid-drop-surface')), findsOneWidget);

    final gesture = await tester.startGesture(tester.getCenter(first));
    await tester.pump(const Duration(milliseconds: 360));
    await gesture.moveTo(fourthCenter);
    await tester.pump();
    expect(tester.getTopLeft(secondPlacement).dx, closeTo(secondStart.dx, 0.5));

    await tester.pump(const Duration(milliseconds: 80));
    final secondMidway = tester.getTopLeft(secondPlacement);
    expect(secondMidway.dx, lessThan(secondStart.dx));
    expect(secondMidway.dx, greaterThan(firstStart.dx));

    await tester.pump(const Duration(milliseconds: 160));
    expect(tester.getTopLeft(secondPlacement).dx, closeTo(firstStart.dx, 0.5));

    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.reorderedNoteId, 'note-1');
    expect(controller.reorderedTargetIndex, 3);
  });

  testWidgets('card preview and committed index agree when moving backwards',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final notes = [
      for (var index = 1; index <= 7; index += 1)
        _note(
          localId: 'note-$index',
          title: 'Note $index',
          body: 'Preview $index',
        ),
    ];
    final controller = _TestNotesController(notes);
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

    final dragged = find.byKey(const ValueKey('compact-note-drag-note-6'));
    final target = find.byKey(const ValueKey('compact-note-drag-note-2'));
    final secondPlacement =
        find.byKey(const ValueKey('animated-note-placement-note-2'));
    final secondStart = tester.getTopLeft(secondPlacement);
    final secondStartDestination =
        tester.widget<AnimatedPositioned>(secondPlacement).left!;
    final targetCenter = tester.getCenter(target);

    final gesture = await tester.startGesture(tester.getCenter(dragged));
    await tester.pump(const Duration(milliseconds: 360));
    await gesture.moveTo(targetCenter);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 240));
    final secondPreview = tester.getTopLeft(secondPlacement);
    final secondDestination =
        tester.widget<AnimatedPositioned>(secondPlacement).left!;

    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.reorderedNoteId, 'note-6');
    expect(controller.reorderedTargetIndex, 1);
    expect(secondDestination, greaterThan(secondStartDestination));
    expect(secondPreview.dx, greaterThan(secondStart.dx));
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
  String? changedNoteId;
  String? changedState;
  String? reorderedNoteId;
  int? reorderedTargetIndex;

  @override
  Future<List<PlainNote>> build() async => _notes;

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

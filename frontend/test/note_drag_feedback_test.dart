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

  @override
  Future<List<PlainNote>> build() async => _notes;

  @override
  Future<void> reorderNotes({
    required String draggedId,
    required int targetIndex,
    required String bucket,
  }) async {}

  @override
  Future<void> changeState(PlainNote note, String nextState) async {
    changedNoteId = note.localId;
    changedState = nextState;
  }
}

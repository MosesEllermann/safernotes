import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/notes/notes_controller.dart';
import 'package:safernotes_app/features/notes/notes_screen.dart';
import 'package:safernotes_app/shared/models/note.dart';
import 'package:safernotes_app/shared/models/session.dart';

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

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('zk.pref.note_overview_layout'), 'list');
  });
}

Future<void> _pumpNotes(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_TestAuthController.new),
        notesControllerProvider.overrideWith(
          () => _TestNotesController([
            _note('note-one', 'First note', 'A short first preview.'),
            _note('note-two', 'Second note', 'A short second preview.'),
          ]),
        ),
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

  @override
  Future<List<PlainNote>> build() async => notes;
}

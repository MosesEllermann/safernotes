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
  testWidgets('new reminder selects an existing note before date and time',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
          notesControllerProvider.overrideWith(
            () => _TestNotesController([
              _note(localId: 'alpha', title: 'Alpha note'),
              _note(
                localId: 'scheduled',
                title: 'Already scheduled',
                reminderAt: DateTime.utc(2020, 1, 1),
              ),
              _note(
                localId: 'archived',
                title: 'Archived note',
                state: 'archived',
              ),
            ]),
          ),
        ],
        child: const MaterialApp(home: NotesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Create'));
    await tester.pump(const Duration(milliseconds: 300));
    final reminderOption = find.ancestor(
      of: find.text('Set reminder'),
      matching: find.byType(InkWell),
    );
    tester.widget<InkWell>(reminderOption).onTap?.call();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('reminder-note-picker')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('reminder-note-alpha')),
      findsOneWidget,
    );
    expect(find.text('Already scheduled'), findsNothing);
    expect(find.text('Archived note'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('reminder-note-alpha')));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.text('Alpha note'),
      ),
      findsOneWidget,
    );
    expect(find.text('Date'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Set reminder'), findsOneWidget);
  });
}

PlainNote _note({
  required String localId,
  required String title,
  String state = 'active',
  DateTime? reminderAt,
}) {
  return PlainNote(
    localId: localId,
    title: title,
    body: 'Note body',
    checklist: const [],
    updatedAt: DateTime.utc(2026, 8, 24),
    pinned: false,
    color: 0xffffffff,
    sortOrder: 0,
    dirty: false,
    version: 1,
    state: state,
    reminderAt: reminderAt,
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
  _TestNotesController(this.notes);

  final List<PlainNote> notes;

  @override
  Future<List<PlainNote>> build() async => notes;
}

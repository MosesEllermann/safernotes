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
  testWidgets('titleless cards move rich formatting into the preview',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final note = PlainNote(
      localId: 'preview-note',
      title: '',
      body: 'Bold preview',
      richTextDelta: const [
        {
          'insert': 'Bold',
          'attributes': {'bold': true},
        },
        {'insert': ' preview'},
        {
          'insert': '\n',
          'attributes': {'list': 'bullet'},
        },
      ],
      checklist: const [],
      updatedAt: DateTime.utc(2026, 8, 24),
      pinned: false,
      color: 0xffffffff,
      sortOrder: 0,
      dirty: false,
      version: 1,
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

    expect(find.text('Untitled note'), findsNothing);
    final preview = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('\u2022 Bold preview'),
    );
    expect(preview, findsOneWidget);
    final richText = tester.widget<RichText>(preview);
    expect(_containsBoldSpan(richText.text), isTrue);
  });

  testWidgets('cards without metadata do not reserve footer space',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final plain = _plainNote(localId: 'plain-card', shared: false);
    final shared = _plainNote(localId: 'shared-card', shared: true);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
          notesControllerProvider.overrideWith(
            () => _TestNotesController([plain, shared]),
          ),
        ],
        child: const MaterialApp(home: NotesScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final plainHeight = tester
        .getSize(find.byKey(const ValueKey('compact-note-drag-plain-card')))
        .height;
    final sharedHeight = tester
        .getSize(find.byKey(const ValueKey('compact-note-drag-shared-card')))
        .height;
    expect(sharedHeight, greaterThan(plainHeight));
  });
}

PlainNote _plainNote({required String localId, required bool shared}) {
  return PlainNote(
    localId: localId,
    title: 'Same title',
    body: 'Same body',
    checklist: const [],
    updatedAt: DateTime.utc(2026, 8, 24),
    pinned: false,
    color: 0xffffffff,
    sortOrder: 0,
    dirty: false,
    version: 1,
    shared: shared,
  );
}

bool _containsBoldSpan(InlineSpan span) {
  if (span.style?.fontWeight == FontWeight.w700) return true;
  if (span is! TextSpan) return false;
  return span.children?.any(_containsBoldSpan) ?? false;
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/notes/notes_controller.dart';
import 'package:safernotes_app/features/notes/notes_screen.dart';
import 'package:safernotes_app/shared/models/note.dart';
import 'package:safernotes_app/shared/models/session.dart';
import 'package:safernotes_app/shared/theme/app_theme.dart';

void main() {
  testWidgets('large mobile collections render in bounded card batches',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notes = List<PlainNote>.generate(500, _note);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_StressAuthController.new),
          notesControllerProvider.overrideWith(
            () => _StressNotesController(notes),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(
            Brightness.light,
            platform: TargetPlatform.android,
          ),
          home: const NotesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Finder renderedCards() => find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('note-card-content-');
        });

    expect(renderedCards(), findsNWidgets(48));
    expect(find.byKey(const ValueKey('load-more-note-cards')), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(
      find.byKey(const ValueKey('load-more-note-cards')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('load-more-note-cards')));
    await tester.pumpAndSettle();

    expect(renderedCards(), findsNWidgets(96));
    expect(find.byKey(const ValueKey('load-more-note-cards')), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('large mobile lists stay lazy during repeated fast scrolling',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'zk.pref.note_overview_layout': 'list',
    });
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notes = List<PlainNote>.generate(500, _note);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_StressAuthController.new),
          notesControllerProvider.overrideWith(
            () => _StressNotesController(notes),
          ),
        ],
        child: MaterialApp(
          theme: buildAppTheme(
            Brightness.light,
            platform: TargetPlatform.android,
          ),
          home: const NotesScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    Finder renderedRows() => find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> &&
              key.value.startsWith('note-list-item-');
        });

    expect(renderedRows().evaluate().length, lessThan(20));
    expect(find.byKey(const ValueKey('note-card-content-stress-note-0')),
        findsNothing);

    for (var pass = 0; pass < 12; pass += 1) {
      await tester.fling(
        find.byType(ListView),
        const Offset(0, -520),
        2600,
      );
      await tester.pumpAndSettle();
      expect(renderedRows().evaluate().length, lessThan(20));
      expect(tester.takeException(), isNull);
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

PlainNote _note(int index) {
  return PlainNote(
    localId: 'stress-note-$index',
    title: 'Stress note $index',
    body: List.filled(8, 'Readable content for a constrained phone.').join(' '),
    checklist: const [],
    updatedAt: DateTime.utc(2026, 9, 14).subtract(Duration(minutes: index)),
    pinned: index % 11 == 0,
    color: brandNoteColors[index % brandNoteColors.length],
    sortOrder: index * 1000,
    dirty: false,
    version: 1,
    state: 'active',
  );
}

class _StressAuthController extends AuthController {
  @override
  Future<AppSession?> build() async => const AppSession(
        email: 'stress@example.test',
        accessToken: 'stress-token',
        refreshToken: 'stress-refresh-token',
        defaultTenant: 'stress-tenant',
        masterKey: [0, 1, 2, 3],
      );
}

class _StressNotesController extends NotesController {
  _StressNotesController(this.notes);

  final List<PlainNote> notes;

  @override
  Future<List<PlainNote>> build() async => notes;
}

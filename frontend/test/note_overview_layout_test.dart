import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/notes/notes_controller.dart';
import 'package:safernotes_app/features/notes/notes_screen.dart';
import 'package:safernotes_app/features/notes/note_editor_screen.dart';
import 'package:safernotes_app/main.dart';
import 'package:safernotes_app/shared/app/app_preferences.dart';
import 'package:safernotes_app/shared/models/note.dart';
import 'package:safernotes_app/shared/models/session.dart';
import 'package:safernotes_app/shared/theme/app_theme.dart';
import 'package:safernotes_app/shared/widgets/animated_icon_button.dart';

void main() {
  testWidgets('notes and editor follow light dark and system preferences',
      (tester) async {
    SharedPreferences.setMockInitialValues({'zk.pref.theme': 'dark'});
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authControllerProvider.overrideWith(_TestAuthController.new),
          notesControllerProvider.overrideWith(() => _TestNotesController([
                _note('note-one', 'First note', 'A short preview.'),
              ])),
        ],
        child: const SafernotesApp(),
      ),
    );
    await tester.pumpAndSettle();
    final preferences = ProviderScope.containerOf(
      tester.element(find.byType(SafernotesApp)),
    ).read(appPreferencesProvider.notifier);

    for (final width in [390.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 900);
      for (final (mode, systemBrightness, expected) in [
        (ThemeMode.light, Brightness.dark, Brightness.light),
        (ThemeMode.dark, Brightness.light, Brightness.dark),
        (ThemeMode.system, Brightness.light, Brightness.light),
        (ThemeMode.system, Brightness.dark, Brightness.dark),
      ]) {
        tester.platformDispatcher.platformBrightnessTestValue =
            systemBrightness;
        await preferences.setThemeMode(mode);
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.text('First note'))).brightness,
          expected,
        );
        await tester.tap(find.text('First note'));
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byType(NoteEditorPanel))).brightness,
          expected,
        );
        Navigator.of(tester.element(find.byType(NoteEditorPanel))).pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    }
  });

  testWidgets('Apple theme survives resizing from desktop to mobile',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotesWithController(
      tester,
      _TestNotesController([
        _note('note-one', 'First note', 'A short first preview.'),
      ]),
      theme: buildAppTheme(Brightness.dark, platform: TargetPlatform.macOS),
    );
    for (final width in [390.0, 600.0, 899.0, 900.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 844);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 1));

      expect(tester.takeException(), isNull);
      expect(find.text('First note'), findsOneWidget);
      if (width < 900) {
        expect(find.byTooltip('Create'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('mobile-bottom-nav-pill')),
          findsOneWidget,
        );
        expect(find.byType(NavigationBar), findsNothing);
      }
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('opened note has one rounded surface without a dialog outline',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotesWithController(
      tester,
      _TestNotesController([
        _note('note-one', 'First note', 'A short first preview.'),
      ]),
      theme: buildAppTheme(Brightness.dark, platform: TargetPlatform.macOS),
    );
    await tester.tap(find.text('First note'));
    await tester.pumpAndSettle();

    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect((dialog.shape! as RoundedRectangleBorder).side, BorderSide.none);
    expect(dialog.backgroundColor, Colors.transparent);
    expect(dialog.elevation, 0);
    final surface = tester.widget<Material>(
      find.byKey(const ValueKey('note-editor-surface')),
    );
    expect(surface.borderRadius, BorderRadius.circular(AppRadii.card));
    expect(surface.clipBehavior, Clip.antiAlias);
    expect(surface.elevation, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark mobile canvas has integrated header controls',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotesWithController(
      tester,
      _TestNotesController([
        _note('note-one', 'First note', 'A short preview.'),
      ]),
      theme: buildAppTheme(Brightness.dark),
    );

    final canvas = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byKey(const ValueKey('notes-app-canvas')),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    final gradient = (canvas.decoration as BoxDecoration).gradient!;
    expect(gradient.colors.first, const Color(0xff0d1513));
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const ValueKey('mobile-layout-toggle')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-account-menu')), findsOneWidget);
  });

  testWidgets('cards remain the default note overview', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotes(tester);

    expect(find.byKey(const ValueKey('cards-note-overview')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-note-list')), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile-bottom-nav-pill')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mobile-nav-create')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-nav-settings')), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile-layout-toggle'))),
      const Size.square(52),
    );
    final notesButton = find.byKey(const ValueKey('mobile-nav-notes'));
    expect(tester.getSize(notesButton), const Size.square(52));
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: notesButton,
              matching: find.byType(Icon),
            ),
          )
          .size,
      20,
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile-nav-create'))),
      const Size.square(52),
    );
    expect(
      tester
          .widget<Icon>(
            find.descendant(
              of: find.byKey(const ValueKey('mobile-nav-create')),
              matching: find.byType(Icon),
            ),
          )
          .size,
      21,
    );
    // 4 items of 52 + 3 gaps of 6 + 6 inset on both sides.
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile-bottom-nav-pill'))),
      const Size(238, 64),
    );

    await tester.tap(find.byKey(const ValueKey('mobile-nav-create')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    final expandedNavSize = tester.getSize(
      find.byKey(const ValueKey('mobile-bottom-nav-pill')),
    );
    expect(expandedNavSize.width, 238);
    expect(expandedNavSize.height, greaterThan(210));
    expect(find.byKey(const ValueKey('mobile-create-note-action')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-create-reminder-action')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mobile-create-list-action')),
        findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('mobile header toggles layout and opens account sidebar',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotes(tester);

    await tester.tap(find.byKey(const ValueKey('mobile-layout-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-note-list')), findsOneWidget);

    final accountButton = find.descendant(
      of: find.byKey(const ValueKey('mobile-account-menu')),
      matching: find.byType(GestureDetector),
    );
    await tester.tap(accountButton);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mobile-account-side-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-sidebar-sync-status')),
      findsOneWidget,
    );
    expect(find.byType(BackdropFilter), findsWidgets);
    expect(find.byKey(const ValueKey('mobile-note-list')), findsOneWidget);
  });

  testWidgets('sparse desktop grids keep a balanced card width',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotesWithController(
      tester,
      _TestNotesController([
        _note('note-one', 'First note', 'A short preview.'),
      ]),
    );

    final card = find.byKey(
      const ValueKey('compact-note-drag-note-one'),
    );
    expect(card, findsOneWidget);
    expect(tester.getSize(card).width, lessThan(400));
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
    // The list is borderless now: spacing separates rows, no divider lines.
    expect(
      find.byKey(const ValueKey('note-list-divider-hidden-0')),
      findsNothing,
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
  _TestNotesController controller, {
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authControllerProvider.overrideWith(_TestAuthController.new),
        notesControllerProvider.overrideWith(() => controller),
      ],
      child: MaterialApp(
        theme: theme,
        localizationsDelegates:
            quill.FlutterQuillLocalizations.localizationsDelegates,
        home: const NotesScreen(),
      ),
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

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/notes/notes_controller.dart';
import 'package:safernotes_app/features/notes/notes_screen.dart';
import 'package:safernotes_app/features/notes/note_editor_screen.dart';
import 'package:safernotes_app/features/settings/settings_screen.dart';
import 'package:safernotes_app/main.dart';
import 'package:safernotes_app/shared/api/api_client.dart';
import 'package:safernotes_app/shared/app/app_preferences.dart';
import 'package:safernotes_app/shared/models/note.dart';
import 'package:safernotes_app/shared/models/session.dart';
import 'package:safernotes_app/shared/providers.dart';
import 'package:safernotes_app/shared/theme/app_icons.dart';
import 'package:safernotes_app/shared/theme/app_theme.dart';
import 'package:safernotes_app/shared/widgets/animated_icon_button.dart';

void main() {
  test('note-card corners derive from the favorite-button geometry', () {
    expect(
      AppRadii.noteCardCompact,
      AppRadii.favoriteButtonCompact * AppRadii.noteCardCornerScale,
    );
    expect(
      AppRadii.noteCard,
      AppRadii.favoriteButton * AppRadii.noteCardCornerScale,
    );
    expect(AppRadii.noteCardCornerScale, inInclusiveRange(1.5, 1.8));
    expect(AppSizes.iosCompactHeaderIcon, 17);
  });

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
        expect(
          find.byKey(const ValueKey('desktop-note-editor-backdrop')),
          width >= 900 ? findsOneWidget : findsNothing,
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
      expect(
        find.byKey(const ValueKey('desktop-note-backdrop-note-one')),
        width >= 900 ? findsOneWidget : findsNothing,
      );
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
    expect(
      find.byKey(const ValueKey('desktop-note-editor-backdrop')),
      findsOneWidget,
    );
    final titleRow = find.byKey(
      const ValueKey('desktop-editor-title-row'),
    );
    final backButton = find.byKey(const ValueKey('editor-back-button'));
    final title = find.byKey(const ValueKey('note-editor-title'));
    final actions = find.byKey(const ValueKey('editor-header-action-bar'));
    expect(titleRow, findsOneWidget);
    expect(
      tester.getTopLeft(title).dx,
      greaterThan(tester.getTopRight(backButton).dx),
    );
    expect(
      tester.getTopRight(title).dx,
      lessThan(tester.getTopLeft(actions).dx),
    );
    final titleAlignment = tester.widget<Transform>(
      find.byKey(const ValueKey('desktop-editor-title-alignment')),
    );
    expect(titleAlignment.transform.getTranslation().y, -4);
    expect(
      tester.getCenter(title).dy,
      closeTo(tester.getCenter(actions).dy - 4, 0.01),
    );
    expect(tester.getSize(actions).width, 204);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile editor exposes five actions above the lowered title',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotesWithController(
      tester,
      _TestNotesController([
        _note('note-one', 'First note', 'A short first preview.'),
      ]),
      theme: buildAppTheme(Brightness.dark, platform: TargetPlatform.android),
    );
    await tester.tap(find.text('First note'));
    await tester.pumpAndSettle();

    final actions = find.byKey(const ValueKey('editor-header-action-bar'));
    final title = find.byKey(const ValueKey('note-editor-title'));
    expect(actions, findsOneWidget);
    expect(title, findsOneWidget);
    expect(
      find.descendant(of: actions, matching: find.byType(AppIconButton)),
      findsNWidgets(5),
    );
    expect(tester.getSize(actions).width, 224);
    expect(tester.getTopLeft(title).dy,
        greaterThan(tester.getBottomLeft(actions).dy));

    final titleField = tester.widget<TextField>(title);
    final titleStyle =
        Theme.of(tester.element(title)).textTheme.headlineMedium!;
    expect(titleField.style?.fontSize, titleStyle.fontSize);
    expect(titleField.style?.fontWeight, titleStyle.fontWeight);
    expect(
      find.byKey(const ValueKey('desktop-note-editor-backdrop')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('dark mobile canvas has integrated header controls',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 30);
    tester.view.viewPadding = const FakeViewPadding(top: 30);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

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
    final systemUi = tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(
      find.byKey(const ValueKey('notes-system-ui-overlay')),
    );
    expect(systemUi.value.statusBarColor, Colors.transparent);
    expect(systemUi.value.statusBarIconBrightness, Brightness.light);
    expect(systemUi.value.systemStatusBarContrastEnforced, isFalse);
    expect(
      find.byKey(const ValueKey('notes-glass-header-tint-dark')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('notes-glass-header-highlight')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('notes-glass-header-light-haze')),
      findsNothing,
    );
    final darkNavFill = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('mobile-nav-drawer-fill')),
    );
    expect(
      (darkNavFill.decoration as ShapeDecoration).color,
      AppChromeGlass.darkTint,
    );
    final darkCountBadge = tester.widget<Container>(
      find.byKey(const ValueKey('note-filter-count-badge')),
    );
    expect(
      (darkCountBadge.decoration! as BoxDecoration).color,
      const Color(0xff4b4354),
    );
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('note-filter-count-badge')),
              matching: find.byType(Text),
            ),
          )
          .style
          ?.color,
      const Color(0xfff8f4fa),
    );
  });

  testWidgets('email confirmation reminder follows the label filters',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotesWithController(
      tester,
      _TestNotesController([
        _note('note-one', 'First note', 'A short first preview.'),
      ]),
      authControllerBuilder: _UnverifiedTestAuthController.new,
    );

    final filters = find.byKey(const ValueKey('note-filter-chips'));
    final banner = find.byKey(const ValueKey('email-verification-banner'));
    final header = find.byKey(const ValueKey('notes-workspace-header-body'));
    expect(banner, findsOneWidget);
    expect(
      find.descendant(of: header, matching: banner),
      findsOneWidget,
    );
    expect(
      tester.getTopLeft(banner).dy,
      greaterThan(tester.getBottomLeft(filters).dy),
    );
    final glassCard = find.byKey(const ValueKey('notes-glass-header-card'));
    expect(
      tester.getBottomLeft(glassCard).dy - tester.getBottomLeft(banner).dy,
      closeTo(16, 0.01),
    );
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
      find.byKey(const ValueKey('desktop-note-backdrop-note-one')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mobile-bottom-nav-pill')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mobile-nav-create')), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-nav-settings')), findsNothing);
    expect(find.byType(FloatingActionButton), findsNothing);
    final firstCard = find.byKey(
      const ValueKey('compact-note-drag-note-one'),
    );
    final continuousCardSurface = tester
        .widgetList<Material>(
          find.descendant(of: firstCard, matching: find.byType(Material)),
        )
        .singleWhere((material) => material.shape is RoundedSuperellipseBorder);
    final continuousShape =
        continuousCardSurface.shape! as RoundedSuperellipseBorder;
    expect(
      continuousShape.borderRadius,
      BorderRadius.circular(AppRadii.noteCardCompact),
    );
    final cardContent = tester.widget<Padding>(
      find.byKey(const ValueKey('note-card-content-note-one')),
    );
    expect(
      cardContent.padding,
      const EdgeInsets.fromLTRB(14, 12, 14, 14),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile-layout-toggle'))),
      const Size.square(50),
    );
    final notesButton = find.byKey(const ValueKey('mobile-nav-notes'));
    expect(tester.getSize(notesButton), const Size.square(50));
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
      const Size.square(50),
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
    // 5 items of 50 + 4 gaps of 7 + 6 inset on every outer edge.
    expect(
      tester.getSize(find.byKey(const ValueKey('mobile-bottom-nav-pill'))),
      const Size(290, 62),
    );
    expect(find.byKey(const ValueKey('mobile-nav-search')), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(
      find.byKey(const ValueKey('mobile-bottom-nav-backdrop')),
      findsNothing,
    );
    final navFill = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('mobile-nav-drawer-fill')),
    );
    expect(
      (navFill.decoration as ShapeDecoration).color,
      AppChromeGlass.lightTint,
    );
    expect(
      find.ancestor(
        of: find.byKey(const ValueKey('mobile-bottom-nav-pill')),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );

    await tester.tap(find.byKey(const ValueKey('mobile-nav-create')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 24));
    expect(
      find.byKey(const ValueKey('mobile-create-actions-progress')),
      findsOneWidget,
    );
    final actionsClip = find.byKey(
      const ValueKey('mobile-create-actions-clip'),
    );
    expect(actionsClip, findsOneWidget);
    final enteringDrawer = find.byKey(const ValueKey('mobile-nav-drawer-fill'));
    final enteringFirstAction =
        find.byKey(const ValueKey('mobile-create-note-action'));
    expect(
      tester.getTopLeft(enteringFirstAction).dy,
      greaterThanOrEqualTo(tester.getTopLeft(enteringDrawer).dy),
    );
    expect(
      find.ancestor(of: enteringFirstAction, matching: actionsClip),
      findsOneWidget,
    );
    final bubbleScales = List.generate(
      3,
      (index) => tester
          .widget<Transform>(
            find.byKey(ValueKey('mobile-create-action-bubble-$index')),
          )
          .transform
          .entry(0, 0),
    );
    expect(bubbleScales[0], greaterThan(bubbleScales[1]));
    expect(bubbleScales[1], greaterThan(bubbleScales[2]));
    expect(bubbleScales[0], lessThan(0.9));
    expect(bubbleScales[0], lessThanOrEqualTo(1.04));
    expect(find.byKey(const ValueKey('mobile-create-note-action')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-create-reminder-action')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mobile-create-list-action')),
        findsOneWidget);
    await tester.pump(const Duration(milliseconds: 230));

    expect(
      tester.getSize(find.byKey(const ValueKey('mobile-bottom-nav-pill'))),
      const Size(290, 62),
    );
    final expandedMenuHeight = tester
        .getSize(find.byKey(const ValueKey('mobile-create-popout-layout')))
        .height;
    expect(expandedMenuHeight, 145);
    expect(find.byKey(const ValueKey('mobile-create-note-action')),
        findsOneWidget);
    expect(
      find.byKey(const ValueKey('mobile-create-reminder-action')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mobile-create-list-action')),
        findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    final actionKeys = [
      'mobile-create-note-action',
      'mobile-create-reminder-action',
      'mobile-create-list-action',
    ];
    final actionRects = actionKeys
        .map((key) => tester.getRect(find.byKey(ValueKey(key))))
        .toList();
    expect(actionRects.map((rect) => rect.top).toSet(), hasLength(1));
    expect(actionRects.map((rect) => rect.height).toSet(), {68.0});
    expect(actionRects[0].right, lessThan(actionRects[1].left));
    expect(actionRects[1].right, lessThan(actionRects[2].left));
    for (final key in actionKeys) {
      final action = find.byKey(ValueKey(key));
      expect(
        find.descendant(of: action, matching: find.byType(BackdropFilter)),
        findsNothing,
      );
      final actionMaterial = tester
          .widgetList<Material>(
            find.descendant(of: action, matching: find.byType(Material)),
          )
          .singleWhere(
            (material) => material.shape is RoundedSuperellipseBorder,
          );
      expect(actionMaterial.clipBehavior, Clip.antiAlias);
      expect(
        (actionMaterial.shape! as RoundedSuperellipseBorder).side,
        BorderSide.none,
      );
      expect(
        (actionMaterial.shape! as RoundedSuperellipseBorder).borderRadius,
        BorderRadius.circular(24),
      );
      final actionIcon = tester.widgetList<Icon>(
        find.descendant(of: action, matching: find.byType(Icon)),
      );
      expect(actionIcon.single.size, 18);
      final actionLabel = tester.widgetList<Text>(
        find.descendant(of: action, matching: find.byType(Text)),
      );
      expect(actionLabel.single.style?.fontSize, 12);
      expect(actionLabel.single.style?.height, 1.05);
    }
    final drawerFill = tester.widget<DecoratedBox>(
      find.byKey(const ValueKey('mobile-nav-drawer-fill')),
    );
    final drawerShape = (drawerFill.decoration as ShapeDecoration).shape;
    expect(drawerShape, isA<RoundedSuperellipseBorder>());
    expect(
      (drawerShape as RoundedSuperellipseBorder).borderRadius,
      const BorderRadius.only(
        topLeft: Radius.circular(32),
        topRight: Radius.circular(32),
        bottomLeft: Radius.circular(31),
        bottomRight: Radius.circular(31),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('mobile-nav-create')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 24));
    final closingMenuHeight = tester
        .getSize(find.byKey(const ValueKey('mobile-create-popout-layout')))
        .height;
    // The composited menu keeps a stable layout box so the native nav surface
    // never has to move/re-layout on each animation frame.
    expect(closingMenuHeight, expandedMenuHeight);
    expect(
      find.byKey(const ValueKey('mobile-create-actions-progress')),
      findsOneWidget,
    );
    final closingActions = tester.widget<Transform>(
      find.byKey(const ValueKey('mobile-create-actions-progress')),
    );
    expect(closingActions.transform.getTranslation().y, 0);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-create-actions-progress')),
      findsNothing,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile-create-popout-layout')))
          .height,
      expandedMenuHeight,
    );
  });

  testWidgets('trash can be emptied after explicit confirmation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _TestNotesController([
      _note('trashed-one', 'Discard me', 'No longer needed')
          .copyWith(state: 'trashed'),
    ]);
    await _pumpNotesWithController(tester, controller);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(NotesScreen)),
    );
    container.read(noteBucketProvider.notifier).state = 'trashed';
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('empty-trash-button')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('empty-trash-button')));
    await tester.pumpAndSettle();
    expect(find.text('Empty trash?'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('confirm-empty-trash')));
    await tester.pumpAndSettle();

    expect(controller.emptyTrashCalls, 1);
    expect(find.text('1 notes permanently deleted.'), findsOneWidget);
  });

  testWidgets('dragging with an open create drawer collapses to a compact bin',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotes(tester);
    await tester.tap(find.byKey(const ValueKey('mobile-nav-create')));
    await tester.pumpAndSettle();
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile-create-popout-layout')))
          .height,
      145,
    );

    final card = find.byKey(const ValueKey('compact-note-drag-note-one'));
    final gesture = await tester.startGesture(tester.getCenter(card));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 220));
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));

    expect(
        find.byKey(const ValueKey('mobile-create-note-action')), findsNothing);
    final surface = tester.widget<Positioned>(
      find.byKey(const ValueKey('mobile-nav-drawer-surface-position')),
    );
    expect(surface.height, lessThanOrEqualTo(88));
    final trashSize = tester.getSize(
      find.byKey(const ValueKey('mobile-nav-trash-drop-target')),
    );
    expect(trashSize.width, 76);
    expect(trashSize.height, lessThanOrEqualTo(76));
    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('mobile overview resets after layout, settings and app resume',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final notes = [
      for (var index = 0; index < 18; index++)
        _note('note-$index', 'Note $index', 'Preview $index'),
    ];
    await _pumpNotesWithController(tester, _TestNotesController(notes));

    double scrollOffset(Key key) {
      final scrollable = find
          .descendant(
            of: find.byKey(key),
            matching: find.byType(Scrollable),
          )
          .first;
      return tester.state<ScrollableState>(scrollable).position.pixels;
    }

    const cardsKey = ValueKey('cards-note-overview');
    await tester.drag(find.byKey(cardsKey), const Offset(0, -360));
    await tester.pumpAndSettle();
    expect(scrollOffset(cardsKey), greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('mobile-layout-toggle')));
    await tester.pumpAndSettle();
    const listKey = ValueKey('mobile-note-list');
    expect(scrollOffset(listKey), 0);

    await tester.drag(find.byKey(listKey), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(scrollOffset(listKey), greaterThan(0));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(scrollOffset(listKey), 0);

    await tester.drag(find.byKey(listKey), const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mobile-account-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
    await tester.pumpAndSettle();
    expect(scrollOffset(listKey), 0);
  });

  testWidgets('Android system gesture inset does not scroll the notes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    tester.view.systemGestureInsets = const FakeViewPadding(bottom: 24);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetSystemGestureInsets);
    await _pumpNotesWithController(
      tester,
      _TestNotesController([
        for (var index = 0; index < 18; index++)
          _note('note-$index', 'Note $index', 'Preview $index'),
      ]),
      theme: buildAppTheme(Brightness.dark, platform: TargetPlatform.android),
    );

    final guard = find.byKey(const ValueKey('android-system-gesture-guard'));
    expect(guard, findsOneWidget);
    expect(tester.getSize(guard).height, 32);
    expect(
      find.byKey(const ValueKey('mobile-bottom-nav-backdrop')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('mobile-header-button-backdrop')),
      findsNothing,
    );
    final gesture = await tester.startGesture(const Offset(4, 845));
    await gesture.moveBy(const Offset(0, -220));
    await gesture.up();
    await tester.pumpAndSettle();
    final scrollable = find
        .descendant(
          of: find.byKey(const ValueKey('cards-note-overview')),
          matching: find.byType(Scrollable),
        )
        .first;
    expect(tester.state<ScrollableState>(scrollable).position.pixels, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('account usage shows MB from local notes while offline',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpNotesWithController(
      tester,
      _TestNotesController([
        _note('note-one', 'First note', 'A local encrypted preview.'),
      ]),
      apiClient: _FailingUsageApiClient(),
    );

    await tester.tap(find.byKey(const ValueKey('mobile-account-menu')));
    await tester.pumpAndSettle();
    expect(find.text('Calculated from local notes'), findsOneWidget);
    expect(find.text('0.01 MB of 500 MB'), findsOneWidget);
    expect(find.text('1 of 500 notes'), findsOneWidget);
  });

  testWidgets('iOS mobile chrome uses native glass and native symbols',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotesWithController(
      tester,
      _TestNotesController([
        _note('note-one', 'First note', 'A short first preview.'),
      ]),
      theme: buildAppTheme(Brightness.dark, platform: TargetPlatform.iOS),
    );

    expect(find.byKey(const ValueKey('ios-native-notes-header-glass')),
        findsNothing);
    expect(find.byKey(const ValueKey('notes-glass-header-backdrop')),
        findsNothing);
    expect(find.byKey(const ValueKey('ios-native-create-drawer-glass')),
        findsNothing);
    expect(find.byKey(const ValueKey('ios-native-bottom-navigation')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey('ios-native-nav-selection')), findsNothing);
    final nativeTabBar = tester.widget<CNTabBar>(
      find.byKey(const ValueKey('ios-native-tab-bar')),
    );
    expect(nativeTabBar.items, hasLength(4));
    expect(nativeTabBar.items.map((item) => item.icon?.name), [
      'note.text',
      'bell',
      'trash',
      'magnifyingglass',
    ]);
    expect(nativeTabBar.items.map((item) => item.icon?.size), everyElement(18));
    expect(nativeTabBar.items.map((item) => item.label), everyElement(isNull));
    expect(nativeTabBar.currentIndex, 0);
    expect(nativeTabBar.height, 64);
    expect(nativeTabBar.split, isFalse);
    final layoutButton = tester.widget<CNButton>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile-layout-toggle')),
        matching: find.byType(CNButton),
      ),
    );
    expect(layoutButton.icon?.name, 'square.grid.2x2');
    expect(layoutButton.icon?.size, AppSizes.iosCompactHeaderIcon);
    final accountButton = tester.widget<CNButton>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile-account-menu')),
        matching: find.byType(CNButton),
      ),
    );
    expect(accountButton.icon?.name, 'person');
    expect(accountButton.icon?.size, AppSizes.iosCompactHeaderIcon);

    final createButton = tester.widget<CNButton>(
      find.byKey(const ValueKey('ios-native-nav-create')),
    );
    expect(createButton.config.style, CNButtonStyle.prominentGlass);
    expect(createButton.config.glassEffectInteractive, isTrue);
    createButton.onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 420));
    final nativeActions =
        find.byKey(const ValueKey('ios-native-create-actions'));
    expect(nativeActions, findsOneWidget);
    expect(
      find.descendant(
        of: nativeActions,
        matching: find.byType(LiquidGlassContainer),
      ),
      findsNWidgets(3),
    );
    expect(
      find.descendant(of: nativeActions, matching: find.byType(CNButton)),
      findsNWidgets(3),
    );
    for (final button in tester.widgetList<CNButton>(
      find.descendant(of: nativeActions, matching: find.byType(CNButton)),
    )) {
      expect(button.config.imagePlacement, CNImagePlacement.top);
    }
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('mobile nav search expands, filters, and closes', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotes(tester);
    await tester.tap(find.byKey(const ValueKey('mobile-nav-search')));
    await tester.pumpAndSettle();

    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile-bottom-nav-pill')))
          .width,
      398,
    );
    final input = find.byKey(const ValueKey('mobile-nav-search-input'));
    expect(input, findsOneWidget);
    final searchField = tester.widget<TextField>(input);
    expect(searchField.decoration?.filled, isFalse);
    expect(searchField.decoration?.fillColor, Colors.transparent);
    await tester.enterText(input, 'First');
    await tester.pump();
    expect(find.text('First note'), findsOneWidget);
    expect(find.text('Second note'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mobile-nav-search-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      find.byKey(const ValueKey('mobile-nav-search-mode')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-nav-icons-mode')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('mobile-bottom-nav-pill')))
          .width,
      inExclusiveRange(296, 398),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-nav-search')), findsOneWidget);
    expect(find.text('Second note'), findsOneWidget);
  });

  testWidgets('mobile notes scroll behind the fixed glass header card',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 30);
    tester.view.viewPadding = const FakeViewPadding(top: 30);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPadding);
    addTearDown(tester.view.resetViewPadding);

    await _pumpNotesWithController(
      tester,
      _TestNotesController([
        for (var index = 0; index < 10; index += 1)
          _note('note-$index', 'Note $index', 'Preview $index'),
      ]),
    );

    final scaffold = tester.widget<Scaffold>(find.byType(Scaffold).first);
    expect(scaffold.bottomNavigationBar, isNull);
    expect(find.byKey(const ValueKey('notes-top-scroll-transition')),
        findsNothing);
    expect(find.byKey(const ValueKey('notes-progressive-blur-effect')),
        findsNothing);
    final glassCard = find.byKey(const ValueKey('notes-glass-header-card'));
    expect(glassCard, findsOneWidget);
    expect(find.byKey(const ValueKey('notes-glass-header-backdrop')),
        findsNothing);
    expect(
        find.byKey(const ValueKey('notes-header-scroll-fade')), findsOneWidget);
    expect(tester.getTopLeft(glassCard), Offset.zero);
    expect(tester.getSize(glassCard).width, 430);
    expect(
      find.byKey(const ValueKey('notes-glass-header-tint-light')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('notes-glass-header-highlight')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('notes-glass-header-light-haze')),
      findsNothing,
    );
    final lightCountBadge = tester.widget<Container>(
      find.byKey(const ValueKey('note-filter-count-badge')),
    );
    expect(
      (lightCountBadge.decoration! as BoxDecoration).color,
      const Color(0xffd9d4da),
    );

    final header = find.byKey(const ValueKey('notes-workspace-header-body'));
    expect(
      find.descendant(
        of: glassCard,
        matching: header,
      ),
      findsOneWidget,
    );

    final overview = find.byKey(const ValueKey('cards-note-overview'));
    final nav = find.byKey(const ValueKey('mobile-bottom-nav-pill'));
    expect(tester.getBottomLeft(overview).dy,
        greaterThan(tester.getTopLeft(nav).dy));

    final firstCard = find.byKey(const ValueKey('compact-note-drag-note-0'));
    expect(tester.getSize(firstCard).height, lessThan(168));
    expect(
      find.descendant(of: firstCard, matching: find.byType(BackdropFilter)),
      findsNothing,
    );
    expect(
      find.descendant(of: firstCard, matching: find.byType(RepaintBoundary)),
      findsWidgets,
    );
    final filters = find.byKey(const ValueKey('note-filter-chips'));
    final date = find.byKey(const ValueKey('notes-header-date'));
    expect(
      tester.getBottomLeft(glassCard).dy - tester.getBottomLeft(filters).dy,
      16,
    );
    expect(
      tester.getTopLeft(firstCard).dy,
      greaterThanOrEqualTo(tester.getBottomLeft(glassCard).dy),
    );
    await tester.drag(overview, const Offset(0, -100));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(firstCard).dy,
      lessThan(tester.getBottomLeft(glassCard).dy),
    );
    expect(
      tester.getTopLeft(firstCard).dy,
      lessThan(tester.getBottomLeft(date).dy),
    );
    expect(
      tester.getTopLeft(firstCard).dy,
      lessThan(tester.getBottomLeft(filters).dy),
    );
  });

  testWidgets('mobile header toggles layout and opens account sidebar',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotes(tester);

    Icon mobileLayoutIcon() => tester.widget<Icon>(
          find.descendant(
            of: find.byKey(const ValueKey('mobile-layout-toggle')),
            matching: find.byType(Icon),
          ),
        );

    expect(mobileLayoutIcon().icon, AppIcons.grid2X2);
    await tester.tap(find.byKey(const ValueKey('mobile-layout-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mobile-note-list')), findsOneWidget);
    expect(mobileLayoutIcon().icon, AppIcons.grid2X2);

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
    expect(
      find.byKey(const ValueKey('mobile-sidebar-quota-card')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-sidebar-navigation')),
      findsOneWidget,
    );
    final inactiveReminder = find.byKey(
      const ValueKey('mobile-sidebar-bucket-reminders'),
    );
    final inactiveSurface = tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: inactiveReminder,
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    expect(
      (inactiveSurface.decoration! as BoxDecoration).color,
      Colors.transparent,
    );
    final settingsAction = find.byKey(
      const ValueKey('account-settings-action'),
    );
    final settingsSurface = tester.widget<AnimatedContainer>(
      find
          .descendant(
            of: settingsAction,
            matching: find.byType(AnimatedContainer),
          )
          .first,
    );
    final sideSheetScheme =
        Theme.of(tester.element(settingsAction)).colorScheme;
    expect(
      (settingsSurface.decoration! as BoxDecoration).color,
      sideSheetScheme.surfaceContainerHighest.withValues(alpha: 0.4),
    );
    expect(find.text('12 MB of 500 MB'), findsOneWidget);
    expect(find.text('42 of 500 notes'), findsOneWidget);
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
    final cardMaterial = tester
        .widgetList<Material>(
          find.descendant(of: card, matching: find.byType(Material)),
        )
        .singleWhere((material) => material.shape is RoundedSuperellipseBorder);
    expect(
      (cardMaterial.shape! as RoundedSuperellipseBorder).borderRadius,
      BorderRadius.circular(AppRadii.noteCard),
    );
    final desktopCardContent = tester.widget<Padding>(
      find.byKey(const ValueKey('note-card-content-note-one')),
    );
    expect(
      desktopCardContent.padding,
      const EdgeInsets.fromLTRB(20, 18, 20, 20),
    );
    expect(
      find.byKey(const ValueKey('desktop-note-backdrop-note-one')),
      findsOneWidget,
    );
  });

  testWidgets('desktop chrome keeps the rail open and search shadow inset',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotes(tester);

    final appBar = tester.widget<AppBar>(find.byType(AppBar));
    expect(appBar.toolbarHeight, 96);
    expect(appBar.actionsPadding, const EdgeInsets.only(bottom: 16));
    expect(find.byTooltip('Menu'), findsNothing);
    expect(find.text('New note'), findsOneWidget);
    expect(find.text('Notes'), findsWidgets);

    final createButton = find.text('New note');
    final rail = find.ancestor(
      of: createButton,
      matching: find.byWidgetPredicate(
        (widget) => widget is SizedBox && widget.width == 216,
      ),
    );
    expect(rail, findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('desktop-account-menu')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('mobile-account-side-sheet')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('mobile-sidebar-navigation')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('account-settings-action')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('account-logout-action')),
      findsOneWidget,
    );
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
    final editorFrame = tester.widget<ClipPath>(
      find.byKey(const ValueKey('desktop-note-editor-frame')),
    );
    final frameClipper = editorFrame.clipper! as ShapeBorderClipper;
    final frameShape = frameClipper.shape as RoundedSuperellipseBorder;
    expect(
      frameShape.borderRadius,
      const BorderRadius.only(topLeft: Radius.circular(AppRadii.xxl)),
    );
    expect(
      find.byKey(const ValueKey('desktop-inline-note-filters')),
      findsOneWidget,
    );
    final allNotesFilter = find.byKey(const ValueKey('note-filter-all'));
    expect(tester.getSize(allNotesFilter).height, lessThan(42));
    final workspaceHeader = find.byKey(
      const ValueKey('notes-workspace-header'),
    );
    expect(
      find.descendant(of: workspaceHeader, matching: find.text('2')),
      findsOneWidget,
    );
    final split = find.byKey(const ValueKey('desktop-split-layout'));
    final editorTitle = find.byKey(const ValueKey('note-editor-title'));
    expect(
      tester.getTopLeft(editorTitle).dy - tester.getTopLeft(split).dy,
      lessThan(40),
    );
    expect(tester.getTopLeft(split).dy, lessThan(240));
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

  testWidgets('pinned notes use the filled heart in desktop list view',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'zk.pref.note_overview_layout': 'list',
    });
    tester.view.physicalSize = const Size(1200, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpNotesWithController(
      tester,
      _TestNotesController([
        _note('favorite', 'Favorite note', 'Saved').copyWith(pinned: true),
      ]),
    );

    final row = find.byKey(const ValueKey('note-list-item-favorite'));
    final heart = find.descendant(
      of: row,
      matching: find.byIcon(AppIcons.heartFill),
    );
    expect(heart, findsOneWidget);
    expect(
      find.descendant(of: row, matching: find.byIcon(AppIcons.pin)),
      findsNothing,
    );
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
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(second) + const Offset(0, 18));
    await tester.pump();
    await gesture.moveBy(const Offset(0, 1));
    await tester.pump(const Duration(milliseconds: 220));
    await gesture.up();
    await tester.pump();

    expect(controller.reorderedNoteId, 'note-one');
    expect(controller.reorderedTargetIndex, greaterThan(0));
  });

  testWidgets('stationary long press selects notes and bulk delete applies all',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = _TestNotesController([
      _note('note-one', 'First note', 'A short first preview.'),
      _note('note-two', 'Second note', 'A short second preview.'),
    ]);
    await _pumpNotesWithController(tester, controller);

    final first = find.byKey(const ValueKey('compact-note-drag-note-one'));
    final gesture = await tester.startGesture(tester.getCenter(first));
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 100));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(controller.reorderedNoteId, isNull);
    expect(
        find.byKey(const ValueKey('multi-selection-toolbar')), findsOneWidget);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byKey(const ValueKey('mobile-nav-trash-drop-target')),
        findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('compact-note-drag-note-two')),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('delete-selected-notes')),
    );
    await tester.pumpAndSettle();
    expect(controller.changedNoteIds, ['note-one', 'note-two']);
    expect(find.byKey(const ValueKey('multi-selection-toolbar')), findsNothing);
    expect(
        find.byKey(const ValueKey('mobile-bottom-nav-pill')), findsOneWidget);
  });

  testWidgets('desktop hover controls select without changing card height',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpNotes(tester);

    final first = find.byKey(const ValueKey('compact-note-drag-note-one'));
    final firstControl =
        find.byKey(const ValueKey('note-selection-control-note-one'));
    final heightBefore = tester.getSize(first).height;
    expect(tester.widget<AnimatedOpacity>(firstControl).opacity, 0);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(1, 1));
    await mouse.moveTo(tester.getCenter(first));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(firstControl).opacity, 1);
    expect(tester.getSize(first).height, heightBefore);

    await tester.tap(firstControl);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    final secondControl =
        find.byKey(const ValueKey('note-selection-control-note-two'));
    expect(tester.widget<AnimatedOpacity>(secondControl).opacity, 1);

    await tester.tap(
      find.byKey(const ValueKey('compact-note-drag-note-two')),
    );
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(tester.getSize(first).height, heightBefore);
    await mouse.removePointer();
  });

  testWidgets('mobile note cards omit the normal synced status',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await _pumpNotesWithController(
      tester,
      _TestNotesController([
        _note('dirty-note', 'Dirty note', 'Pending content')
            .copyWith(dirty: true),
      ]),
    );

    expect(find.text('synced'), findsNothing);
  });

  testWidgets('moving after a long press exposes the trash drop target',
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
    await gesture.moveBy(const Offset(12, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final trash = find.byKey(const ValueKey('mobile-nav-trash-drop-target'));
    expect(trash, findsOneWidget);
    final trashIconScale = tester.widget<Transform>(
      find.byKey(const ValueKey('mobile-nav-trash-icon-scale')),
    );
    expect(trashIconScale.transform.getMaxScaleOnAxis(), greaterThan(1));
    expect(trashIconScale.transform.getMaxScaleOnAxis(), lessThan(1.65));
    final openingViewportHeight = tester
        .getSize(
          find.byKey(const ValueKey('mobile-nav-morphing-viewport')),
        )
        .height;
    expect(openingViewportHeight, greaterThan(50));
    expect(openingViewportHeight, lessThan(76));
    final openingSurface = tester.widget<Positioned>(
      find.byKey(const ValueKey('mobile-nav-drawer-surface-position')),
    );
    expect(openingSurface.height, greaterThan(62));
    expect(openingSurface.height, lessThan(88));
    final selectionMorph = tester.widget<Transform>(
      find.byKey(const ValueKey('mobile-nav-selection-morph')),
    );
    expect(selectionMorph.transform.getTranslation().x, greaterThan(80));
    final selectionScale = tester.widget<Transform>(
      find.descendant(
        of: find.byKey(const ValueKey('mobile-nav-selection-morph')),
        matching: find.byType(Transform),
      ),
    );
    expect(selectionScale.transform.entry(0, 0) * 50, lessThan(30));

    final lift = tester.widget<Transform>(
      find.byKey(const ValueKey('mobile-nav-trash-lift')),
    );
    expect(lift.transform.getTranslation().y, greaterThan(-12));
    expect(lift.transform.getTranslation().y, lessThan(0));

    final trashIcon = tester.widget<Icon>(
      find.byKey(const ValueKey('mobile-nav-trash-icon-color')),
    );
    expect(trashIcon.color!.a, greaterThan(0.72));
    expect(trashIcon.color!.a, lessThan(1));

    final notesSlot = find.byKey(
      const ValueKey('mobile-nav-notes-morph-slot'),
    );
    final notesOpacity = tester.widget<Opacity>(
      find.descendant(of: notesSlot, matching: find.byType(Opacity)).first,
    );
    expect(notesOpacity.opacity, lessThan(0.2));
    final notesScale = tester.widget<Transform>(
      find.byKey(const ValueKey('mobile-nav-notes-morph-scale')),
    );
    final createScale = tester.widget<Transform>(
      find.byKey(const ValueKey('mobile-nav-create-morph-scale')),
    );
    final searchScale = tester.widget<Transform>(
      find.byKey(const ValueKey('mobile-nav-search-morph-scale')),
    );
    expect(notesScale.transform.entry(0, 0), lessThan(0.65));
    expect(createScale.transform.entry(0, 0), lessThan(0.65));
    expect(searchScale.transform.entry(0, 0), greaterThan(0.8));

    await tester.pump(const Duration(milliseconds: 220));
    final liftedTrash = tester.widget<Transform>(
      find.byKey(const ValueKey('mobile-nav-trash-lift')),
    );
    expect(liftedTrash.transform.getTranslation().y, closeTo(-12, 0.01));

    await gesture.moveTo(tester.getCenter(trash));
    await tester.pump(const Duration(milliseconds: 220));
    final feedbackOpacity = tester.widget<AnimatedOpacity>(
      find.byKey(const ValueKey('note-drag-trash-opacity-note-one')),
    );
    expect(feedbackOpacity.opacity, 0.24);
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    final reversingTrashIconScale = tester.widget<Transform>(
      find.byKey(const ValueKey('mobile-nav-trash-icon-scale')),
    );
    expect(
      reversingTrashIconScale.transform.getMaxScaleOnAxis(),
      greaterThan(1),
    );
    expect(
      reversingTrashIconScale.transform.getMaxScaleOnAxis(),
      lessThan(1.65),
    );
    final closingViewportHeight = tester
        .getSize(
          find.byKey(const ValueKey('mobile-nav-morphing-viewport')),
        )
        .height;
    expect(closingViewportHeight, greaterThan(50));
    expect(closingViewportHeight, lessThan(76));
    final closingSurface = tester.widget<Positioned>(
      find.byKey(const ValueKey('mobile-nav-drawer-surface-position')),
    );
    expect(closingSurface.height, greaterThan(62));
    expect(closingSurface.height, lessThan(88));
    await tester.pumpAndSettle();

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
  AuthController Function()? authControllerBuilder,
  ApiClient? apiClient,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiClientProvider.overrideWithValue(apiClient ?? _TestApiClient()),
        authControllerProvider.overrideWith(
          authControllerBuilder ?? _TestAuthController.new,
        ),
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

class _TestApiClient extends ApiClient {
  @override
  Future<SubscriptionUsage> fetchSubscriptionUsage({
    required String accessToken,
    required String tenant,
  }) async {
    return const SubscriptionUsage(
      plan: 'free',
      storageBytesUsed: 12582912,
      storageBytesLimit: 524288000,
      notesCount: 42,
      maxNotes: 500,
    );
  }
}

class _FailingUsageApiClient extends ApiClient {
  @override
  Future<SubscriptionUsage> fetchSubscriptionUsage({
    required String accessToken,
    required String tenant,
  }) {
    throw ApiException('offline', 0);
  }
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

class _UnverifiedTestAuthController extends AuthController {
  @override
  Future<AppSession?> build() async {
    return const AppSession(
      email: 'local@example.test',
      accessToken: 'local-access',
      refreshToken: 'local-refresh',
      defaultTenant: 'local-tenant',
      masterKey: [0, 1, 2, 3],
      emailVerified: false,
    );
  }

  @override
  Future<bool> refreshEmailVerificationStatus() async => false;
}

class _TestNotesController extends NotesController {
  _TestNotesController(this.notes);

  final List<PlainNote> notes;
  String? reorderedNoteId;
  int? reorderedTargetIndex;
  String? changedNoteId;
  String? changedState;
  final changedNoteIds = <String>[];
  int emptyTrashCalls = 0;

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
    changedNoteIds.add(note.localId);
  }

  @override
  Future<int> emptyTrash() async {
    emptyTrashCalls += 1;
    final current = state.requireValue;
    final count = current.where((note) => note.state == 'trashed').length;
    state = AsyncData([
      for (final note in current)
        if (note.state == 'trashed')
          note.copyWith(state: 'deleted', dirty: false)
        else
          note,
    ]);
    return count;
  }
}

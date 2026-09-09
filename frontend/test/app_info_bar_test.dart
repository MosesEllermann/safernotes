import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safernotes_app/shared/widgets/app_info_bar.dart';

void main() {
  testWidgets('actionable info bars execute and dismiss', (tester) async {
    tester.view.physicalSize = const Size(430, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var actions = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showAppInfoBar(
                context,
                message: 'Saved',
                actionLabel: 'Undo',
                onAction: () => actions++,
                avoidMobileNavigation: true,
              ),
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pumpAndSettle();
    final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
    expect(snackBar.persist, isFalse);
    expect(snackBar.duration, appInfoBarDuration);
    expect(snackBar.margin, const EdgeInsets.fromLTRB(16, 0, 16, 96));

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(actions, 1);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('actionable info bars expire and replace queued feedback',
      (tester) async {
    late BuildContext appContext;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              appContext = context;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    );

    showAppInfoBar(
      appContext,
      message: 'First',
      actionLabel: 'Action',
      onAction: () {},
    );
    showAppInfoBar(appContext, message: 'Second');
    await tester.pump();
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(appInfoBarDuration + const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}

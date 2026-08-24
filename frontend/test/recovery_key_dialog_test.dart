import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safernotes_app/features/auth/recovery_key_dialog.dart';
import 'package:safernotes_app/shared/app/app_l10n.dart';

void main() {
  testWidgets('recovery-key onboarding requires explicit saved confirmation',
      (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                result = await showRecoveryKeyConfirmationDialog(
                  context: context,
                  l10n: const AppL10n('en'),
                  recoveryKey: 'local-recovery-key',
                  rotating: false,
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('local-recovery-key'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Continue'),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.text('I saved this recovery key in a secure place.'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Continue'),
          )
          .onPressed,
      isNotNull,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Continue'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });
}

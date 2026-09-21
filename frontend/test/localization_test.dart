import 'package:flutter_test/flutter_test.dart';
import 'package:safernotes_app/shared/app/app_l10n.dart';

void main() {
  test('shared UI translations exist in English and German', () {
    const keys = [
      'newNote',
      'newChecklist',
      'setReminder',
      'collaboratorInvite',
      'searchNotes',
      'background',
      'save',
      'profile',
      'personalVault',
      'noteMovedToTrash',
      'noteArchived',
      'noteRestored',
      'noteDeletedPermanently',
      'syncServer',
    ];
    const english = AppL10n('en');
    const german = AppL10n('de');

    for (final key in keys) {
      expect(english.t(key), isNot(key));
      expect(german.t(key), isNot(key));
    }

    expect(
      german.t('emailConfirmDescription', params: {'email': 'a@example.com'}),
      contains('a@example.com'),
    );
  });
}

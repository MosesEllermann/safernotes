import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_test/flutter_test.dart';
import 'package:safernotes_app/features/notes/rich_text_document.dart';

void main() {
  test('loads persisted Delta without exposing formatting markers', () {
    final document = noteDocument(
      delta: [
        {
          'insert': 'Gute Kaese',
          'attributes': {'italic': true},
        },
        {'insert': '\n'},
      ],
      legacyText: 'ignored',
    );

    expect(documentPlainText(document), 'Gute Kaese');
    expect(
      document.toDelta().toJson().first['attributes'],
      {'italic': true},
    );
  });

  test('migrates malformed legacy markers from the old Android editor', () {
    final document = noteDocument(
      delta: null,
      legacyText: '_ Gute Kaese _ and **bold**',
    );
    final operations = document.toDelta().toJson();

    expect(documentPlainText(document), 'Gute Kaese and bold');
    expect(operations[0]['insert'], 'Gute Kaese');
    expect(operations[0]['attributes'], {'italic': true});
    expect(operations[2]['insert'], 'bold');
    expect(operations[2]['attributes'], {'bold': true});
  });

  test('falls back to legacy text when stored Delta is invalid', () {
    final document = noteDocument(
      delta: const [
        {'delete': 4},
      ],
      legacyText: 'safe text',
    );

    expect(documentPlainText(document), 'safe text');
    expect(document, isA<quill.Document>());
  });
}

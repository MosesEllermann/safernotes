import 'package:flutter_test/flutter_test.dart';
import 'package:safernotes_app/shared/models/note.dart';

void main() {
  test('rich text Delta survives offline and encrypted payload serialization',
      () {
    final note = PlainNote(
      localId: 'note',
      title: 'Title',
      body: 'formatted',
      richTextDelta: const [
        {
          'insert': 'formatted',
          'attributes': {'bold': true},
        },
        {'insert': '\n'},
      ],
      checklist: const [],
      updatedAt: DateTime.utc(2026, 8, 24),
      pinned: false,
      color: 0xffffffff,
      sortOrder: 0,
      dirty: true,
      version: 1,
      shared: true,
      noteKey: 'encrypted-local-note-key',
      shareRole: 'viewer',
    );

    final offline = PlainNote.fromPlainJson(note.toPlainJson());
    final remote = PlainNote.fromEncryptedPayload(
      localId: note.localId,
      remoteId: 'remote',
      updatedAt: note.updatedAt,
      version: 2,
      json: note.encryptedPayloadJson(),
    );

    expect(offline.richTextDelta, note.richTextDelta);
    expect(offline.noteKey, note.noteKey);
    expect(offline.shareRole, note.shareRole);
    expect(remote.richTextDelta, note.richTextDelta);
    // Schema 4 adds encrypted labels.
    expect(note.encryptedPayloadJson()['schema'], 4);
  });
}

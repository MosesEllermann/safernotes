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
    expect(remote.richTextDelta, note.richTextDelta);
    expect(note.encryptedPayloadJson()['schema'], 3);
  });
}

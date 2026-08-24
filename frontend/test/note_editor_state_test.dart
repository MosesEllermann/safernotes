import 'package:flutter_test/flutter_test.dart';
import 'package:safernotes_app/features/notes/note_editor_state.dart';
import 'package:safernotes_app/shared/models/note.dart';

void main() {
  group('checklist ordering', () {
    test('keeps unchecked items above checked items without reshuffling groups',
        () {
      final result = orderChecklistItems([
        _item('done-1', done: true),
        _item('open-1'),
        _item('done-2', done: true),
        _item('open-2'),
      ]);

      expect(result.map((item) => item.id), [
        'open-1',
        'open-2',
        'done-1',
        'done-2',
      ]);
    });

    test('checking moves to the bottom and unchecking returns above checked',
        () {
      final initial = [
        _item('open-1'),
        _item('open-2'),
        _item('done-1', done: true),
      ];
      final checked = updateChecklistItem(
        initial,
        initial.first.copyWith(done: true),
      );
      expect(checked.map((item) => item.id), [
        'open-2',
        'done-1',
        'open-1',
      ]);

      final unchecked = updateChecklistItem(
        checked,
        checked.last.copyWith(done: false),
      );
      expect(unchecked.map((item) => item.id), [
        'open-2',
        'open-1',
        'done-1',
      ]);
    });

    test('new items are inserted at the end of the unchecked section', () {
      final result = insertUncheckedItem(
        [_item('open'), _item('done', done: true)],
        _item('new'),
      );

      expect(result.map((item) => item.id), ['open', 'new', 'done']);
    });

    test('drag reorders items inside the same checklist section', () {
      final items = [
        _item('a'),
        _item('b'),
        _item('done', done: true),
      ];

      final reordered = moveChecklistItemBefore(
        items,
        movingId: 'b',
        targetId: 'a',
      );

      expect(reordered.map((item) => item.id), ['b', 'a', 'done']);
    });

    test('drag keeps open and completed checklist sections separate', () {
      final items = [_item('open'), _item('done', done: true)];

      final reordered = moveChecklistItemBefore(
        items,
        movingId: 'done',
        targetId: 'open',
      );

      expect(reordered.map((item) => item.id), ['open', 'done']);
    });
  });

  test('editor history is bounded and clears redo after a new edit', () {
    final history = EditorHistory<int>(
      initialValue: 0,
      sameContent: (left, right) => left == right,
      limit: 2,
    );

    history
      ..record(1)
      ..record(2)
      ..record(3);
    expect(history.undo(), 2);
    expect(history.undo(), 1);
    expect(history.undo(), isNull);
    expect(history.redo(), 2);
    history.record(4);
    expect(history.canRedo, isFalse);
  });
}

ChecklistItem _item(String id, {bool done = false}) {
  return ChecklistItem(id: id, text: id, done: done, indent: 0);
}

import 'package:flutter/services.dart';
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

  group('markdown formatting', () {
    test('toggles existing persisted markdown without losing selection', () {
      const original = TextEditingValue(
        text: 'A **bold** note',
        selection: TextSelection(baseOffset: 4, extentOffset: 8),
      );

      expect(
        MarkdownFormatting.isActive(original, MarkdownFormat.bold),
        isTrue,
      );
      final result = MarkdownFormatting.toggle(original, MarkdownFormat.bold);
      expect(result.text, 'A bold note');
      expect(
          result.selection,
          const TextSelection(
            baseOffset: 2,
            extentOffset: 6,
          ));
    });

    test('rapid sequential formatting composes deterministically', () {
      const original = TextEditingValue(
        text: 'alpha',
        selection: TextSelection(baseOffset: 0, extentOffset: 5),
      );

      final bold = MarkdownFormatting.toggle(original, MarkdownFormat.bold);
      final italic = MarkdownFormatting.toggle(bold, MarkdownFormat.italic);
      expect(italic.text, '**_alpha_**');
      expect(italic.selection.textInside(italic.text), 'alpha');
      expect(
        MarkdownFormatting.isActive(italic, MarkdownFormat.bold),
        isTrue,
      );
      expect(
        MarkdownFormatting.isActive(italic, MarkdownFormat.italic),
        isTrue,
      );
    });

    test('collapsed selection formats the current word and keeps its text', () {
      const original = TextEditingValue(
        text: 'one two',
        selection: TextSelection.collapsed(offset: 5),
      );

      final result = MarkdownFormatting.toggle(original, MarkdownFormat.strike);
      expect(result.text, 'one ~~two~~');
      expect(result.selection.textInside(result.text), 'two');
    });
  });
}

ChecklistItem _item(String id, {bool done = false}) {
  return ChecklistItem(id: id, text: id, done: done, indent: 0);
}

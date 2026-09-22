import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:safernotes_app/features/notes/checklist_input_formatter.dart';

void main() {
  test('IME backspace distinguishes an empty row from the last character', () {
    var deletions = 0;
    final formatter =
        ChecklistInputFormatter(onEmptyBackspace: () => deletions++);
    final empty = formatter.formatEditUpdate(
      ChecklistInputFormatter.initialValue('x'),
      TextEditingValue.empty,
    );
    expect(deletions, 0);
    expect(ChecklistInputFormatter.itemText(empty.text), '');
    formatter.formatEditUpdate(empty, TextEditingValue.empty);
    expect(deletions, 1);
  });

  test('typing and composing in an empty row never stores the IME marker', () {
    final formatter = ChecklistInputFormatter(
        onEmptyBackspace: () => fail('unexpected deletion'));
    final value = formatter.formatEditUpdate(
      ChecklistInputFormatter.initialValue(''),
      const TextEditingValue(
        text: '${ChecklistInputFormatter.emptyMarker}Hallo',
        selection: TextSelection.collapsed(offset: 6),
        composing: TextRange(start: 1, end: 6),
      ),
    );
    expect(value.text, 'Hallo');
    expect(value.selection.extentOffset, 5);
    expect(value.composing, const TextRange(start: 0, end: 5));
    expect(ChecklistInputFormatter.itemText(value.text), 'Hallo');
  });
}

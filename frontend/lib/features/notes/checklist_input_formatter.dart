import 'package:flutter/services.dart';

/// Gives an empty row a deletable character for Android IMEs, which may not
/// send a key event when backspace is pressed in an empty editing buffer.
/// The marker belongs only to the editing buffer, never to the saved item.
class ChecklistInputFormatter extends TextInputFormatter {
  ChecklistInputFormatter({required this.onEmptyBackspace});

  static const emptyMarker = '\u200b';
  final VoidCallback onEmptyBackspace;

  static String itemText(String text) =>
      text.startsWith(emptyMarker) ? text.substring(1) : text;

  static TextEditingValue initialValue(String text) => TextEditingValue(
        text: text.isEmpty ? emptyMarker : text,
        selection:
            TextSelection.collapsed(offset: text.isEmpty ? 1 : text.length),
      );

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (oldValue.text == emptyMarker && newValue.text.isEmpty) {
      onEmptyBackspace();
      return initialValue('');
    }
    if (newValue.text.isEmpty || newValue.text == emptyMarker) {
      return initialValue('');
    }
    if (!newValue.text.startsWith(emptyMarker)) return newValue;

    final text = itemText(newValue.text);
    int offset(int value) => (value - 1).clamp(0, text.length);
    return TextEditingValue(
      text: text,
      selection: newValue.selection.isValid
          ? newValue.selection.copyWith(
              baseOffset: offset(newValue.selection.baseOffset),
              extentOffset: offset(newValue.selection.extentOffset),
            )
          : TextSelection.collapsed(offset: text.length),
      composing: newValue.composing.isValid
          ? TextRange(
              start: offset(newValue.composing.start),
              end: offset(newValue.composing.end),
            )
          : TextRange.empty,
    );
  }
}

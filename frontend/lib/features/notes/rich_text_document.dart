import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter_quill/quill_delta.dart' as quill_delta;

quill.Document noteDocument({
  required List<Map<String, dynamic>>? delta,
  required String legacyText,
}) {
  if (delta != null && delta.isNotEmpty) {
    try {
      return quill.Document.fromJson(delta);
    } catch (_) {
      // Fall through once for notes written by older editor versions.
    }
  }
  return _legacyMarkdownDocument(legacyText);
}

String documentPlainText(quill.Document document) {
  return document.toPlainText().replaceFirst(RegExp(r'\n$'), '');
}

quill.Document _legacyMarkdownDocument(String source) {
  final delta = quill_delta.Delta();
  final normalized = source.replaceAll('\r\n', '\n');
  final lines = normalized.split('\n');
  for (var index = 0; index < lines.length; index += 1) {
    _appendInlineMarkdown(delta, lines[index]);
    delta.insert('\n');
  }
  if (lines.isEmpty) delta.insert('\n');
  return quill.Document.fromDelta(delta);
}

final _inlineMarkdown = RegExp(
  r'\[([^\]]+)\]\(([^)]+)\)|\*\*(.+?)\*\*|__(.+?)__|~~(.+?)~~|`(.+?)`|_([^_\n]+)_|\*([^*\n]+)\*',
);

void _appendInlineMarkdown(quill_delta.Delta delta, String line) {
  var offset = 0;
  for (final match in _inlineMarkdown.allMatches(line)) {
    if (match.start > offset) delta.insert(line.substring(offset, match.start));

    final attributes = <String, dynamic>{};
    String content;
    if (match.group(1) != null) {
      content = match.group(1)!;
      attributes[quill.Attribute.link.key] = match.group(2)!;
    } else if (match.group(3) != null || match.group(4) != null) {
      content = (match.group(3) ?? match.group(4)!).trim();
      attributes[quill.Attribute.bold.key] = true;
    } else if (match.group(5) != null) {
      content = match.group(5)!.trim();
      attributes[quill.Attribute.strikeThrough.key] = true;
    } else if (match.group(6) != null) {
      content = match.group(6)!;
      attributes[quill.Attribute.inlineCode.key] = true;
    } else {
      content = (match.group(7) ?? match.group(8)!).trim();
      attributes[quill.Attribute.italic.key] = true;
    }
    delta.insert(content, attributes);
    offset = match.end;
  }
  if (offset < line.length) delta.insert(line.substring(offset));
}

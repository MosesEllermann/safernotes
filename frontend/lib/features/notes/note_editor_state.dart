import 'package:flutter/services.dart';
import 'package:safernotes_app/shared/models/note.dart';

enum MarkdownFormat { bold, italic, strike }

class EditorHistory<T> {
  EditorHistory({
    required T initialValue,
    required this.sameContent,
    this.limit = 80,
  })  : assert(limit > 0),
        _current = initialValue;

  final bool Function(T previous, T next) sameContent;
  final int limit;
  final List<T> _undo = [];
  final List<T> _redo = [];
  T _current;

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;
  T get current => _current;

  bool record(T next) {
    if (sameContent(_current, next)) {
      _current = next;
      return false;
    }
    _undo.add(_current);
    if (_undo.length > limit) _undo.removeAt(0);
    _current = next;
    _redo.clear();
    return true;
  }

  T? undo() {
    if (!canUndo) return null;
    _redo.add(_current);
    _current = _undo.removeLast();
    return _current;
  }

  T? redo() {
    if (!canRedo) return null;
    _undo.add(_current);
    _current = _redo.removeLast();
    return _current;
  }

  void reset(T value) {
    _current = value;
    _undo.clear();
    _redo.clear();
  }
}

List<ChecklistItem> orderChecklistItems(Iterable<ChecklistItem> items) {
  final unchecked = <ChecklistItem>[];
  final checked = <ChecklistItem>[];
  for (final item in items) {
    (item.done ? checked : unchecked).add(item);
  }
  return [...unchecked, ...checked];
}

List<ChecklistItem> updateChecklistItem(
  List<ChecklistItem> items,
  ChecklistItem updated,
) {
  final ordered = orderChecklistItems(items);
  final previousIndex = ordered.indexWhere((item) => item.id == updated.id);
  if (previousIndex < 0) return ordered;
  final previous = ordered[previousIndex];
  if (previous.done == updated.done) {
    ordered[previousIndex] = updated;
    return ordered;
  }

  ordered.removeAt(previousIndex);
  final firstChecked = ordered.indexWhere((item) => item.done);
  if (updated.done) {
    ordered.add(updated);
  } else {
    ordered.insert(firstChecked < 0 ? ordered.length : firstChecked, updated);
  }
  return ordered;
}

List<ChecklistItem> insertUncheckedItem(
  List<ChecklistItem> items,
  ChecklistItem inserted, {
  String? afterItemId,
}) {
  final ordered = orderChecklistItems(items);
  final firstChecked = ordered.indexWhere((item) => item.done);
  final uncheckedEnd = firstChecked < 0 ? ordered.length : firstChecked;
  final afterIndex = afterItemId == null
      ? -1
      : ordered.indexWhere(
          (item) => item.id == afterItemId && !item.done,
        );
  final insertionIndex = afterIndex < 0 ? uncheckedEnd : afterIndex + 1;
  ordered.insert(insertionIndex, inserted.copyWith(done: false));
  return ordered;
}

List<ChecklistItem> reorderChecklistSection(
  List<ChecklistItem> items, {
  required bool done,
  required int oldIndex,
  required int newIndex,
}) {
  final ordered = orderChecklistItems(items);
  final section = ordered.where((item) => item.done == done).toList();
  if (oldIndex < 0 || oldIndex >= section.length) return ordered;
  final item = section.removeAt(oldIndex);
  section.insert(newIndex.clamp(0, section.length), item);
  final other = ordered.where((item) => item.done != done).toList();
  return done ? [...other, ...section] : [...section, ...other];
}

class MarkdownFormatting {
  static const _markers = {
    MarkdownFormat.bold: '**',
    MarkdownFormat.italic: '_',
    MarkdownFormat.strike: '~~',
  };

  static TextEditingValue toggle(
    TextEditingValue value,
    MarkdownFormat format,
  ) {
    final marker = _markers[format]!;
    final text = value.text;
    var range = _safeRange(value.selection, text);
    final selected = range.textInside(text);

    if (selected.length >= marker.length * 2 &&
        selected.startsWith(marker) &&
        selected.endsWith(marker)) {
      final replacement =
          selected.substring(marker.length, selected.length - marker.length);
      return _replace(
        value,
        range,
        replacement,
        TextSelection(
          baseOffset: range.start,
          extentOffset: range.start + replacement.length,
        ),
      );
    }

    final enclosing = _enclosingMarker(text, range, marker);
    if (enclosing != null) {
      final replacement = text.substring(
        enclosing.contentStart,
        enclosing.contentEnd,
      );
      final mappedStart = _mapOffsetWithoutMarkers(
        range.start,
        enclosing,
        marker.length,
      );
      final mappedEnd = _mapOffsetWithoutMarkers(
        range.end,
        enclosing,
        marker.length,
      );
      return _replace(
        value,
        TextRange(start: enclosing.start, end: enclosing.end),
        replacement,
        TextSelection(baseOffset: mappedStart, extentOffset: mappedEnd),
      );
    }

    if (range.isCollapsed) {
      range = _wordRangeAt(text, range.start) ?? range;
    }
    final inner = range.textInside(text);
    final replacement = '$marker$inner$marker';
    final selection = inner.isEmpty
        ? TextSelection.collapsed(offset: range.start + marker.length)
        : TextSelection(
            baseOffset: range.start + marker.length,
            extentOffset: range.start + marker.length + inner.length,
          );
    return _replace(value, range, replacement, selection);
  }

  static bool isActive(TextEditingValue value, MarkdownFormat format) {
    final marker = _markers[format]!;
    final range = _safeRange(value.selection, value.text);
    final selected = range.textInside(value.text);
    if (selected.length >= marker.length * 2 &&
        selected.startsWith(marker) &&
        selected.endsWith(marker)) {
      return true;
    }
    return _enclosingMarker(value.text, range, marker) != null;
  }

  static TextEditingValue codeBlock(TextEditingValue value) {
    final range = _safeRange(value.selection, value.text);
    final selected = range.textInside(value.text);
    final replacement =
        selected.trim().isEmpty ? '```\n\n```' : '```\n$selected\n```';
    final selection = selected.trim().isEmpty
        ? TextSelection.collapsed(offset: range.start + 4)
        : TextSelection(
            baseOffset: range.start + 4,
            extentOffset: range.start + 4 + selected.length,
          );
    return _replace(value, range, replacement, selection);
  }

  static TextEditingValue clear(TextEditingValue value) {
    var range = _safeRange(value.selection, value.text);
    if (range.isCollapsed) {
      range = _lineRangeAt(value.text, range.start);
    }
    if (range.isCollapsed) return value;
    final replacement = _clearMarkdownSyntax(range.textInside(value.text));
    return _replace(
      value,
      range,
      replacement,
      TextSelection(
        baseOffset: range.start,
        extentOffset: range.start + replacement.length,
      ),
    );
  }

  static bool isLinkActive(TextEditingValue value) {
    final range = _safeRange(value.selection, value.text);
    final expression = RegExp(r'\[([^\]]*)\]\(([^)]*)\)');
    return expression.allMatches(value.text).any((match) {
      if (range.isCollapsed) {
        return range.start >= match.start && range.start <= match.end;
      }
      return range.start < match.end && range.end > match.start;
    });
  }

  static TextRange safeRange(TextSelection selection, String text) {
    return _safeRange(selection, text);
  }

  static TextRange? wordRangeAt(String text, int offset) {
    return _wordRangeAt(text, offset);
  }

  static TextRange lineRangeAt(String text, int offset) {
    return _lineRangeAt(text, offset);
  }

  static TextEditingValue _replace(
    TextEditingValue value,
    TextRange range,
    String replacement,
    TextSelection selection,
  ) {
    return value.copyWith(
      text: value.text.replaceRange(range.start, range.end, replacement),
      selection: selection,
      composing: TextRange.empty,
    );
  }

  static TextRange _safeRange(TextSelection selection, String text) {
    final rawStart = selection.start < 0 ? text.length : selection.start;
    final rawEnd = selection.end < 0 ? text.length : selection.end;
    final start = rawStart.clamp(0, text.length);
    final end = rawEnd.clamp(start, text.length);
    return TextRange(start: start, end: end);
  }

  static TextRange? _wordRangeAt(String text, int offset) {
    if (text.isEmpty) return null;
    var start = offset.clamp(0, text.length);
    var end = start;
    while (start > 0 && _isWordCharacter(text.codeUnitAt(start - 1))) {
      start -= 1;
    }
    while (end < text.length && _isWordCharacter(text.codeUnitAt(end))) {
      end += 1;
    }
    if (start == end) return null;
    return TextRange(start: start, end: end);
  }

  static TextRange _lineRangeAt(String text, int offset) {
    final safeOffset = offset.clamp(0, text.length);
    final searchFrom = safeOffset == 0 ? 0 : safeOffset - 1;
    final lineStart = text.lastIndexOf('\n', searchFrom) + 1;
    final nextBreak = text.indexOf('\n', safeOffset);
    return TextRange(
      start: lineStart,
      end: nextBreak < 0 ? text.length : nextBreak,
    );
  }

  static _MarkerRange? _enclosingMarker(
    String text,
    TextRange range,
    String marker,
  ) {
    final lineStart = text.lastIndexOf(
          '\n',
          range.start == 0 ? 0 : range.start - 1,
        ) +
        1;
    final nextBreak = text.indexOf('\n', range.end);
    final lineEnd = nextBreak < 0 ? text.length : nextBreak;
    var open = text.indexOf(marker, lineStart);
    while (open >= 0 && open < lineEnd) {
      final close = text.indexOf(marker, open + marker.length);
      if (close < 0 || close > lineEnd) return null;
      final contentStart = open + marker.length;
      final contains = range.isCollapsed
          ? range.start >= contentStart && range.start <= close
          : range.start >= contentStart && range.end <= close;
      if (contains) {
        return _MarkerRange(
          start: open,
          contentStart: contentStart,
          contentEnd: close,
          end: close + marker.length,
        );
      }
      open = text.indexOf(marker, close + marker.length);
    }
    return null;
  }

  static int _mapOffsetWithoutMarkers(
    int offset,
    _MarkerRange range,
    int markerLength,
  ) {
    if (offset <= range.start) return offset;
    if (offset <= range.contentStart) return range.start;
    if (offset <= range.contentEnd) return offset - markerLength;
    return offset - markerLength * 2;
  }

  static bool _isWordCharacter(int codeUnit) {
    return (codeUnit >= 48 && codeUnit <= 57) ||
        (codeUnit >= 65 && codeUnit <= 90) ||
        (codeUnit >= 97 && codeUnit <= 122) ||
        codeUnit == 45 ||
        codeUnit == 95 ||
        codeUnit >= 128;
  }

  static String _clearMarkdownSyntax(String value) {
    return value
        .replaceAllMapped(RegExp(r'\[(.*?)\]\((.*?)\)'), (match) {
          final label = match.group(1)?.trim() ?? '';
          final url = match.group(2)?.trim() ?? '';
          if (label.isEmpty) return url;
          if (url.isEmpty || label == url) return label;
          return '$label $url';
        })
        .replaceAll(RegExp(r'(\*\*|__|~~|`|<u>|</u>|```)', multiLine: true), '')
        .replaceAll(RegExp(r'^#{1,3}\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^>\s+', multiLine: true), '');
  }
}

class _MarkerRange {
  const _MarkerRange({
    required this.start,
    required this.contentStart,
    required this.contentEnd,
    required this.end,
  });

  final int start;
  final int contentStart;
  final int contentEnd;
  final int end;
}

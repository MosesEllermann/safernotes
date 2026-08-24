import 'package:safernotes_app/shared/models/note.dart';

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

List<ChecklistItem> moveChecklistItemBefore(
  List<ChecklistItem> items, {
  required String movingId,
  required String targetId,
}) {
  final ordered = orderChecklistItems(items);
  final movingIndex = ordered.indexWhere((item) => item.id == movingId);
  final targetIndexBeforeMove =
      ordered.indexWhere((item) => item.id == targetId);
  if (movingIndex < 0 || targetIndexBeforeMove < 0 || movingId == targetId) {
    return ordered;
  }
  final moving = ordered[movingIndex];
  final target = ordered[targetIndexBeforeMove];
  if (moving.done != target.done) return ordered;

  ordered.removeAt(movingIndex);
  final targetIndex = ordered.indexWhere((item) => item.id == targetId);
  if (targetIndex < 0) return orderChecklistItems(items);
  ordered.insert(targetIndex, moving);
  return ordered;
}

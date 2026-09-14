import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safernotes_app/shared/theme/app_icons.dart';
import 'package:uuid/uuid.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/notes/note_editor_state.dart';
import 'package:safernotes_app/features/notes/rich_text_document.dart';
import 'package:safernotes_app/features/notes/notes_controller.dart';
import 'package:safernotes_app/shared/app/app_l10n.dart';
import 'package:safernotes_app/shared/api/api_client.dart';
import 'package:safernotes_app/shared/models/note.dart';
import 'package:safernotes_app/shared/notifications/reminder_notifications.dart';
import 'package:safernotes_app/shared/providers.dart';
import 'package:safernotes_app/shared/theme/app_theme.dart';
import 'package:safernotes_app/shared/widgets/app_canvas.dart';
import 'package:safernotes_app/shared/widgets/app_info_bar.dart';
import 'package:safernotes_app/shared/widgets/animated_icon_button.dart';

bool get _usesIosNativeEditorControls =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

class NoteEditorScreen extends StatelessWidget {
  const NoteEditorScreen({super.key, required this.note});

  final PlainNote note;

  @override
  Widget build(BuildContext context) {
    final bottomViewInset = MediaQuery.viewInsetsOf(context).bottom;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: AppCanvas(
        child: SafeArea(
          child: NoteEditorPanel(
            note: note,
            bottomViewInset: bottomViewInset,
          ),
        ),
      ),
    );
  }
}

class NoteEditorPanel extends ConsumerStatefulWidget {
  const NoteEditorPanel({
    super.key,
    required this.note,
    this.embedded = false,
    this.bottomViewInset,
  });

  final PlainNote note;
  final bool embedded;
  final double? bottomViewInset;

  @override
  ConsumerState<NoteEditorPanel> createState() => _NoteEditorPanelState();
}

InputDecoration _borderlessInput(String hint) {
  return InputDecoration(
    hintText: hint,
    filled: false,
    isDense: true,
    contentPadding: EdgeInsets.zero,
    border: InputBorder.none,
    enabledBorder: InputBorder.none,
    focusedBorder: InputBorder.none,
    disabledBorder: InputBorder.none,
  );
}

class _NoteEditorPanelState extends ConsumerState<NoteEditorPanel> {
  final _uuid = const Uuid();
  late TextEditingController _title;
  late quill.QuillController _body;
  final _bodyFocusNode = FocusNode(debugLabel: 'note-body');
  final _bodyScrollController = ScrollController();
  late StreamSubscription<quill.DocChange> _bodyChanges;
  late List<ChecklistItem> _checklist;
  late bool _pinned;
  late List<String> _labels;
  late int _color;
  late bool _checklistMode;
  late DateTime? _reminderAt;
  late EditorHistory<_EditorSnapshot> _history;
  bool _restoringHistory = false;
  bool _checklistItemFocused = false;
  Timer? _autosave;

  static const _colors = brandNoteColors;

  @override
  void initState() {
    super.initState();
    _hydrate(widget.note);
  }

  @override
  void didUpdateWidget(covariant NoteEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.localId != widget.note.localId) {
      final previousDraft = _draftFrom(oldWidget.note);
      _autosave?.cancel();
      unawaited(
        ref.read(notesControllerProvider.notifier).saveDraft(
              draft: previousDraft,
              syncImmediately: true,
            ),
      );
      _bodyChanges.cancel();
      _title.dispose();
      _body.dispose();
      _checklistItemFocused = false;
      _hydrate(widget.note);
    }
  }

  void _hydrate(PlainNote note) {
    _title = TextEditingController(
      text: note.title == 'Untitled note' ? '' : note.title,
    );
    _body = quill.QuillController(
      document: noteDocument(
        delta: note.richTextDelta,
        legacyText: note.body,
      ),
      selection: const TextSelection.collapsed(offset: 0),
    );
    _checklist = orderChecklistItems(note.checklist);
    _checklistMode = note.checklist.isNotEmpty && note.body.trim().isEmpty;
    _pinned = note.pinned;
    _labels = [...note.labels];
    _color = normalizeBrandNoteColor(note.color);
    _reminderAt = note.reminderAt;
    _history = EditorHistory<_EditorSnapshot>(
      initialValue: _snapshot(),
      sameContent: (previous, next) => previous.hasSameContent(next),
    );
    _title.addListener(_handleControllerChange);
    _body.addListener(_handleRichSelectionChange);
    _bodyChanges = _body.document.changes.listen(_handleRichDocumentChange);
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _bodyChanges.cancel();
    _title.dispose();
    _body.dispose();
    _bodyFocusNode.dispose();
    _bodyScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final note = _draft();
    final width = MediaQuery.sizeOf(context).width;
    final bottomToolbar = width < 700;
    final desktop = width >= 900;
    final compactChecklistKeyboard = bottomToolbar &&
        _checklistMode &&
        _checklistItemFocused &&
        (widget.bottomViewInset ?? MediaQuery.viewInsetsOf(context).bottom) > 0;
    final surfaceColor = desktop
        ? brandNoteSurfaceColor(context, _color)
        : effectiveNoteSurfaceColor(context, _color);
    final presence = ref
        .watch(presenceProvider)
        .where(
            (item) => item.noteId == note.remoteId && item.status == 'online')
        .toList();
    final toolbar = _Toolbar(
      l10n: l10n,
      onFormat: _applyFormat,
      onBackground: _showBackgroundSheet,
      onUndo: _undo,
      onRedo: _redo,
      showFormatting: !_checklistMode,
      canUndo: _checklistMode ? _history.canUndo : _body.hasUndo,
      canRedo: _checklistMode ? _history.canRedo : _body.hasRedo,
      activeActions: _activeFormattingActions(),
      compact: compactChecklistKeyboard,
    );
    final titleField = TextField(
      key: const ValueKey('note-editor-title'),
      controller: _title,
      decoration: _borderlessInput(l10n.t('title')),
      style: bottomToolbar
          ? Theme.of(context).textTheme.headlineMedium
          : Theme.of(context).textTheme.displayMedium,
    );
    final headerActions = _EditorHeaderActions(
      compact: bottomToolbar,
      l10n: l10n,
      pinned: _pinned,
      shared: note.shared,
      reminderActive: _reminderAt != null,
      canShare: _reminderAt == null,
      onPin: () => _recordMutation(
        () => _pinned = !_pinned,
        immediate: true,
      ),
      onShare: () => _showShareSheet(note),
      onReminder: _showReminderSheet,
      onArchive: () => _changeNoteState('archived'),
      onTrash: () => _changeNoteState('trashed'),
    );
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyB):
            const _FormatIntent('bold'),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyB):
            const _FormatIntent('bold'),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyI):
            const _FormatIntent('italic'),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyI):
            const _FormatIntent('italic'),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyZ):
            const _HistoryIntent(redo: false),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyZ):
            const _HistoryIntent(redo: false),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.keyZ): const _HistoryIntent(redo: true),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.keyZ): const _HistoryIntent(redo: true),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyY):
            const _HistoryIntent(redo: true),
      },
      child: Actions(
        actions: {
          _FormatIntent: CallbackAction<_FormatIntent>(onInvoke: (intent) {
            _applyFormat(intent.action);
            return null;
          }),
          _HistoryIntent: CallbackAction<_HistoryIntent>(onInvoke: (intent) {
            intent.redo ? _redo() : _undo();
            return null;
          }),
        },
        child: Focus(
          autofocus: true,
          child: _DesktopEditorBackdrop(
            enabled: desktop,
            borderRadius: BorderRadius.circular(
              widget.embedded ? 0 : context.safernotesTheme.noteCardRadius,
            ),
            child: Material(
              key: const ValueKey('note-editor-surface'),
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(
                widget.embedded ? 0 : context.safernotesTheme.noteCardRadius,
              ),
              clipBehavior: Clip.antiAlias,
              child: Ink(
                decoration: BoxDecoration(
                  color: surfaceColor,
                  gradient: brandNoteGradient(context, _color),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        bottomToolbar ? 14 : 24,
                        compactChecklistKeyboard
                            ? 6
                            : bottomToolbar
                                ? 16
                                : 24,
                        bottomToolbar ? 10 : 20,
                        compactChecklistKeyboard ? 4 : 10,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (!desktop) ...[
                            Row(
                              children: [
                                if (!widget.embedded)
                                  _EditorBackButton(
                                    tooltip: l10n.t('close'),
                                    compact: bottomToolbar,
                                    onPressed: () {
                                      _saveNow();
                                      Navigator.of(context).maybePop();
                                    },
                                  ),
                                if (compactChecklistKeyboard)
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: Text(
                                        _title.text.trim().isEmpty
                                            ? l10n.t('title')
                                            : _title.text.trim(),
                                        key: const ValueKey(
                                          'checklist-compact-title',
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ),
                                      ),
                                    ),
                                  )
                                else
                                  const Spacer(),
                                _PresenceDots(presence: presence),
                                headerActions,
                              ],
                            ),
                            if (!compactChecklistKeyboard) ...[
                              SizedBox(height: bottomToolbar ? 16 : 20),
                              titleField,
                            ],
                          ] else
                            Row(
                              key: const ValueKey('desktop-editor-title-row'),
                              children: [
                                if (!widget.embedded) ...[
                                  _EditorBackButton(
                                    tooltip: l10n.t('close'),
                                    compact: false,
                                    onPressed: () {
                                      _saveNow();
                                      Navigator.of(context).maybePop();
                                    },
                                  ),
                                  const SizedBox(width: 14),
                                ],
                                Expanded(
                                  child: Transform.translate(
                                    key: const ValueKey(
                                      'desktop-editor-title-alignment',
                                    ),
                                    offset: const Offset(0, -4),
                                    child: titleField,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                _PresenceDots(presence: presence),
                                headerActions,
                              ],
                            ),
                        ],
                      ),
                    ),
                    if (!compactChecklistKeyboard)
                      _LabelEditorRow(
                        labels: _labels,
                        l10n: l10n,
                        onAdd: _promptAddLabel,
                        onRemove: (label) => _recordMutation(
                          () => _labels = [..._labels]..remove(label),
                          immediate: true,
                        ),
                      ),
                    if (!bottomToolbar) toolbar,
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final editor = _BodyEditor(
                            controller: _body,
                            focusNode: _bodyFocusNode,
                            scrollController: _bodyScrollController,
                            hint: l10n.t('writeNote'),
                          );
                          final checklist = _ChecklistEditor(
                            items: _checklist,
                            keyboardCompact: compactChecklistKeyboard,
                            onItemFocusChanged: (focused) {
                              if (_checklistItemFocused == focused) return;
                              setState(() => _checklistItemFocused = focused);
                            },
                            onChanged: (items) {
                              _recordMutation(
                                () => _checklist = orderChecklistItems(items),
                              );
                            },
                          );
                          return Align(
                            alignment: Alignment.topCenter,
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 900),
                              child: SizedBox(
                                height: constraints.maxHeight,
                                child: AnimatedSwitcher(
                                  key: const ValueKey('editor-content'),
                                  duration: const Duration(milliseconds: 180),
                                  layoutBuilder:
                                      (currentChild, previousChildren) {
                                    return Stack(
                                      alignment: Alignment.topCenter,
                                      children: [
                                        ...previousChildren,
                                        if (currentChild != null) currentChild,
                                      ],
                                    );
                                  },
                                  child: _checklistMode
                                      ? Padding(
                                          key: const ValueKey('checklist'),
                                          padding: compactChecklistKeyboard
                                              ? const EdgeInsets.fromLTRB(
                                                  16, 4, 16, 4)
                                              : const EdgeInsets.fromLTRB(
                                                  24, 20, 24, 20),
                                          child: checklist,
                                        )
                                      : Padding(
                                          key: const ValueKey('body'),
                                          padding: const EdgeInsets.fromLTRB(
                                              24, 10, 24, 16),
                                          child: editor,
                                        ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    if (bottomToolbar) toolbar,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  PlainNote _draft() {
    return _draftFrom(_currentNote());
  }

  PlainNote _draftFrom(PlainNote note) {
    return note.copyWith(
      title: _title.text.trim(),
      body: _checklistMode ? '' : documentPlainText(_body.document),
      richTextDelta: _checklistMode
          ? null
          : _body.document.toDelta().toJson().cast<Map<String, dynamic>>(),
      clearRichTextDelta: _checklistMode,
      checklist: _checklist,
      labels: _labels,
      pinned: _pinned,
      color: _color,
      reminderAt: _reminderAt,
      clearReminder: _reminderAt == null,
    );
  }

  _EditorSnapshot _snapshot() {
    return _EditorSnapshot(
      title: _title.value,
      checklist: [..._checklist],
      labels: [..._labels],
      pinned: _pinned,
      color: _color,
      checklistMode: _checklistMode,
      reminderAt: _reminderAt,
    );
  }

  void _handleControllerChange() {
    if (_restoringHistory) return;
    final contentChanged = _history.record(_snapshot());
    if (mounted) setState(() {});
    if (contentChanged) _scheduleSave();
  }

  void _handleRichSelectionChange() {
    if (!_restoringHistory && mounted) setState(() {});
  }

  void _handleRichDocumentChange(quill.DocChange _) {
    if (_restoringHistory) return;
    if (mounted) setState(() {});
    _scheduleSave();
  }

  Future<void> _promptAddLabel() async {
    final l10n = ref.read(l10nProvider);
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.t('addLabel')),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 32,
          decoration: InputDecoration(labelText: l10n.t('labelName')),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: Text(l10n.t('addLabel')),
          ),
        ],
      ),
    );
    controller.dispose();
    final trimmed = label?.trim();
    if (trimmed == null || trimmed.isEmpty) return;
    if (_labels.any((entry) => entry.toLowerCase() == trimmed.toLowerCase())) {
      return;
    }
    _recordMutation(
      () => _labels = [..._labels, trimmed],
      immediate: true,
    );
  }

  void _recordMutation(VoidCallback mutation, {bool immediate = false}) {
    _restoringHistory = true;
    setState(mutation);
    _restoringHistory = false;
    if (_history.record(_snapshot())) {
      _scheduleSave(immediate: immediate);
    }
  }

  void _undo() {
    if (!_checklistMode) {
      if (_body.hasUndo) _body.undo();
      return;
    }
    final snapshot = _history.undo();
    if (snapshot != null) _restoreSnapshot(snapshot);
  }

  void _redo() {
    if (!_checklistMode) {
      if (_body.hasRedo) _body.redo();
      return;
    }
    final snapshot = _history.redo();
    if (snapshot != null) _restoreSnapshot(snapshot);
  }

  void _restoreSnapshot(_EditorSnapshot snapshot) {
    _autosave?.cancel();
    _restoringHistory = true;
    setState(() {
      _title.value = snapshot.title;
      _checklist = [...snapshot.checklist];
      _pinned = snapshot.pinned;
      _labels = [...snapshot.labels];
      _color = snapshot.color;
      _checklistMode = snapshot.checklistMode;
      _reminderAt = snapshot.reminderAt;
    });
    _restoringHistory = false;
    _scheduleSave();
  }

  Set<String> _activeFormattingActions() {
    final attributes = _body.getSelectionStyle().attributes;
    return {
      if (attributes.containsKey(quill.Attribute.bold.key)) 'bold',
      if (attributes.containsKey(quill.Attribute.italic.key)) 'italic',
      if (attributes.containsKey(quill.Attribute.strikeThrough.key)) 'strike',
      if (attributes.containsKey(quill.Attribute.link.key)) 'link',
      if (attributes.containsKey(quill.Attribute.codeBlock.key)) 'codeblock',
      if (attributes[quill.Attribute.list.key]?.value ==
          quill.Attribute.ul.value)
        'bullet',
    };
  }

  PlainNote _currentNote() {
    final notes = ref.read(notesControllerProvider).valueOrNull;
    if (notes == null) return widget.note;
    for (final note in notes) {
      if (note.localId == widget.note.localId) return note;
    }
    return widget.note;
  }

  void _scheduleSave({bool immediate = false}) {
    _autosave?.cancel();
    _autosave = Timer(
        immediate ? Duration.zero : const Duration(milliseconds: 700),
        _saveNow);
  }

  Future<void> _saveNow() {
    return ref.read(notesControllerProvider.notifier).saveDraft(
          draft: _draft(),
          syncImmediately: true,
        );
  }

  Future<void> _changeNoteState(String state) async {
    await _saveNow();
    await ref
        .read(notesControllerProvider.notifier)
        .changeState(_draft(), state);
    if (mounted && !widget.embedded) {
      Navigator.of(context).maybePop();
    }
  }

  void _applyFormat(String action) {
    if (_checklistMode) return;
    if (action == 'link') {
      unawaited(_showLinkSheet());
      return;
    }
    if (action == 'codeblock') {
      _toggleQuillAttribute(quill.Attribute.codeBlock);
      return;
    }
    if (action == 'bullet') {
      _toggleQuillAttribute(quill.Attribute.ul);
      return;
    }
    if (action == 'check') {
      final text = documentPlainText(_body.document);
      final selection = _body.selection;
      final start = selection.start.clamp(0, text.length);
      final end = selection.end.clamp(start, text.length);
      final selected = start == end ? '' : text.substring(start, end);
      final lines = selected.trim().isEmpty ? [''] : selected.split('\n');
      _recordMutation(() {
        _checklistMode = true;
        for (final line in lines) {
          _checklist = insertUncheckedItem(
            _checklist,
            ChecklistItem(
              id: _uuid.v4(),
              text: line.replaceFirst(RegExp(r'^[-*]\s*'), ''),
              done: false,
              indent: 0,
            ),
          );
        }
      });
      return;
    }
    switch (action) {
      case 'bold':
        _toggleQuillAttribute(quill.Attribute.bold);
      case 'italic':
        _toggleQuillAttribute(quill.Attribute.italic);
      case 'strike':
        _toggleQuillAttribute(quill.Attribute.strikeThrough);
      case 'clear':
        final attributes = <quill.Attribute>{};
        for (final style in _body.getAllSelectionStyles()) {
          attributes.addAll(style.attributes.values);
        }
        for (final attribute in attributes) {
          _body.formatSelection(quill.Attribute.clone(attribute, null));
        }
    }
  }

  void _toggleQuillAttribute(quill.Attribute attribute) {
    final active =
        _body.getSelectionStyle().attributes.containsKey(attribute.key);
    _body.formatSelection(
      active ? quill.Attribute.clone(attribute, null) : attribute,
    );
  }

  Future<void> _showLinkSheet() async {
    final selection = _body.selection;
    final text = documentPlainText(_body.document);
    final start = selection.start.clamp(0, text.length);
    final end = selection.end.clamp(start, text.length);
    final selected = start == end ? '' : text.substring(start, end);
    final existing =
        _body.getSelectionStyle().attributes[quill.Attribute.link.key];
    final result = await showModalBottomSheet<_LinkEdit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LinkSheet(
        initialLabel: selected,
        initialUrl: existing?.value?.toString() ?? '',
        canRemove: existing != null,
      ),
    );
    if (result == null || !mounted) return;
    if (start != end && result.label != selected) {
      _body.replaceText(
        start,
        end - start,
        result.label,
        TextSelection(
            baseOffset: start, extentOffset: start + result.label.length),
      );
    } else if (start == end && result.label.isNotEmpty) {
      _body.replaceText(
        start,
        0,
        result.label,
        TextSelection(
            baseOffset: start, extentOffset: start + result.label.length),
      );
    }
    final linkLength =
        result.label.isNotEmpty ? result.label.length : end - start;
    if (linkLength == 0) return;
    _body.formatText(
      start,
      linkLength,
      result.remove
          ? quill.Attribute.clone(quill.Attribute.link, null)
          : quill.LinkAttribute(_normalizeUrl(result.url)),
    );
    _body.updateSelection(
      TextSelection.collapsed(offset: start + linkLength),
      quill.ChangeSource.local,
    );
  }

  String _normalizeUrl(String value) {
    final trimmed = value.trim();
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(trimmed)) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  Future<void> _showBackgroundSheet() async {
    final color = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _BackgroundSheet(
        colors: _colors,
        selectedColor: _color,
      ),
    );
    if (color == null || !mounted) return;
    _recordMutation(() => _color = color, immediate: true);
  }

  void _showShareSheet(PlainNote note) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShareSheet(note: note),
    );
  }

  Future<void> _showReminderSheet() async {
    final draft = _draft();
    var duplicateShared = false;
    if (draft.shared && draft.reminderAt == null) {
      duplicateShared = await _confirmDuplicateReminder(context) ?? false;
      if (!duplicateShared) return;
    }
    if (!mounted) return;
    final selection = await showModalBottomSheet<_ReminderSelection>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditorReminderSheet(reminderAt: _reminderAt),
    );
    if (selection == null) return;
    final selected = selection.value;
    if (!mounted) return;
    if (selected == _reminderAt) return;
    if (selected != null) await requestReminderPermission();
    if (duplicateShared && selected != null) {
      await ref.read(notesControllerProvider.notifier).duplicateAsReminder(
            source: draft,
            reminderAt: selected,
          );
      if (!mounted) return;
      _showReminderFeedback(true, duplicated: true);
      return;
    }
    _recordMutation(() => _reminderAt = selected, immediate: true);
    _showReminderFeedback(selected != null);
  }

  Future<bool?> _confirmDuplicateReminder(BuildContext context) {
    final l10n = ref.read(l10nProvider);
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(l10n.t('sharedNote')),
          content: Text(l10n.t('sharedReminderDescription')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.t('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.t('duplicateAsReminder')),
            ),
          ],
        );
      },
    );
  }

  void _showReminderFeedback(bool added, {bool duplicated = false}) {
    final l10n = ref.read(l10nProvider);
    showAppInfoBar(
      context,
      message: l10n.t(
        added
            ? duplicated
                ? 'reminderDuplicateAdded'
                : 'reminderAdded'
            : 'reminderRemoved',
      ),
    );
  }
}

class _DesktopEditorBackdrop extends StatelessWidget {
  const _DesktopEditorBackdrop({
    required this.enabled,
    required this.borderRadius,
    required this.child,
  });

  final bool enabled;
  final BorderRadius borderRadius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        key: const ValueKey('desktop-note-editor-backdrop'),
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: child,
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.l10n,
    required this.onFormat,
    required this.onBackground,
    required this.onUndo,
    required this.onRedo,
    required this.showFormatting,
    required this.canUndo,
    required this.canRedo,
    required this.activeActions,
    this.compact = false,
  });

  final AppL10n l10n;
  final ValueChanged<String> onFormat;
  final VoidCallback onBackground;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool showFormatting;
  final bool canUndo;
  final bool canRedo;
  final Set<String> activeActions;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      _ToolbarItem('bold', AppIcons.bold, l10n.t('bold')),
      _ToolbarItem('italic', AppIcons.italic, l10n.t('italic')),
      _ToolbarItem('strike', AppIcons.strikethrough, l10n.t('strikethrough')),
      _ToolbarItem('link', AppIcons.link, l10n.t('link')),
      _ToolbarItem('codeblock', AppIcons.squareCode, l10n.t('codeBlock')),
      _ToolbarItem('bullet', AppIcons.list, l10n.t('bulletList')),
      _ToolbarItem('check', AppIcons.squareCheck, l10n.t('checklist')),
      _ToolbarItem(
          'clear', AppIcons.removeFormatting, l10n.t('clearFormatting')),
    ];
    final scheme = Theme.of(context).colorScheme;
    final nativeGlass = _usesIosNativeEditorControls;
    final content = Material(
      color: nativeGlass
          ? Colors.transparent
          : scheme.surface.withValues(alpha: 0.68),
      borderRadius: BorderRadius.circular(AppRadii.xxl),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 8,
          vertical: compact ? 2 : 7,
        ),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    AppIconButton(
                      tooltip: l10n.t('undo'),
                      icon: AppIcons.undo2,
                      onPressed: canUndo ? onUndo : null,
                    ),
                    AppIconButton(
                      tooltip: l10n.t('redo'),
                      icon: AppIcons.redo2,
                      onPressed: canRedo ? onRedo : null,
                    ),
                    if (showFormatting) ...[
                      const SizedBox(width: 8),
                      for (final item in buttons)
                        AppIconButton(
                          tooltip: item.tooltip,
                          icon: item.icon,
                          selected: activeActions.contains(item.action),
                          onPressed: () => onFormat(item.action),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            AppIconButton(
              tooltip: l10n.t('background'),
              icon: AppIcons.palette,
              onPressed: onBackground,
            ),
          ],
        ),
      ),
    );
    return Padding(
      padding: compact
          ? const EdgeInsets.fromLTRB(12, 4, 12, 6)
          : const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: nativeGlass
          ? LiquidGlassContainer(
              key: const ValueKey('ios-editor-formatting-glass'),
              config: LiquidGlassConfig(
                effect: CNGlassEffect.regular,
                shape: CNGlassEffectShape.capsule,
                tint: scheme.surface.withValues(alpha: 0.08),
                interactive: true,
              ),
              child: content,
            )
          : content,
    );
  }
}

class _ToolbarItem {
  const _ToolbarItem(this.action, this.icon, this.tooltip);

  final String action;
  final IconData icon;
  final String tooltip;
}

class _LinkSheet extends StatefulWidget {
  const _LinkSheet({
    required this.initialLabel,
    required this.initialUrl,
    required this.canRemove,
  });

  final String initialLabel;
  final String initialUrl;
  final bool canRemove;

  @override
  State<_LinkSheet> createState() => _LinkSheetState();
}

class _LinkSheetState extends State<_LinkSheet> {
  late final TextEditingController _label =
      TextEditingController(text: widget.initialLabel);
  late final TextEditingController _url =
      TextEditingController(text: widget.initialUrl);

  @override
  void initState() {
    super.initState();
    _label.addListener(_refresh);
    _url.addListener(_refresh);
  }

  @override
  void dispose() {
    _label
      ..removeListener(_refresh)
      ..dispose();
    _url
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n(Localizations.localeOf(context).languageCode);
    final scheme = Theme.of(context).colorScheme;
    final canSave =
        _label.text.trim().isNotEmpty && _url.text.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(AppRadii.hero),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(AppRadii.xl),
                            ),
                            child: Icon(
                              AppIcons.link,
                              size: 20,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.t('link'),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          AppIconButton(
                            tooltip: l10n.t('close'),
                            icon: AppIcons.x,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: _label,
                        autofocus: widget.initialLabel.trim().isEmpty,
                        textInputAction: TextInputAction.next,
                        decoration: InputDecoration(
                          labelText: l10n.t('text'),
                          prefixIcon: const Icon(AppIcons.type, size: 18),
                          filled: true,
                          fillColor: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.42),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadii.xl),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _url,
                        autofocus: widget.initialLabel.trim().isNotEmpty &&
                            widget.initialUrl.trim().isEmpty,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: l10n.t('url'),
                          prefixIcon: const Icon(AppIcons.globe, size: 18),
                          filled: true,
                          fillColor: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.42),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadii.xl),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: canSave
                            ? () => Navigator.of(context).pop(_LinkEdit(
                                  label: _label.text.trim(),
                                  url: _url.text.trim(),
                                ))
                            : null,
                        icon: const Icon(AppIcons.check),
                        label: Text(l10n.t('save')),
                      ),
                      if (widget.canRemove) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).pop(_LinkEdit(
                            label: _label.text.trim(),
                            url: _url.text.trim(),
                            remove: true,
                          )),
                          icon: const Icon(AppIcons.unlink),
                          label: Text(l10n.t('removeLink')),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackgroundSheet extends StatelessWidget {
  const _BackgroundSheet({
    required this.colors,
    required this.selectedColor,
  });

  final List<int> colors;
  final int selectedColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n(Localizations.localeOf(context).languageCode);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(AppRadii.hero),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(AppRadii.xl),
                            ),
                            child: Icon(
                              AppIcons.palette,
                              size: 20,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.t('background'),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          AppIconButton(
                            tooltip: l10n.t('close'),
                            icon: AppIcons.x,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          for (final color in colors)
                            _BackgroundColorTile(
                              color: color,
                              selected: color == selectedColor,
                              onSelected: () =>
                                  Navigator.of(context).pop(color),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackgroundColorTile extends StatelessWidget {
  const _BackgroundColorTile({
    required this.color,
    required this.selected,
    required this.onSelected,
  });

  final int color;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.xl),
      onTap: onSelected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: 64,
        height: 56,
        decoration: BoxDecoration(
          color: brandNoteSurfaceColor(context, color),
          gradient: brandNoteGradient(context, color),
          borderRadius: BorderRadius.circular(AppRadii.xl),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.26),
                    blurRadius: 0,
                    spreadRadius: 3,
                  ),
                ]
              : null,
        ),
        child: selected
            ? Icon(AppIcons.check, size: 18, color: scheme.onSurface)
            : null,
      ),
    );
  }
}

class _LinkEdit {
  const _LinkEdit({
    required this.label,
    required this.url,
    this.remove = false,
  });

  final String label;
  final String url;
  final bool remove;
}

class _ReminderSelection {
  const _ReminderSelection(this.value);

  final DateTime? value;
}

class _EditorReminderSheet extends StatefulWidget {
  const _EditorReminderSheet({required this.reminderAt});

  final DateTime? reminderAt;

  @override
  State<_EditorReminderSheet> createState() => _EditorReminderSheetState();
}

class _EditorReminderSheetState extends State<_EditorReminderSheet> {
  late DateTime _selected = widget.reminderAt?.toLocal() ??
      DateTime.now().add(const Duration(hours: 1));

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n(Localizations.localeOf(context).languageCode);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(AppRadii.hero),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(AppRadii.xl),
                            ),
                            child: Icon(
                              AppIcons.bell,
                              size: 20,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.t('reminder'),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          AppIconButton(
                            tooltip: l10n.t('close'),
                            icon: AppIcons.x,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _EditorReminderPickTile(
                        icon: AppIcons.calendar,
                        label: l10n.t('date'),
                        value:
                            '${_selected.day.toString().padLeft(2, '0')}.${_selected.month.toString().padLeft(2, '0')}.${_selected.year}',
                        onTap: _pickDate,
                      ),
                      const SizedBox(height: 10),
                      _EditorReminderPickTile(
                        icon: AppIcons.clock3,
                        label: l10n.t('time'),
                        value:
                            '${_selected.hour.toString().padLeft(2, '0')}:${_selected.minute.toString().padLeft(2, '0')}',
                        onTap: _pickTime,
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context)
                            .pop(_ReminderSelection(_selected.toUtc())),
                        icon: const Icon(AppIcons.bellRing),
                        label: Text(l10n.t('setReminder')),
                      ),
                      if (widget.reminderAt != null) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => Navigator.of(context)
                              .pop(const _ReminderSelection(null)),
                          icon: const Icon(AppIcons.bellOff),
                          label: Text(l10n.t('removeReminder')),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selected,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
    );
    if (picked == null) return;
    setState(() {
      _selected = DateTime(
        picked.year,
        picked.month,
        picked.day,
        _selected.hour,
        _selected.minute,
      );
    });
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_selected),
    );
    if (picked == null) return;
    setState(() {
      _selected = DateTime(
        _selected.year,
        _selected.month,
        _selected.day,
        picked.hour,
        picked.minute,
      );
    });
  }
}

class _EditorReminderPickTile extends StatelessWidget {
  const _EditorReminderPickTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.xl),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(AppRadii.xl),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            Text(
              value,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BodyEditor extends StatelessWidget {
  const _BodyEditor({
    required this.controller,
    required this.focusNode,
    required this.scrollController,
    required this.hint,
  });

  final quill.QuillController controller;
  final FocusNode focusNode;
  final ScrollController scrollController;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return quill.QuillEditor.basic(
      controller: controller,
      focusNode: focusNode,
      scrollController: scrollController,
      config: quill.QuillEditorConfig(
        expands: true,
        placeholder: hint,
        padding: EdgeInsets.zero,
        textCapitalization: TextCapitalization.sentences,
      ),
    );
  }
}

class _ChecklistEditor extends ConsumerStatefulWidget {
  const _ChecklistEditor({
    required this.items,
    required this.onChanged,
    required this.keyboardCompact,
    required this.onItemFocusChanged,
  });

  final List<ChecklistItem> items;
  final ValueChanged<List<ChecklistItem>> onChanged;
  final bool keyboardCompact;
  final ValueChanged<bool> onItemFocusChanged;

  @override
  ConsumerState<_ChecklistEditor> createState() => _ChecklistEditorState();
}

class _ChecklistEditorState extends ConsumerState<_ChecklistEditor> {
  String? _focusItemId;
  String? _focusedItemId;
  final _scrollController = ScrollController();
  final _itemKeys = <String, GlobalKey>{};
  double _lastKeyboardInset = 0;

  static const _rowHeight = 42.0;
  static const _addHeight = 44.0;
  static const _completedHeaderHeight = 38.0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    if (keyboardInset != _lastKeyboardInset) {
      _lastKeyboardInset = keyboardInset;
      _scheduleFocusedItemVisibility();
    }
  }

  @override
  void didUpdateWidget(covariant _ChecklistEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keyboardCompact != widget.keyboardCompact) {
      _scheduleFocusedItemVisibility();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final unchecked = widget.items.where((item) => !item.done).toList();
    final checked = widget.items.where((item) => item.done).toList();
    final itemIds = widget.items.map((item) => item.id).toSet();
    _itemKeys.removeWhere((id, _) => !itemIds.contains(id));
    return SingleChildScrollView(
      key: const ValueKey('checklist-scroll-view'),
      controller: _scrollController,
      child: _buildAnimatedItems(context, unchecked, checked),
    );
  }

  Widget _buildAnimatedItems(
    BuildContext context,
    List<ChecklistItem> unchecked,
    List<ChecklistItem> checked,
  ) {
    final l10n = ref.watch(l10nProvider);
    final checkedOffset = unchecked.length * _rowHeight +
        _addHeight +
        (checked.isEmpty ? 0 : _completedHeaderHeight);
    final height = checkedOffset + checked.length * _rowHeight;
    final positions = <String, double>{};
    for (var index = 0; index < unchecked.length; index += 1) {
      positions[unchecked[index].id] = index * _rowHeight;
    }
    for (var index = 0; index < checked.length; index += 1) {
      positions[checked[index].id] = checkedOffset + index * _rowHeight;
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: SizedBox(
        height: height,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final item in widget.items)
              AnimatedPositioned(
                key: ValueKey('position-${item.id}'),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOutCubic,
                left: 0,
                right: 0,
                top: positions[item.id] ?? 0,
                height: _rowHeight,
                child: DragTarget<String>(
                  onWillAcceptWithDetails: (details) => details.data != item.id,
                  onAcceptWithDetails: (details) => widget.onChanged(
                    moveChecklistItemBefore(
                      widget.items,
                      movingId: details.data,
                      targetId: item.id,
                    ),
                  ),
                  builder: (context, candidates, _) => KeyedSubtree(
                    key: _itemKeys.putIfAbsent(item.id, GlobalKey.new),
                    child: _ChecklistRow(
                      key: ValueKey(item.id),
                      item: item,
                      l10n: l10n,
                      autofocus: item.id == _focusItemId,
                      dropTargeted: candidates.isNotEmpty,
                      onChanged: (updated) => widget.onChanged(
                        updateChecklistItem(widget.items, updated),
                      ),
                      onDelete: () {
                        _handleItemFocusChanged(item.id, false);
                        widget.onChanged(
                          widget.items
                              .where((candidate) => candidate.id != item.id)
                              .toList(),
                        );
                      },
                      onInsertAfter: () => _insertItem(after: item),
                      onFocusChanged: (focused) =>
                          _handleItemFocusChanged(item.id, focused),
                    ),
                  ),
                ),
              ),
            AnimatedPositioned(
              key: const ValueKey('checklist-add-position'),
              duration: const Duration(milliseconds: 320),
              curve: Curves.easeInOutCubic,
              left: 0,
              right: 0,
              top: unchecked.length * _rowHeight,
              height: _addHeight,
              child: _ChecklistAddButton(
                label: l10n.t('addTask'),
                onPressed: () => _insertItem(),
              ),
            ),
            if (checked.isNotEmpty)
              Positioned(
                left: 42,
                right: 0,
                top: unchecked.length * _rowHeight + _addHeight,
                height: _completedHeaderHeight,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Erledigt (${checked.length})',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _insertItem({ChecklistItem? after}) {
    final inserted = ChecklistItem(
      id: const Uuid().v4(),
      text: '',
      done: false,
      indent: after?.done == false ? after!.indent : 0,
    );
    setState(() => _focusItemId = inserted.id);
    widget.onChanged(insertUncheckedItem(
      widget.items,
      inserted,
      afterItemId: after?.done == false ? after!.id : null,
    ));
  }

  void _handleItemFocusChanged(String itemId, bool focused) {
    if (focused) {
      _focusedItemId = itemId;
      if (_focusItemId == itemId) {
        setState(() => _focusItemId = null);
      }
      widget.onItemFocusChanged(true);
      _scheduleFocusedItemVisibility();
      return;
    }
    if (_focusedItemId != itemId) return;
    _focusedItemId = null;
    widget.onItemFocusChanged(false);
  }

  void _scheduleFocusedItemVisibility() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final itemId = _focusedItemId;
      final itemContext =
          itemId == null ? null : _itemKeys[itemId]?.currentContext;
      if (itemContext == null) return;
      unawaited(
        Scrollable.ensureVisible(
          itemContext,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: 1,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ),
      );
    });
  }
}

class _ChecklistAddButton extends StatelessWidget {
  const _ChecklistAddButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      key: const ValueKey('checklist-add'),
      onTap: onPressed,
      borderRadius: BorderRadius.circular(6),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Icon(
            AppIcons.plus,
            size: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 14),
          Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

class _ChecklistRow extends StatefulWidget {
  const _ChecklistRow({
    super.key,
    required this.item,
    required this.l10n,
    required this.autofocus,
    required this.dropTargeted,
    required this.onChanged,
    required this.onDelete,
    required this.onInsertAfter,
    required this.onFocusChanged,
  });

  final ChecklistItem item;
  final AppL10n l10n;
  final bool autofocus;
  final bool dropTargeted;
  final ValueChanged<ChecklistItem> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onInsertAfter;
  final ValueChanged<bool> onFocusChanged;

  @override
  State<_ChecklistRow> createState() => _ChecklistRowState();
}

class _ChecklistRowState extends State<_ChecklistRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.item.text,
  )..selection = TextSelection.collapsed(offset: widget.item.text.length);
  final _focusNode = FocusNode();
  Offset? _swipeOrigin;
  double _swipeOffset = 0;
  bool _dragHandleActive = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChanged);
  }

  @override
  void didUpdateWidget(covariant _ChecklistRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.item.text != _controller.text) {
      final offset =
          _controller.selection.extentOffset.clamp(0, widget.item.text.length);
      _controller.value = TextEditingValue(
        text: widget.item.text,
        selection: TextSelection.collapsed(offset: offset),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChanged() => widget.onFocusChanged(_focusNode.hasFocus);

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 700;
    final row = AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      padding: EdgeInsets.only(left: widget.item.indent * 18.0, bottom: 2),
      decoration: BoxDecoration(
        color: widget.dropTargeted
            ? Theme.of(context)
                .colorScheme
                .primaryContainer
                .withValues(alpha: 0.48)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Listener(
            onPointerDown: (_) {
              _dragHandleActive = true;
              _swipeOrigin = null;
            },
            onPointerUp: (_) => _dragHandleActive = false,
            onPointerCancel: (_) => _dragHandleActive = false,
            child: Draggable<String>(
              data: widget.item.id,
              feedback: Material(
                color: Colors.transparent,
                child: Icon(
                  AppIcons.gripVertical,
                  size: 22,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              childWhenDragging: Opacity(
                opacity: 0.28,
                child: _ChecklistDragHandle(l10n: widget.l10n),
              ),
              child: _ChecklistDragHandle(l10n: widget.l10n),
            ),
          ),
          Checkbox(
            visualDensity: VisualDensity.compact,
            value: widget.item.done,
            onChanged: (value) =>
                widget.onChanged(widget.item.copyWith(done: value ?? false)),
          ),
          Expanded(
            child: TextField(
              autofocus: widget.autofocus,
              controller: _controller,
              focusNode: _focusNode,
              decoration: _borderlessInput('Task'),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    decoration:
                        widget.item.done ? TextDecoration.lineThrough : null,
                    color: widget.item.done
                        ? Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.56)
                        : null,
                  ),
              onChanged: (value) =>
                  widget.onChanged(widget.item.copyWith(text: value)),
              onSubmitted: (_) => widget.onInsertAfter(),
            ),
          ),
          if (!mobile) ...[
            _ChecklistActionButton(
              key: ValueKey('outdent-${widget.item.id}'),
              tooltip: widget.l10n.t('outdentTask'),
              icon: AppIcons.indentDecrease,
              onPressed: widget.item.indent == 0
                  ? null
                  : () => widget.onChanged(
                        widget.item.copyWith(indent: widget.item.indent - 1),
                      ),
            ),
            _ChecklistActionButton(
              key: ValueKey('indent-${widget.item.id}'),
              tooltip: widget.l10n.t('indentTask'),
              icon: AppIcons.indentIncrease,
              onPressed: widget.item.indent >= 4
                  ? null
                  : () => widget.onChanged(
                        widget.item.copyWith(indent: widget.item.indent + 1),
                      ),
            ),
          ],
          const SizedBox(width: 4),
          _ChecklistActionButton(
            key: ValueKey('delete-${widget.item.id}'),
            tooltip: widget.l10n.t('deleteTask'),
            icon: AppIcons.x,
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
    if (!mobile) return row;
    return Listener(
      key: ValueKey('swipe-indent-${widget.item.id}'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (_dragHandleActive) return;
        _swipeOrigin = event.position;
        _swipeOffset = 0;
      },
      onPointerMove: (event) {
        final origin = _swipeOrigin;
        if (origin == null) return;
        final delta = event.position - origin;
        if (delta.dx.abs() <= delta.dy.abs()) return;
        setState(() => _swipeOffset = delta.dx.clamp(-52.0, 52.0));
      },
      onPointerUp: (_) => _finishSwipe(),
      onPointerCancel: (_) => _cancelSwipe(),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 8,
            child: AnimatedOpacity(
              opacity: _swipeOffset > 8 ? 1 : 0,
              duration: const Duration(milliseconds: 80),
              child: const Icon(AppIcons.indentIncrease, size: 20),
            ),
          ),
          Positioned(
            right: 8,
            child: AnimatedOpacity(
              opacity: _swipeOffset < -8 ? 1 : 0,
              duration: const Duration(milliseconds: 80),
              child: const Icon(AppIcons.indentDecrease, size: 20),
            ),
          ),
          AnimatedContainer(
            duration: _swipeOrigin == null
                ? const Duration(milliseconds: 150)
                : Duration.zero,
            curve: Curves.easeOutCubic,
            transform: Matrix4.translationValues(_swipeOffset, 0, 0),
            child: row,
          ),
        ],
      ),
    );
  }

  void _finishSwipe() {
    final offset = _swipeOffset;
    _cancelSwipe();
    if (offset >= 42 && widget.item.indent < 4) {
      widget.onChanged(widget.item.copyWith(indent: widget.item.indent + 1));
    } else if (offset <= -42 && widget.item.indent > 0) {
      widget.onChanged(widget.item.copyWith(indent: widget.item.indent - 1));
    }
  }

  void _cancelSwipe() {
    if (!mounted) return;
    setState(() {
      _swipeOrigin = null;
      _swipeOffset = 0;
    });
  }
}

class _ChecklistDragHandle extends StatelessWidget {
  const _ChecklistDragHandle({required this.l10n});

  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: l10n.t('reorderTask'),
      child: SizedBox(
        key: const ValueKey('checklist-drag-handle'),
        width: 32,
        height: 40,
        child: Icon(
          AppIcons.gripVertical,
          size: 20,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ChecklistActionButton extends StatelessWidget {
  const _ChecklistActionButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      iconSize: 18,
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints.tightFor(width: 40, height: 40),
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurface.withValues(alpha: 0.78),
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.24),
        hoverColor: scheme.surfaceContainerHighest,
        highlightColor: scheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }
}

class _EditorBackButton extends StatelessWidget {
  const _EditorBackButton({
    required this.tooltip,
    required this.compact,
    required this.onPressed,
  });

  final String tooltip;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (compact && _usesIosNativeEditorControls) {
      return Tooltip(
        message: tooltip,
        child: SizedBox.square(
          key: const ValueKey('ios-editor-back-button'),
          dimension: 44,
          child: CNButton.icon(
            icon: const CNSymbol('chevron.left', size: 17),
            onPressed: onPressed,
            tint: Theme.of(context).colorScheme.onSurface,
            config: const CNButtonConfig(
              style: CNButtonStyle.glass,
              width: 44,
              minHeight: 44,
              padding: EdgeInsets.zero,
              glassEffectId: 'note-editor-back',
              glassEffectInteractive: true,
            ),
          ),
        ),
      );
    }
    return AppIconButton(
      key: const ValueKey('editor-back-button'),
      tooltip: tooltip,
      icon: AppIcons.chevronLeft,
      size: compact ? 44 : 36,
      onPressed: onPressed,
    );
  }
}

class _EditorHeaderActions extends StatelessWidget {
  const _EditorHeaderActions({
    required this.compact,
    required this.l10n,
    required this.pinned,
    required this.shared,
    required this.reminderActive,
    required this.canShare,
    required this.onPin,
    required this.onShare,
    required this.onReminder,
    required this.onArchive,
    required this.onTrash,
  });

  final bool compact;
  final AppL10n l10n;
  final bool pinned;
  final bool shared;
  final bool reminderActive;
  final bool canShare;
  final VoidCallback onPin;
  final VoidCallback onShare;
  final VoidCallback onReminder;
  final VoidCallback onArchive;
  final VoidCallback onTrash;

  CNButtonData _nativeButton({
    required String symbol,
    required String effectId,
    required Color tint,
    required VoidCallback? onPressed,
    bool selected = false,
  }) {
    return CNButtonData.icon(
      icon: CNSymbol(symbol, size: 17),
      onPressed: onPressed,
      enabled: onPressed != null,
      tint: tint,
      config: CNButtonDataConfig(
        width: 40,
        minHeight: 40,
        padding: EdgeInsets.zero,
        style: selected ? CNButtonStyle.prominentGlass : CNButtonStyle.glass,
        glassEffectUnionId: 'note-editor-header-actions',
        glassEffectId: effectId,
        glassEffectInteractive: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (compact && _usesIosNativeEditorControls) {
      return SizedBox(
        key: const ValueKey('ios-editor-header-action-bar'),
        width: 226,
        height: 43,
        child: CNGlassButtonGroup(
          axis: Axis.horizontal,
          spacing: 4,
          spacingForGlass: 36,
          buttons: [
            _nativeButton(
              symbol: pinned ? 'heart.fill' : 'heart',
              effectId: 'note-editor-pin',
              tint: pinned ? brandLavender : scheme.onSurface,
              selected: pinned,
              onPressed: onPin,
            ),
            _nativeButton(
              symbol: shared ? 'person.2.fill' : 'person.badge.plus',
              effectId: 'note-editor-share',
              tint: scheme.onSurface,
              onPressed: canShare ? onShare : null,
            ),
            _nativeButton(
              symbol: reminderActive ? 'bell.fill' : 'bell',
              effectId: 'note-editor-reminder',
              tint: reminderActive ? scheme.primary : scheme.onSurface,
              selected: reminderActive,
              onPressed: onReminder,
            ),
            _nativeButton(
              symbol: 'archivebox',
              effectId: 'note-editor-archive',
              tint: scheme.onSurface,
              onPressed: onArchive,
            ),
            _nativeButton(
              symbol: 'trash',
              effectId: 'note-editor-trash',
              tint: scheme.error,
              onPressed: onTrash,
            ),
          ],
        ),
      );
    }
    final size = compact ? 40.0 : 36.0;
    return Row(
      key: const ValueKey('editor-header-action-bar'),
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconButton(
          tooltip: pinned ? l10n.t('unpin') : l10n.t('pin'),
          icon: pinned ? AppIcons.heartFill : AppIcons.heart,
          size: size,
          selected: pinned,
          onPressed: onPin,
        ),
        const SizedBox(width: 6),
        AppIconButton(
          tooltip: l10n.t('collaboratorInvite'),
          icon: shared ? AppIcons.users : AppIcons.userPlus,
          size: size,
          onPressed: canShare ? onShare : null,
        ),
        const SizedBox(width: 6),
        AppIconButton(
          tooltip: l10n.t('reminder'),
          icon: reminderActive ? AppIcons.bellRing : AppIcons.bell,
          size: size,
          selected: reminderActive,
          onPressed: onReminder,
        ),
        const SizedBox(width: 6),
        AppIconButton(
          tooltip: l10n.t('archiveNote'),
          icon: AppIcons.archive,
          size: size,
          onPressed: onArchive,
        ),
        const SizedBox(width: 6),
        AppIconButton(
          tooltip: l10n.t('moveToTrash'),
          icon: AppIcons.trash,
          size: size,
          onPressed: onTrash,
        ),
      ],
    );
  }
}

class _PresenceDots extends StatelessWidget {
  const _PresenceDots({required this.presence});

  final List<CollaboratorPresence> presence;

  @override
  Widget build(BuildContext context) {
    if (presence.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final item in presence.take(4))
            Tooltip(
              message: item.userId,
              child: Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(left: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(context).colorScheme.surface, width: 2),
                ),
                alignment: Alignment.center,
                child: Text(item.userId.substring(0, 1).toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShareSheet extends ConsumerStatefulWidget {
  const _ShareSheet({required this.note});

  final PlainNote note;

  @override
  ConsumerState<_ShareSheet> createState() => _ShareSheetState();
}

class _ShareSheetState extends ConsumerState<_ShareSheet> {
  final _recipient = TextEditingController();
  List<ShareContact> _recentContacts = const [];
  List<ShareParticipant> _participants = const [];
  var _contactsLoading = true;
  var _accessLoading = true;
  var _role = 'editor';
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecentContacts());
    unawaited(_loadAccess());
  }

  @override
  void dispose() {
    _recipient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _CollaboratorInviteSheet(
      recipient: _recipient,
      role: _role,
      busy: _busy,
      error: _error,
      recentContacts: _recentContacts,
      contactsLoading: _contactsLoading,
      participants: _participants,
      accessLoading: _accessLoading,
      onRemoveAccess: _removeAccess,
      onContactSelected: _selectContact,
      onRoleChanged: (value) => setState(() => _role = value),
      onInvite: _busy ? null : _invite,
    );
  }

  Future<void> _loadRecentContacts() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) {
      if (mounted) setState(() => _contactsLoading = false);
      return;
    }
    try {
      final contacts = await ref
          .read(apiClientProvider)
          .fetchShareContacts(session.accessToken);
      if (mounted) {
        setState(() {
          _recentContacts = contacts;
          _contactsLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _contactsLoading = false);
    }
  }

  Future<void> _loadAccess() async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || widget.note.remoteId == null) {
      if (mounted) setState(() => _accessLoading = false);
      return;
    }
    try {
      final participants = await ref.read(apiClientProvider).fetchNoteSharing(
            accessToken: session.accessToken,
            noteId: widget.note.remoteId!,
          );
      if (mounted) {
        setState(() {
          _participants = participants;
          _accessLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _accessLoading = false);
    }
  }

  Future<void> _removeAccess(ShareParticipant participant) async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) return;
    await ref.read(apiClientProvider).removeShareAccess(
          accessToken: session.accessToken,
          participant: participant,
        );
    if (mounted) {
      setState(() => _participants =
          _participants.where((item) => item.id != participant.id).toList());
    }
    await ref.read(notesControllerProvider.notifier).pullRemote();
  }

  void _selectContact(ShareContact contact) {
    _recipient.text = contact.email;
    _recipient.selection =
        TextSelection.collapsed(offset: contact.email.length);
  }

  Future<void> _invite() async {
    if (_busy) return;
    final recipient = _recipient.text.trim();
    if (recipient.isEmpty) {
      setState(() => _error = ref.read(l10nProvider).t('recipientRequired'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final note =
          await ref.read(notesControllerProvider.notifier).ensureSynced(
                widget.note,
              );
      await ref.read(notesControllerProvider.notifier).inviteCollaborator(
            note: note,
            recipientUserId: recipient,
            role: _role,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) setState(() => _error = _friendlyInviteError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyInviteError(Object error) {
    final l10n = ref.read(l10nProvider);
    final text = error.toString();
    if (text.contains('No user found')) {
      return l10n.t('userNotFound');
    }
    if (text.contains('Only note owners')) {
      return l10n.t('ownerInviteOnly');
    }
    if (text.contains('recipient_user')) {
      return l10n.t('checkRecipient');
    }
    return l10n.t('inviteFailed');
  }
}

class _CollaboratorInviteSheet extends StatelessWidget {
  const _CollaboratorInviteSheet({
    required this.recipient,
    required this.role,
    required this.busy,
    required this.error,
    required this.recentContacts,
    required this.contactsLoading,
    required this.participants,
    required this.accessLoading,
    required this.onRemoveAccess,
    required this.onContactSelected,
    required this.onRoleChanged,
    required this.onInvite,
  });

  final TextEditingController recipient;
  final String role;
  final bool busy;
  final String? error;
  final List<ShareContact> recentContacts;
  final bool contactsLoading;
  final List<ShareParticipant> participants;
  final bool accessLoading;
  final ValueChanged<ShareParticipant> onRemoveAccess;
  final ValueChanged<ShareContact> onContactSelected;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n(Localizations.localeOf(context).languageCode);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Material(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(AppRadii.hero),
                clipBehavior: Clip.antiAlias,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 42,
                            height: 42,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(AppRadii.xl),
                            ),
                            child: Icon(
                              AppIcons.userPlus,
                              size: 20,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              l10n.t('collaboratorInvite'),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          AppIconButton(
                            tooltip: l10n.t('close'),
                            icon: AppIcons.x,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      if (accessLoading || participants.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        Text(
                          l10n.t('peopleWithAccess'),
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 6),
                        if (accessLoading)
                          const LinearProgressIndicator(minHeight: 2)
                        else
                          for (final participant in participants)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                participant.status == 'pending'
                                    ? AppIcons.mail
                                    : AppIcons.userRoundCheck,
                                size: 20,
                              ),
                              title: Text(participant.email),
                              subtitle: Text(participant.status == 'pending'
                                  ? l10n.t('invitationPending')
                                  : participant.role == 'editor'
                                      ? l10n.t('canEdit')
                                      : l10n.t('readOnly')),
                              trailing: AppIconButton(
                                tooltip: l10n.t('removeAccess'),
                                icon: AppIcons.userRoundX,
                                onPressed: () => onRemoveAccess(participant),
                              ),
                            ),
                      ],
                      const SizedBox(height: 18),
                      TextField(
                        controller: recipient,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: l10n.t('userIdOrEmail'),
                          prefixIcon: const Icon(AppIcons.atSign, size: 18),
                          filled: true,
                          fillColor: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadii.xl),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadii.xl),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(AppRadii.xl),
                            borderSide: BorderSide(color: scheme.primary),
                          ),
                        ),
                      ),
                      if (contactsLoading || recentContacts.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _RecentInviteContacts(
                          contacts: recentContacts,
                          loading: contactsLoading,
                          onSelected: onContactSelected,
                        ),
                      ],
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _InviteRoleTile(
                              selected: role == 'editor',
                              icon: AppIcons.edit3,
                              label: l10n.t('canEdit'),
                              onTap: () => onRoleChanged('editor'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _InviteRoleTile(
                              selected: role == 'viewer',
                              icon: AppIcons.eye,
                              label: l10n.t('readOnly'),
                              onTap: () => onRoleChanged('viewer'),
                            ),
                          ),
                        ],
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          error!,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: scheme.error),
                        ),
                      ],
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: onInvite,
                        icon: busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(AppIcons.send),
                        label: Text(
                          busy ? l10n.t('inviting') : l10n.t('invite'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentInviteContacts extends StatelessWidget {
  const _RecentInviteContacts({
    required this.contacts,
    required this.loading,
    required this.onSelected,
  });

  final List<ShareContact> contacts;
  final bool loading;
  final ValueChanged<ShareContact> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n(Localizations.localeOf(context).languageCode);
    final scheme = Theme.of(context).colorScheme;
    if (loading) {
      return Align(
        alignment: Alignment.centerLeft,
        child: SizedBox(
          height: 24,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l10n.t('contactsLoading'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final contact in contacts)
          ActionChip(
            avatar: Icon(
              contact.lastDirection == 'received'
                  ? AppIcons.mailOpen
                  : AppIcons.send,
              size: 15,
            ),
            label: Text(contact.email),
            tooltip: contact.lastDirection == 'received'
                ? l10n.t('invitedYouAlready')
                : l10n.t('alreadyInvited'),
            onPressed: () => onSelected(contact),
          ),
      ],
    );
  }
}

class _InviteRoleTile extends StatelessWidget {
  const _InviteRoleTile({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(AppRadii.xl),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected
              ? scheme.surfaceContainerHighest
              : scheme.surfaceContainerHighest.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(AppRadii.xl),
          border: Border.all(
            color: selected
                ? scheme.onSurface.withValues(alpha: 0.28)
                : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: scheme.onSurface),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
              ),
            ),
            AnimatedOpacity(
              opacity: selected ? 1 : 0,
              duration: const Duration(milliseconds: 120),
              child: Icon(AppIcons.check, size: 17, color: scheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}

class _FormatIntent extends Intent {
  const _FormatIntent(this.action);

  final String action;
}

class _HistoryIntent extends Intent {
  const _HistoryIntent({required this.redo});

  final bool redo;
}

class _EditorSnapshot {
  const _EditorSnapshot({
    required this.title,
    required this.checklist,
    required this.labels,
    required this.pinned,
    required this.color,
    required this.checklistMode,
    required this.reminderAt,
  });

  final TextEditingValue title;
  final List<ChecklistItem> checklist;
  final List<String> labels;
  final bool pinned;
  final int color;
  final bool checklistMode;
  final DateTime? reminderAt;

  bool hasSameContent(_EditorSnapshot other) {
    if (title.text != other.title.text ||
        pinned != other.pinned ||
        color != other.color ||
        checklistMode != other.checklistMode ||
        reminderAt != other.reminderAt ||
        checklist.length != other.checklist.length ||
        labels.length != other.labels.length) {
      return false;
    }
    for (var index = 0; index < labels.length; index += 1) {
      if (labels[index] != other.labels[index]) return false;
    }
    for (var index = 0; index < checklist.length; index += 1) {
      final left = checklist[index];
      final right = other.checklist[index];
      if (left.id != right.id ||
          left.text != right.text ||
          left.done != right.done ||
          left.indent != right.indent) {
        return false;
      }
    }
    return true;
  }
}

/// Inline label editor shown under the note title.
class _LabelEditorRow extends StatelessWidget {
  const _LabelEditorRow({
    required this.labels,
    required this.l10n,
    required this.onAdd,
    required this.onRemove,
  });

  final List<String> labels;
  final AppL10n l10n;
  final Future<void> Function() onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final label in labels)
            InputChip(
              key: ValueKey('note-label-$label'),
              label: Text(label),
              onDeleted: () => onRemove(label),
              deleteIcon: const Icon(AppIcons.close, size: 15),
              backgroundColor:
                  brandLavender.withValues(alpha: dark ? 0.20 : 0.16),
              side: BorderSide.none,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              labelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: dark ? brandLavender : const Color(0xff53407f),
                  ),
            ),
          ActionChip(
            key: const ValueKey('note-add-label'),
            avatar:
                Icon(AppIcons.plus, size: 15, color: scheme.onSurfaceVariant),
            label: Text(l10n.t('addLabel')),
            onPressed: () => unawaited(onAdd()),
            backgroundColor: dark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.04),
            side: BorderSide.none,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            labelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

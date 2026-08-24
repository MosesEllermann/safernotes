import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart' as quill;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
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
import 'package:safernotes_app/shared/widgets/animated_icon_button.dart';

class NoteEditorScreen extends StatelessWidget {
  const NoteEditorScreen({super.key, required this.note});

  final PlainNote note;

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: SafeArea(child: NoteEditorPanel(note: note)));
  }
}

class NoteEditorPanel extends ConsumerStatefulWidget {
  const NoteEditorPanel({
    super.key,
    required this.note,
    this.embedded = false,
  });

  final PlainNote note;
  final bool embedded;

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
  late StreamSubscription<quill.DocChange> _bodyChanges;
  late List<ChecklistItem> _checklist;
  late bool _pinned;
  late int _color;
  late bool _checklistMode;
  late DateTime? _reminderAt;
  late EditorHistory<_EditorSnapshot> _history;
  bool _restoringHistory = false;
  Timer? _autosave;

  static const _colors = [
    0xffffffff,
    0xfffef3c7,
    0xffdcfce7,
    0xffdbeafe,
    0xfffce7f3,
    0xffede9fe,
  ];

  @override
  void initState() {
    super.initState();
    _hydrate(widget.note);
  }

  @override
  void didUpdateWidget(covariant NoteEditorPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.note.localId != widget.note.localId) {
      _autosave?.cancel();
      _bodyChanges.cancel();
      _title.dispose();
      _body.dispose();
      _hydrate(widget.note);
    }
  }

  void _hydrate(PlainNote note) {
    _title = TextEditingController(
        text: note.title == 'Untitled note' ? '' : note.title);
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
    _color = note.color;
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final note = _draft();
    final surfaceColor = _color == 0xffffffff
        ? Theme.of(context).colorScheme.surfaceContainerLow
        : _noteColorFor(context, _color);
    final presence = ref
        .watch(presenceProvider)
        .where(
            (item) => item.noteId == note.remoteId && item.status == 'online')
        .toList();
    final bottomToolbar = MediaQuery.sizeOf(context).width < 700;
    final toolbar = _Toolbar(
      onFormat: _applyFormat,
      onBackground: _showBackgroundSheet,
      onUndo: _undo,
      onRedo: _redo,
      showFormatting: !_checklistMode,
      canUndo: _checklistMode ? _history.canUndo : _body.hasUndo,
      canRedo: _checklistMode ? _history.canRedo : _body.hasRedo,
      activeActions: _activeFormattingActions(),
    );
    final divider = Divider(
      height: 1,
      thickness: 1,
      color:
          Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.62),
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
          child: Material(
            color: surfaceColor,
            elevation: widget.embedded ? 0 : 4,
            shadowColor: Colors.black.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(widget.embedded ? 0 : 8),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
                  child: Row(
                    children: [
                      if (!widget.embedded)
                        AppIconButton(
                          tooltip: l10n.t('close'),
                          icon: LucideIcons.chevronLeft,
                          onPressed: () {
                            _saveNow();
                            Navigator.of(context).maybePop();
                          },
                        ),
                      Expanded(
                        child: TextField(
                          controller: _title,
                          decoration: _borderlessInput(l10n.t('title')),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      _PresenceDots(presence: presence),
                      AppIconButton(
                        tooltip: _pinned ? l10n.t('unpin') : l10n.t('pin'),
                        icon: _pinned ? LucideIcons.pin : LucideIcons.pinOff,
                        selected: _pinned,
                        onPressed: () => _recordMutation(
                          () => _pinned = !_pinned,
                          immediate: true,
                        ),
                      ),
                      if (_reminderAt == null)
                        AppIconButton(
                          tooltip: 'Mitarbeiter einladen',
                          icon: LucideIcons.userPlus,
                          onPressed: () => _showShareSheet(note),
                        ),
                      AppIconButton(
                        tooltip: 'Erinnerung',
                        icon: _reminderAt == null
                            ? LucideIcons.bell
                            : LucideIcons.bellRing,
                        selected: _reminderAt != null,
                        onPressed: () => _showReminderSheet(),
                      ),
                      AppIconButton(
                        tooltip: 'Archivieren',
                        icon: LucideIcons.archive,
                        onPressed: () => _changeNoteState('archived'),
                      ),
                      AppIconButton(
                        tooltip: 'Papierkorb',
                        icon: LucideIcons.trash,
                        onPressed: () => _changeNoteState('trashed'),
                      ),
                    ],
                  ),
                ),
                if (!bottomToolbar) ...[
                  toolbar,
                  divider,
                ],
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final editor = _BodyEditor(
                        controller: _body,
                        hint: l10n.t('writeNote'),
                      );
                      final checklist = _ChecklistEditor(
                        items: _checklist,
                        onChanged: (items) {
                          _recordMutation(
                            () => _checklist = orderChecklistItems(items),
                          );
                        },
                      );
                      return AnimatedSwitcher(
                        key: const ValueKey('editor-content'),
                        duration: const Duration(milliseconds: 160),
                        layoutBuilder: (currentChild, previousChildren) {
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
                                padding:
                                    const EdgeInsets.fromLTRB(20, 8, 20, 16),
                                child: checklist,
                              )
                            : Padding(
                                key: const ValueKey('body'),
                                padding:
                                    const EdgeInsets.fromLTRB(20, 6, 20, 10),
                                child: editor,
                              ),
                      );
                    },
                  ),
                ),
                if (bottomToolbar) ...[
                  divider,
                  toolbar,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  PlainNote _draft() {
    return _currentNote().copyWith(
      title: _title.text.trim().isEmpty ? 'Untitled note' : _title.text.trim(),
      body: _checklistMode ? '' : documentPlainText(_body.document),
      richTextDelta: _checklistMode
          ? null
          : _body.document.toDelta().toJson().cast<Map<String, dynamic>>(),
      clearRichTextDelta: _checklistMode,
      checklist: _checklist,
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
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Geteilte Notiz'),
          content: const Text(
            'Erinnerungen sind lokal und können nicht mit Mitarbeitern geteilt werden. Du kannst abbrechen oder eine persönliche Kopie als Erinnerung erstellen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Abbrechen'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Als Erinnerung duplizieren'),
            ),
          ],
        );
      },
    );
  }

  void _showReminderFeedback(bool added, {bool duplicated = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          added
              ? duplicated
                  ? 'Eine persönliche Kopie wird jetzt unter Erinnerungen angezeigt.'
                  : 'Die Notiz wird jetzt unter Erinnerungen angezeigt.'
              : 'Die Erinnerung wurde entfernt.',
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.onFormat,
    required this.onBackground,
    required this.onUndo,
    required this.onRedo,
    required this.showFormatting,
    required this.canUndo,
    required this.canRedo,
    required this.activeActions,
  });

  final ValueChanged<String> onFormat;
  final VoidCallback onBackground;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final bool showFormatting;
  final bool canUndo;
  final bool canRedo;
  final Set<String> activeActions;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      const _ToolbarItem('bold', LucideIcons.bold, 'Fett'),
      const _ToolbarItem('italic', LucideIcons.italic, 'Kursiv'),
      const _ToolbarItem('strike', LucideIcons.strikethrough, 'Durchstreichen'),
      const _ToolbarItem('link', LucideIcons.link, 'Link'),
      const _ToolbarItem('codeblock', LucideIcons.squareCode, 'Codeblock'),
      const _ToolbarItem('check', LucideIcons.squareCheck, 'Checkliste'),
      const _ToolbarItem(
          'clear', LucideIcons.removeFormatting, 'Formatierung löschen'),
    ];
    return Material(
      color: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    AppIconButton(
                      tooltip: 'Rückgängig',
                      icon: LucideIcons.undo2,
                      onPressed: canUndo ? onUndo : null,
                    ),
                    AppIconButton(
                      tooltip: 'Wiederholen',
                      icon: LucideIcons.redo2,
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
              tooltip: 'Hintergrund',
              icon: LucideIcons.palette,
              onPressed: onBackground,
            ),
          ],
        ),
      ),
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
                borderRadius: BorderRadius.circular(24),
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
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              LucideIcons.link,
                              size: 20,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Link',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          AppIconButton(
                            tooltip: 'Schließen',
                            icon: LucideIcons.x,
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
                          labelText: 'Text',
                          prefixIcon: const Icon(LucideIcons.type, size: 18),
                          filled: true,
                          fillColor: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.42),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
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
                          labelText: 'URL',
                          prefixIcon: const Icon(LucideIcons.globe, size: 18),
                          filled: true,
                          fillColor: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.42),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
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
                        icon: const Icon(LucideIcons.check),
                        label: const Text('Speichern'),
                      ),
                      if (widget.canRemove) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => Navigator.of(context).pop(_LinkEdit(
                            label: _label.text.trim(),
                            url: _url.text.trim(),
                            remove: true,
                          )),
                          icon: const Icon(LucideIcons.unlink),
                          label: const Text('Link entfernen'),
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
                borderRadius: BorderRadius.circular(24),
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
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              LucideIcons.palette,
                              size: 20,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Hintergrund',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          AppIconButton(
                            tooltip: 'Schließen',
                            icon: LucideIcons.x,
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
                          _BackgroundImageTile(
                            onSelected: () {},
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
      borderRadius: BorderRadius.circular(16),
      onTap: onSelected,
      child: Container(
        width: 64,
        height: 56,
        decoration: BoxDecoration(
          color: Color(color),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: selected
            ? Icon(LucideIcons.check, size: 18, color: scheme.onSurface)
            : null,
      ),
    );
  }
}

class _BackgroundImageTile extends StatelessWidget {
  const _BackgroundImageTile({required this.onSelected});

  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onSelected,
      child: Container(
        width: 112,
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.image, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Text(
              'Bild',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
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
                borderRadius: BorderRadius.circular(24),
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
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              LucideIcons.bell,
                              size: 20,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Erinnerung',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          AppIconButton(
                            tooltip: 'Schließen',
                            icon: LucideIcons.x,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      _EditorReminderPickTile(
                        icon: LucideIcons.calendar,
                        label: 'Datum',
                        value:
                            '${_selected.day.toString().padLeft(2, '0')}.${_selected.month.toString().padLeft(2, '0')}.${_selected.year}',
                        onTap: _pickDate,
                      ),
                      const SizedBox(height: 10),
                      _EditorReminderPickTile(
                        icon: LucideIcons.clock3,
                        label: 'Uhrzeit',
                        value:
                            '${_selected.hour.toString().padLeft(2, '0')}:${_selected.minute.toString().padLeft(2, '0')}',
                        onTap: _pickTime,
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(context)
                            .pop(_ReminderSelection(_selected.toUtc())),
                        icon: const Icon(LucideIcons.bellRing),
                        label: const Text('Erinnerung setzen'),
                      ),
                      if (widget.reminderAt != null) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => Navigator.of(context)
                              .pop(const _ReminderSelection(null)),
                          icon: const Icon(LucideIcons.bellOff),
                          label: const Text('Erinnerung entfernen'),
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
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
          borderRadius: BorderRadius.circular(14),
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
  const _BodyEditor({required this.controller, required this.hint});

  final quill.QuillController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return quill.QuillEditor.basic(
      controller: controller,
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
  });

  final List<ChecklistItem> items;
  final ValueChanged<List<ChecklistItem>> onChanged;

  @override
  ConsumerState<_ChecklistEditor> createState() => _ChecklistEditorState();
}

class _ChecklistEditorState extends ConsumerState<_ChecklistEditor> {
  String? _focusItemId;

  static const _rowHeight = 46.0;
  static const _addHeight = 44.0;
  static const _completedHeaderHeight = 38.0;

  @override
  Widget build(BuildContext context) {
    final unchecked = widget.items.where((item) => !item.done).toList();
    final checked = widget.items.where((item) => item.done).toList();
    return SingleChildScrollView(
      child: _buildAnimatedItems(context, unchecked, checked),
    );
  }

  Widget _buildAnimatedItems(
    BuildContext context,
    List<ChecklistItem> unchecked,
    List<ChecklistItem> checked,
  ) {
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
                child: _ChecklistRow(
                  key: ValueKey(item.id),
                  item: item,
                  autofocus: item.id == _focusItemId,
                  onChanged: (updated) => widget.onChanged(
                    updateChecklistItem(widget.items, updated),
                  ),
                  onDelete: () => widget.onChanged(
                    widget.items
                        .where((candidate) => candidate.id != item.id)
                        .toList(),
                  ),
                  onInsertAfter: () => _insertItem(after: item),
                  onFocused: () {
                    if (_focusItemId == item.id) {
                      setState(() => _focusItemId = null);
                    }
                  },
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
                label: ref.watch(l10nProvider).t('addTask'),
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
            LucideIcons.plus,
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
    required this.autofocus,
    required this.onChanged,
    required this.onDelete,
    required this.onInsertAfter,
    required this.onFocused,
  });

  final ChecklistItem item;
  final bool autofocus;
  final ValueChanged<ChecklistItem> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onInsertAfter;
  final VoidCallback onFocused;

  @override
  State<_ChecklistRow> createState() => _ChecklistRowState();
}

class _ChecklistRowState extends State<_ChecklistRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.item.text,
  )..selection = TextSelection.collapsed(offset: widget.item.text.length);

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: widget.item.indent * 18.0, bottom: 4),
      child: Row(
        children: [
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
              onTap: widget.onFocused,
            ),
          ),
          AppIconButton(
            tooltip: 'Delete',
            icon: LucideIcons.x,
            onPressed: widget.onDelete,
          ),
        ],
      ),
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
  var _contactsLoading = true;
  var _role = 'editor';
  var _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRecentContacts());
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

  void _selectContact(ShareContact contact) {
    _recipient.text = contact.email;
    _recipient.selection =
        TextSelection.collapsed(offset: contact.email.length);
  }

  Future<void> _invite() async {
    final recipient = _recipient.text.trim();
    if (recipient.isEmpty) {
      setState(() => _error = 'Bitte gib eine E-Mail oder User-ID ein.');
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
      setState(() => _error = _friendlyInviteError(error));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _friendlyInviteError(Object error) {
    final text = error.toString();
    if (text.contains('No user found')) {
      return 'Kein Nutzer mit dieser E-Mail oder User-ID gefunden.';
    }
    if (text.contains('Only note owners')) {
      return 'Nur Besitzer dieser Notiz können Mitarbeiter einladen.';
    }
    if (text.contains('recipient_user')) {
      return 'Bitte prüfe die E-Mail oder User-ID.';
    }
    return 'Einladen ist fehlgeschlagen. Bitte versuche es erneut.';
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
  final ValueChanged<ShareContact> onContactSelected;
  final ValueChanged<String> onRoleChanged;
  final VoidCallback? onInvite;

  @override
  Widget build(BuildContext context) {
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
                borderRadius: BorderRadius.circular(24),
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
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(
                              LucideIcons.userPlus,
                              size: 20,
                              color: scheme.onSurface,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Mitarbeiter einladen',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                          ),
                          AppIconButton(
                            tooltip: 'Schließen',
                            icon: LucideIcons.x,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      TextField(
                        controller: recipient,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'User ID oder E-Mail',
                          prefixIcon: const Icon(LucideIcons.atSign, size: 18),
                          filled: true,
                          fillColor: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.5),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
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
                              icon: LucideIcons.edit3,
                              label: 'Bearbeiten',
                              onTap: () => onRoleChanged('editor'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _InviteRoleTile(
                              selected: role == 'viewer',
                              icon: LucideIcons.eye,
                              label: 'Nur lesen',
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
                            : const Icon(LucideIcons.send),
                        label: Text(busy ? 'Wird eingeladen' : 'Einladen'),
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
                'Kontakte laden',
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
                  ? LucideIcons.mailOpen
                  : LucideIcons.send,
              size: 15,
            ),
            label: Text(contact.email),
            tooltip: contact.lastDirection == 'received'
                ? 'Hat dich schon eingeladen'
                : 'Schon eingeladen',
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
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: selected
              ? scheme.surfaceContainerHighest
              : scheme.surfaceContainerHighest.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(14),
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
              child: Icon(LucideIcons.check, size: 17, color: scheme.onSurface),
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
    required this.pinned,
    required this.color,
    required this.checklistMode,
    required this.reminderAt,
  });

  final TextEditingValue title;
  final List<ChecklistItem> checklist;
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
        checklist.length != other.checklist.length) {
      return false;
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

Color _noteColorFor(BuildContext context, int color) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (!dark) return Color(color);
  return switch (color) {
    0xfffef3c7 => const Color(0xff3a2f13),
    0xffdcfce7 => const Color(0xff173322),
    0xffdbeafe => const Color(0xff173344),
    0xfffce7f3 => const Color(0xff3a1830),
    0xffede9fe => const Color(0xff2b2146),
    _ => Theme.of(context).colorScheme.surfaceContainerLow,
  };
}

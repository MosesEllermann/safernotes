import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:uuid/uuid.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
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
  late _MarkdownEditingController _body;
  late List<ChecklistItem> _checklist;
  late bool _pinned;
  late int _color;
  late bool _checklistMode;
  late DateTime? _reminderAt;
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
    if (oldWidget.note.localId != widget.note.localId ||
        oldWidget.note.updatedAt != widget.note.updatedAt) {
      _autosave?.cancel();
      _title.dispose();
      _body.dispose();
      _hydrate(widget.note);
    }
  }

  void _hydrate(PlainNote note) {
    _title = TextEditingController(
        text: note.title == 'Untitled note' ? '' : note.title);
    _body = _MarkdownEditingController(text: note.body);
    _checklist = [...note.checklist];
    _checklistMode = note.checklist.isNotEmpty && note.body.trim().isEmpty;
    _pinned = note.pinned;
    _color = note.color;
    _reminderAt = note.reminderAt;
    _title.addListener(_scheduleSave);
    _body.addListener(_scheduleSave);
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final note = _draft();
    final surfaceColor = _color == 0xffffffff
        ? Theme.of(context).colorScheme.surface
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
      },
      child: Actions(
        actions: {
          _FormatIntent: CallbackAction<_FormatIntent>(onInvoke: (intent) {
            _applyFormat(intent.action);
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
                        onPressed: () {
                          setState(() => _pinned = !_pinned);
                          _scheduleSave(immediate: true);
                        },
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
                          setState(() => _checklist = items);
                          _scheduleSave();
                        },
                      );
                      return AnimatedSwitcher(
                        duration: const Duration(milliseconds: 160),
                        child: _checklistMode
                            ? Padding(
                                key: const ValueKey('checklist'),
                                padding:
                                    const EdgeInsets.fromLTRB(20, 10, 20, 16),
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
      body: _checklistMode ? '' : _body.text,
      checklist: _checklist,
      pinned: _pinned,
      color: _color,
      reminderAt: _reminderAt,
      clearReminder: _reminderAt == null,
    );
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
    final selection = _body.selection;
    final text = _body.text;
    if (action == 'link') {
      unawaited(_showLinkSheet());
      return;
    }
    if (action == 'codeblock') {
      _applyCodeBlock();
      return;
    }
    if (action == 'check') {
      final range = _safeSelectionRange(selection, text);
      final selected = range.isCollapsed ? '' : range.textInside(text);
      final replacement = _switchToChecklist(selected);
      _body.value = TextEditingValue(
        text: text.replaceRange(range.start, range.end, replacement),
        selection: TextSelection.collapsed(offset: range.start),
      );
      _scheduleSave();
      return;
    }

    final range = action == 'clear'
        ? _rangeForClear(selection, text)
        : _rangeForInlineFormat(selection, text);
    if (range == null) return;
    final selected = range.textInside(text);
    if (selected.trim().isEmpty) return;
    final edit = switch (action) {
      'bold' => _inlineMarkdownEdit(text, range, '**'),
      'italic' => _inlineMarkdownEdit(text, range, '_'),
      'strike' => _inlineMarkdownEdit(text, range, '~~'),
      'clear' =>
        _TextEdit(range: range, replacement: _clearMarkdownSyntax(selected)),
      _ => _TextEdit(range: range, replacement: selected),
    };
    _body.value = TextEditingValue(
      text:
          text.replaceRange(edit.range.start, edit.range.end, edit.replacement),
      selection: TextSelection.collapsed(
          offset: edit.range.start + edit.replacement.length),
    );
    _scheduleSave();
  }

  void _applyCodeBlock() {
    final text = _body.text;
    final range = _safeSelectionRange(_body.selection, text);
    final selected = range.isCollapsed ? '' : range.textInside(text);
    final replacement =
        selected.trim().isEmpty ? '```\n\n```' : '```\n$selected\n```';
    final caretOffset = selected.trim().isEmpty
        ? range.start + 4
        : range.start + replacement.length;
    _body.value = TextEditingValue(
      text: text.replaceRange(range.start, range.end, replacement),
      selection: TextSelection.collapsed(offset: caretOffset),
    );
    _scheduleSave();
  }

  Future<void> _showLinkSheet() async {
    final text = _body.text;
    final selection = _body.selection;
    final link = _linkAroundSelection(selection, text);
    final fallbackRange = _rangeForInlineFormat(selection, text) ??
        _safeSelectionRange(selection, text);
    final editRange = link?.range ?? fallbackRange;
    final selected = editRange.isCollapsed ? '' : editRange.textInside(text);
    final initialLabel = link?.label ?? selected;
    final initialUrl = link?.url ?? '';
    final result = await showModalBottomSheet<_LinkEdit>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LinkSheet(
        initialLabel: initialLabel,
        initialUrl: initialUrl,
        canRemove: link != null,
      ),
    );
    if (result == null || !mounted) return;
    final replacement = result.remove
        ? result.label
        : '[${result.label}](${_normalizeUrl(result.url)})';
    _body.value = TextEditingValue(
      text: text.replaceRange(editRange.start, editRange.end, replacement),
      selection:
          TextSelection.collapsed(offset: editRange.start + replacement.length),
    );
    _scheduleSave();
  }

  _ExistingLink? _linkAroundSelection(TextSelection selection, String text) {
    final range = _safeSelectionRange(selection, text);
    final expression = RegExp(r'\[([^\]]*)\]\(([^)]*)\)');
    for (final match in expression.allMatches(text)) {
      final touchesCollapsed = range.isCollapsed &&
          range.start >= match.start &&
          range.start <= match.end;
      final overlapsSelection = !range.isCollapsed &&
          range.start < match.end &&
          range.end > match.start;
      if (touchesCollapsed || overlapsSelection) {
        return _ExistingLink(
          range: TextRange(start: match.start, end: match.end),
          label: match.group(1) ?? '',
          url: match.group(2) ?? '',
        );
      }
    }
    return null;
  }

  String _normalizeUrl(String value) {
    final trimmed = value.trim();
    if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:').hasMatch(trimmed)) {
      return trimmed;
    }
    return 'https://$trimmed';
  }

  TextRange _safeSelectionRange(TextSelection selection, String text) {
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    return TextRange(start: start, end: end);
  }

  TextRange? _rangeForInlineFormat(TextSelection selection, String text) {
    final range = _safeSelectionRange(selection, text);
    if (!range.isCollapsed) return range;
    return _wordRangeAt(text, range.start);
  }

  TextRange? _rangeForClear(TextSelection selection, String text) {
    final range = _safeSelectionRange(selection, text);
    if (!range.isCollapsed) return range;
    if (text.trim().isEmpty) return null;
    return _lineRangeAt(text, range.start);
  }

  TextRange? _wordRangeAt(String text, int offset) {
    if (text.isEmpty) return null;
    var start = offset.clamp(0, text.length);
    var end = start;
    while (start > 0 && _isWordCharacter(text.codeUnitAt(start - 1))) {
      start--;
    }
    while (end < text.length && _isWordCharacter(text.codeUnitAt(end))) {
      end++;
    }
    if (start == end) return null;
    return TextRange(start: start, end: end);
  }

  TextRange _lineRangeAt(String text, int offset) {
    final safeOffset = offset.clamp(0, text.length);
    final lineStart =
        text.lastIndexOf('\n', safeOffset == 0 ? 0 : safeOffset - 1) + 1;
    final nextBreak = text.indexOf('\n', safeOffset);
    final lineEnd = nextBreak == -1 ? text.length : nextBreak;
    return TextRange(start: lineStart, end: lineEnd);
  }

  bool _isWordCharacter(int codeUnit) {
    return (codeUnit >= 48 && codeUnit <= 57) ||
        (codeUnit >= 65 && codeUnit <= 90) ||
        (codeUnit >= 97 && codeUnit <= 122) ||
        codeUnit == 45 ||
        codeUnit == 95 ||
        codeUnit >= 128;
  }

  _TextEdit _inlineMarkdownEdit(String text, TextRange range, String marker) {
    final beforeStart = range.start - marker.length;
    final afterEnd = range.end + marker.length;
    final hasWrappingMarkers = beforeStart >= 0 &&
        afterEnd <= text.length &&
        text.substring(beforeStart, range.start) == marker &&
        text.substring(range.end, afterEnd) == marker;
    if (hasWrappingMarkers) {
      return _TextEdit(
        range: TextRange(start: beforeStart, end: afterEnd),
        replacement: range.textInside(text),
      );
    }
    return _TextEdit(
      range: range,
      replacement: '$marker${range.textInside(text)}$marker',
    );
  }

  String _clearMarkdownSyntax(String value) {
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
    setState(() => _color = color);
    _scheduleSave(immediate: true);
  }

  String _switchToChecklist(String selected) {
    final lines = selected.trim().isEmpty ? [''] : selected.split('\n');
    setState(() {
      _checklistMode = true;
      _checklist = [
        ..._checklist,
        ...lines.map((line) => ChecklistItem(
            id: _uuid.v4(),
            text: line.replaceFirst(RegExp(r'^[-*]\s*'), ''),
            done: false,
            indent: 0)),
      ];
    });
    return '';
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
    setState(() => _reminderAt = selected);
    _scheduleSave(immediate: true);
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
  });

  final ValueChanged<String> onFormat;
  final VoidCallback onBackground;

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
                    for (final item in buttons)
                      AppIconButton(
                        tooltip: item.tooltip,
                        icon: item.icon,
                        onPressed: () => onFormat(item.action),
                      ),
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

class _ExistingLink {
  const _ExistingLink({
    required this.range,
    required this.label,
    required this.url,
  });

  final TextRange range;
  final String label;
  final String url;
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

  final _MarkdownEditingController controller;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      expands: true,
      minLines: null,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      textAlignVertical: TextAlignVertical.top,
      decoration: _borderlessInput(hint),
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
    );
  }
}

class _MarkdownEditingController extends TextEditingController {
  _MarkdownEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final base = style ?? DefaultTextStyle.of(context).style;
    final spans = <InlineSpan>[];
    var inCodeBlock = false;
    for (final line in text.split('\n')) {
      if (line.trim() == '```') {
        spans.add(TextSpan(text: line, style: _hiddenStyle(base)));
        inCodeBlock = !inCodeBlock;
      } else {
        spans.addAll(
          _lineSpans(context, base, line, inCodeBlock: inCodeBlock),
        );
      }
      spans.add(const TextSpan(text: '\n'));
    }
    if (spans.isNotEmpty) spans.removeLast();
    return TextSpan(style: base, children: spans);
  }

  TextStyle _hiddenStyle(TextStyle base) {
    return base.copyWith(
        color: Colors.transparent, fontSize: 0.01, height: 0.01);
  }

  List<TextSpan> _lineSpans(
    BuildContext context,
    TextStyle base,
    String line, {
    required bool inCodeBlock,
  }) {
    final hiddenStyle = _hiddenStyle(base);
    if (inCodeBlock) {
      return [
        TextSpan(
          text: line,
          style: base.copyWith(
            fontFamily: 'monospace',
            backgroundColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.58),
          ),
        ),
      ];
    }
    var index = 0;
    var lineStyle = base;
    if (line.startsWith('# ')) {
      lineStyle = base.copyWith(fontSize: 28, fontWeight: FontWeight.w700);
      index = 2;
    } else if (line.startsWith('## ')) {
      lineStyle = base.copyWith(fontSize: 23, fontWeight: FontWeight.w700);
      index = 3;
    } else if (line.startsWith('### ')) {
      lineStyle = base.copyWith(fontSize: 19, fontWeight: FontWeight.w700);
      index = 4;
    } else if (line.startsWith('> ')) {
      lineStyle = base.copyWith(
        fontStyle: FontStyle.italic,
        color: base.color?.withValues(alpha: 0.72),
      );
      index = 2;
    }

    final spans = <TextSpan>[];
    if (index > 0) {
      spans.add(TextSpan(text: line.substring(0, index), style: hiddenStyle));
    }

    var bold = false;
    var italic = false;
    var strike = false;
    var underline = false;
    var code = false;
    while (index < line.length) {
      if (line.startsWith('**', index)) {
        spans.add(TextSpan(text: '**', style: hiddenStyle));
        bold = !bold;
        index += 2;
        continue;
      }
      if (line.startsWith('~~', index)) {
        spans.add(TextSpan(text: '~~', style: hiddenStyle));
        strike = !strike;
        index += 2;
        continue;
      }
      if (line.startsWith('<u>', index)) {
        spans.add(TextSpan(text: '<u>', style: hiddenStyle));
        underline = true;
        index += 3;
        continue;
      }
      if (line.startsWith('</u>', index)) {
        spans.add(TextSpan(text: '</u>', style: hiddenStyle));
        underline = false;
        index += 4;
        continue;
      }
      if (line.startsWith('```', index)) {
        spans.add(TextSpan(text: '```', style: hiddenStyle));
        code = !code;
        index += 3;
        continue;
      }
      if (line.startsWith('`', index)) {
        spans.add(TextSpan(text: '`', style: hiddenStyle));
        code = !code;
        index += 1;
        continue;
      }
      if (_isItalicMarker(line, index)) {
        spans.add(TextSpan(text: '_', style: hiddenStyle));
        italic = !italic;
        index += 1;
        continue;
      }
      final link = _markdownLinkAt(line, index);
      if (link != null) {
        spans
          ..add(TextSpan(text: '[', style: hiddenStyle))
          ..add(TextSpan(
            text: link.label,
            style: _inlineStyle(
              context,
              lineStyle,
              bold: bold,
              italic: italic,
              strike: strike,
              underline: true,
              code: code,
              link: true,
            ),
          ))
          ..add(TextSpan(text: '](${link.url})', style: hiddenStyle));
        index = link.end;
        continue;
      }

      final next = _nextMarkdownBoundary(line, index);
      spans.add(TextSpan(
        text: line.substring(index, next),
        style: _inlineStyle(
          context,
          lineStyle,
          bold: bold,
          italic: italic,
          strike: strike,
          underline: underline,
          code: code,
        ),
      ));
      index = next;
    }
    return spans;
  }

  TextStyle _inlineStyle(
    BuildContext context,
    TextStyle base, {
    required bool bold,
    required bool italic,
    required bool strike,
    required bool underline,
    required bool code,
    bool link = false,
  }) {
    final decorations = <TextDecoration>[
      if (strike) TextDecoration.lineThrough,
      if (underline || link) TextDecoration.underline,
    ];
    return base.copyWith(
      backgroundColor: link
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
          : base.backgroundColor,
      color: link ? Theme.of(context).colorScheme.primary : base.color,
      fontWeight: bold ? FontWeight.w700 : base.fontWeight,
      fontStyle: italic ? FontStyle.italic : base.fontStyle,
      fontFamily: code ? 'monospace' : base.fontFamily,
      decoration: decorations.isEmpty
          ? base.decoration
          : TextDecoration.combine(decorations),
    );
  }

  int _nextMarkdownBoundary(String line, int start) {
    for (var i = start + 1; i < line.length; i++) {
      if (line.startsWith('**', i) ||
          line.startsWith('~~', i) ||
          line.startsWith('<u>', i) ||
          line.startsWith('</u>', i) ||
          line.startsWith('```', i) ||
          line.startsWith('`', i) ||
          line.startsWith('[', i) ||
          _isItalicMarker(line, i)) {
        return i;
      }
    }
    return line.length;
  }

  bool _isItalicMarker(String line, int index) {
    if (!line.startsWith('_', index)) return false;
    final beforeIsWord =
        index > 0 && _isInlineWordCharacter(line.codeUnitAt(index - 1));
    final afterIsWord = index + 1 < line.length &&
        _isInlineWordCharacter(line.codeUnitAt(index + 1));
    return beforeIsWord != afterIsWord;
  }

  bool _isInlineWordCharacter(int codeUnit) {
    return (codeUnit >= 48 && codeUnit <= 57) ||
        (codeUnit >= 65 && codeUnit <= 90) ||
        (codeUnit >= 97 && codeUnit <= 122) ||
        codeUnit >= 128;
  }

  _MarkdownLink? _markdownLinkAt(String line, int index) {
    if (!line.startsWith('[', index)) return null;
    final labelEnd = line.indexOf('](', index + 1);
    if (labelEnd == -1) return null;
    final urlEnd = line.indexOf(')', labelEnd + 2);
    if (urlEnd == -1) return null;
    return _MarkdownLink(
      label: line.substring(index + 1, labelEnd),
      url: line.substring(labelEnd + 2, urlEnd),
      end: urlEnd + 1,
    );
  }
}

class _MarkdownLink {
  const _MarkdownLink({
    required this.label,
    required this.url,
    required this.end,
  });

  final String label;
  final String url;
  final int end;
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

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.t('checklist'),
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            AppIconButton(
              tooltip: l10n.t('addTask'),
              icon: LucideIcons.plus,
              onPressed: () {
                final item = ChecklistItem(
                    id: const Uuid().v4(), text: '', done: false, indent: 0);
                setState(() => _focusItemId = item.id);
                widget.onChanged([...widget.items, item]);
              },
            ),
          ],
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: widget.items.length,
          onReorderItem: (oldIndex, newIndex) {
            final next = [...widget.items];
            final item = next.removeAt(oldIndex);
            next.insert(newIndex, item);
            widget.onChanged(next);
          },
          itemBuilder: (context, index) {
            final item = widget.items[index];
            return _ChecklistRow(
              key: ValueKey(item.id),
              index: index,
              item: item,
              autofocus: item.id == _focusItemId,
              onChanged: (updated) {
                final next = [...widget.items]..[index] = updated;
                widget.onChanged(next);
              },
              onDelete: () {
                final next = [...widget.items]..removeAt(index);
                widget.onChanged(next);
              },
              onInsertAfter: () {
                final next = [...widget.items];
                final inserted = ChecklistItem(
                  id: const Uuid().v4(),
                  text: '',
                  done: false,
                  indent: item.indent,
                );
                next.insert(
                  index + 1,
                  inserted,
                );
                setState(() => _focusItemId = inserted.id);
                widget.onChanged(next);
              },
              onFocused: () {
                if (_focusItemId == item.id) {
                  setState(() => _focusItemId = null);
                }
              },
            );
          },
        ),
      ],
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  const _ChecklistRow({
    super.key,
    required this.index,
    required this.item,
    required this.autofocus,
    required this.onChanged,
    required this.onDelete,
    required this.onInsertAfter,
    required this.onFocused,
  });

  final int index;
  final ChecklistItem item;
  final bool autofocus;
  final ValueChanged<ChecklistItem> onChanged;
  final VoidCallback onDelete;
  final VoidCallback onInsertAfter;
  final VoidCallback onFocused;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: item.indent * 20.0, bottom: 6),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Icon(
              LucideIcons.gripVertical,
              size: 16,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Checkbox(
            visualDensity: VisualDensity.compact,
            value: item.done,
            onChanged: (value) =>
                onChanged(item.copyWith(done: value ?? false)),
          ),
          Expanded(
            child: TextField(
              autofocus: autofocus,
              controller: TextEditingController(text: item.text)
                ..selection = TextSelection.collapsed(offset: item.text.length),
              decoration: _borderlessInput('Task'),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    decoration: item.done ? TextDecoration.lineThrough : null,
                    color: item.done
                        ? Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.56)
                        : null,
                  ),
              onChanged: (value) => onChanged(item.copyWith(text: value)),
              onSubmitted: (_) => onInsertAfter(),
              onTap: onFocused,
            ),
          ),
          AppIconButton(
            tooltip: 'Outdent',
            icon: LucideIcons.outdent,
            onPressed: item.indent == 0
                ? null
                : () => onChanged(item.copyWith(indent: item.indent - 1)),
          ),
          AppIconButton(
            tooltip: 'Indent',
            icon: LucideIcons.indent,
            onPressed: () => onChanged(item.copyWith(
                indent: item.indent + 1 > 4 ? 4 : item.indent + 1)),
          ),
          AppIconButton(
            tooltip: 'Delete',
            icon: LucideIcons.trash,
            onPressed: onDelete,
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

class _TextEdit {
  const _TextEdit({required this.range, required this.replacement});

  final TextRange range;
  final String replacement;
}

Color _noteColorFor(BuildContext context, int color) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  if (!dark) return Color(color);
  return switch (color) {
    0xfffef3c7 => const Color(0xff3a2f13),
    0xffdcfce7 => const Color(0xff173322),
    0xffdbeafe => const Color(0xff142943),
    0xfffce7f3 => const Color(0xff3a1830),
    0xffede9fe => const Color(0xff2b2146),
    _ => Theme.of(context).colorScheme.surface,
  };
}

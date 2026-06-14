import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import 'package:zknotes_app/features/notes/notes_controller.dart';
import 'package:zknotes_app/shared/app/app_l10n.dart';
import 'package:zknotes_app/shared/models/note.dart';
import 'package:zknotes_app/shared/widgets/animated_icon_button.dart';

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

class _NoteEditorPanelState extends ConsumerState<NoteEditorPanel> {
  final _uuid = const Uuid();
  late TextEditingController _title;
  late _MarkdownEditingController _body;
  late List<ChecklistItem> _checklist;
  late bool _pinned;
  late int _color;
  late bool _checklistMode;
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
        .where((item) =>
            item.noteId == widget.note.remoteId && item.status == 'online')
        .toList();

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
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyU):
            const _FormatIntent('underline'),
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyU):
            const _FormatIntent('underline'),
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
                          icon: Icons.close,
                          onPressed: () {
                            _saveNow();
                            Navigator.of(context).maybePop();
                          },
                        ),
                      Expanded(
                        child: TextField(
                          controller: _title,
                          decoration: InputDecoration.collapsed(
                              hintText: l10n.t('title')),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      _PresenceDots(presence: presence),
                      AppIconButton(
                        tooltip: _pinned ? l10n.t('unpin') : l10n.t('pin'),
                        icon:
                            _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                        selected: _pinned,
                        onPressed: () {
                          setState(() => _pinned = !_pinned);
                          _scheduleSave(immediate: true);
                        },
                      ),
                      AppIconButton(
                        tooltip: l10n.t('share'),
                        icon: Icons.ios_share,
                        onPressed: note.remoteId == null
                            ? null
                            : () => _showShareSheet(note),
                      ),
                    ],
                  ),
                ),
                _Toolbar(
                  onFormat: _applyFormat,
                  onColor: (value) {
                    setState(() => _color = value);
                    _scheduleSave(immediate: true);
                  },
                  selectedColor: _color,
                  colors: _colors,
                ),
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
                                    const EdgeInsets.fromLTRB(20, 0, 20, 16),
                                child: checklist,
                              )
                            : Padding(
                                key: const ValueKey('body'),
                                padding:
                                    const EdgeInsets.fromLTRB(20, 0, 20, 16),
                                child: editor,
                              ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  PlainNote _draft() {
    return widget.note.copyWith(
      title: _title.text.trim().isEmpty ? 'Untitled note' : _title.text.trim(),
      body: _checklistMode ? '' : _body.text,
      checklist: _checklist,
      pinned: _pinned,
      color: _color,
    );
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

  void _applyFormat(String action) {
    final selection = _body.selection;
    final text = _body.text;
    final start = selection.start < 0 ? text.length : selection.start;
    final end = selection.end < 0 ? text.length : selection.end;
    final selected = start == end ? '' : text.substring(start, end);
    final replacement = switch (action) {
      'bold' => '**$selected**',
      'italic' => '_${selected}_',
      'underline' => '<u>$selected</u>',
      'strike' => '~~$selected~~',
      'h1' => '# $selected',
      'h2' => '## $selected',
      'h3' => '### $selected',
      'code' => '`$selected`',
      'codeblock' => '```\n$selected\n```',
      'quote' => '> $selected',
      'link' => '[$selected](https://)',
      'clear' => selected.replaceAll(
          RegExp(r'(\*\*|__|~~|`|<u>|</u>|^#{1,3}\s|^>\s)', multiLine: true),
          ''),
      'check' => _switchToChecklist(selected),
      _ => selected,
    };
    _body.value = TextEditingValue(
      text: text.replaceRange(start, end, replacement),
      selection: TextSelection.collapsed(offset: start + replacement.length),
    );
    _scheduleSave();
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
      showDragHandle: true,
      builder: (_) => _ShareSheet(note: note),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.onFormat,
    required this.onColor,
    required this.selectedColor,
    required this.colors,
  });

  final ValueChanged<String> onFormat;
  final ValueChanged<int> onColor;
  final int selectedColor;
  final List<int> colors;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      ('bold', Icons.format_bold),
      ('italic', Icons.format_italic),
      ('underline', Icons.format_underlined),
      ('strike', Icons.format_strikethrough),
      ('h1', Icons.title),
      ('code', Icons.code),
      ('codeblock', Icons.data_object),
      ('quote', Icons.format_quote),
      ('link', Icons.link),
      ('check', Icons.check_box_outlined),
      ('clear', Icons.format_clear),
    ];
    return Material(
      color: Colors.transparent,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          children: [
            for (final item in buttons)
              AppIconButton(
                tooltip: item.$1,
                icon: item.$2,
                onPressed: () => onFormat(item.$1),
              ),
            const SizedBox(width: 8),
            for (final color in colors)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: () => onColor(color),
                  child: Container(
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      color: Color(color),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: color == selectedColor
                            ? Theme.of(context).colorScheme.primary
                            : const Color(0xffcbd5e1),
                        width: color == selectedColor ? 2 : 1,
                      ),
                    ),
                  ),
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
      minLines: 18,
      maxLines: null,
      keyboardType: TextInputType.multiline,
      decoration: InputDecoration.collapsed(
        hintText: hint,
      ),
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
    for (final line in text.split('\n')) {
      final lineStyle = _lineStyle(base, line);
      spans.add(TextSpan(text: _visibleLine(line), style: lineStyle));
      spans.add(const TextSpan(text: '\n'));
    }
    if (spans.isNotEmpty) spans.removeLast();
    return TextSpan(style: base, children: spans);
  }

  TextStyle _lineStyle(TextStyle base, String line) {
    if (line.startsWith('# ')) {
      return base.copyWith(fontSize: 28, fontWeight: FontWeight.w700);
    }
    if (line.startsWith('## ')) {
      return base.copyWith(fontSize: 23, fontWeight: FontWeight.w700);
    }
    if (line.startsWith('### ')) {
      return base.copyWith(fontSize: 19, fontWeight: FontWeight.w700);
    }
    if (line.startsWith('> ')) {
      return base.copyWith(
          fontStyle: FontStyle.italic,
          color: base.color?.withValues(alpha: 0.72));
    }
    if (line.startsWith('```')) return base.copyWith(fontFamily: 'monospace');
    if (line.contains('**')) return base.copyWith(fontWeight: FontWeight.w700);
    if (line.contains('_')) return base.copyWith(fontStyle: FontStyle.italic);
    if (line.contains('~~')) {
      return base.copyWith(decoration: TextDecoration.lineThrough);
    }
    if (line.contains('<u>')) {
      return base.copyWith(decoration: TextDecoration.underline);
    }
    if (line.contains('`')) return base.copyWith(fontFamily: 'monospace');
    return base;
  }

  String _visibleLine(String line) {
    return line
        .replaceFirst(RegExp(r'^#{1,3}\s'), '')
        .replaceFirst(RegExp(r'^>\s'), '')
        .replaceAll('**', '')
        .replaceAll('~~', '')
        .replaceAll('`', '')
        .replaceAll('<u>', '')
        .replaceAll('</u>', '')
        .replaceAllMapped(
            RegExp(r'\[(.*?)\]\((.*?)\)'), (match) => match.group(1) ?? '');
  }
}

class _ChecklistEditor extends ConsumerWidget {
  const _ChecklistEditor({
    required this.items,
    required this.onChanged,
  });

  final List<ChecklistItem> items;
  final ValueChanged<List<ChecklistItem>> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              icon: Icons.add,
              onPressed: () => onChanged([
                ...items,
                ChecklistItem(
                    id: const Uuid().v4(), text: '', done: false, indent: 0),
              ]),
            ),
          ],
        ),
        ReorderableListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          buildDefaultDragHandles: false,
          itemCount: items.length,
          onReorderItem: (oldIndex, newIndex) {
            final next = [...items];
            final item = next.removeAt(oldIndex);
            next.insert(newIndex, item);
            onChanged(next);
          },
          itemBuilder: (context, index) {
            final item = items[index];
            return _ChecklistRow(
              key: ValueKey(item.id),
              index: index,
              item: item,
              onChanged: (updated) {
                final next = [...items]..[index] = updated;
                onChanged(next);
              },
              onDelete: () {
                final next = [...items]..removeAt(index);
                onChanged(next);
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
    required this.onChanged,
    required this.onDelete,
  });

  final int index;
  final ChecklistItem item;
  final ValueChanged<ChecklistItem> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: item.indent * 20.0, bottom: 6),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: index,
            child: Icon(
              Icons.drag_indicator,
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
              controller: TextEditingController(text: item.text)
                ..selection = TextSelection.collapsed(offset: item.text.length),
              decoration: const InputDecoration.collapsed(hintText: 'Task'),
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
            ),
          ),
          AppIconButton(
            tooltip: 'Outdent',
            icon: Icons.format_indent_decrease,
            onPressed: item.indent == 0
                ? null
                : () => onChanged(item.copyWith(indent: item.indent - 1)),
          ),
          AppIconButton(
            tooltip: 'Indent',
            icon: Icons.format_indent_increase,
            onPressed: () => onChanged(item.copyWith(
                indent: item.indent + 1 > 4 ? 4 : item.indent + 1)),
          ),
          AppIconButton(
            tooltip: 'Delete',
            icon: Icons.delete_outline,
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
  var _role = 'editor';
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _recipient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    return Padding(
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.viewInsetsOf(context).bottom + 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.t('share'),
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: _recipient,
              decoration: InputDecoration(
                  labelText: l10n.t('recipientId'),
                  prefixIcon: const Icon(Icons.person_add_alt)),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              selected: {_role},
              segments: [
                ButtonSegment(
                    value: 'editor',
                    label: Text(l10n.t('editor')),
                    icon: const Icon(Icons.edit)),
                ButtonSegment(
                    value: 'viewer',
                    label: Text(l10n.t('viewer')),
                    icon: const Icon(Icons.visibility)),
              ],
              onSelectionChanged: (value) =>
                  setState(() => _role = value.first),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _invite,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
              label: Text(l10n.t('invite')),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _invite() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(notesControllerProvider.notifier).inviteCollaborator(
            note: widget.note,
            recipientUserId: _recipient.text.trim(),
            role: _role,
          );
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _FormatIntent extends Intent {
  const _FormatIntent(this.action);

  final String action;
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

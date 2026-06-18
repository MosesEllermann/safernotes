import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zknotes_app/features/auth/auth_controller.dart';
import 'package:zknotes_app/features/notes/note_editor_screen.dart';
import 'package:zknotes_app/features/notes/notes_controller.dart';
import 'package:zknotes_app/features/settings/settings_screen.dart';
import 'package:zknotes_app/shared/app/app_l10n.dart';
import 'package:zknotes_app/shared/models/note.dart';
import 'package:zknotes_app/shared/widgets/animated_icon_button.dart';

final noteSearchProvider = StateProvider<String>((ref) => '');
final sideNavExpandedProvider = StateProvider<bool>((ref) => true);

class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final notes = ref.watch(notesControllerProvider);
    final session = ref.watch(authControllerProvider).valueOrNull;
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 900;
    final showLogoText = width >= 620;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 8,
        title: Row(
          children: [
            AppIconButton(
              tooltip: 'Menue',
              icon: Icons.menu_rounded,
              onPressed: () {
                if (desktop) {
                  final expanded = ref.read(sideNavExpandedProvider);
                  ref.read(sideNavExpandedProvider.notifier).state = !expanded;
                } else {
                  _showNavigationSheet(context, ref);
                }
              },
            ),
            const SizedBox(width: 8),
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: const Color(0xfffff4c2),
                borderRadius: BorderRadius.circular(10),
              ),
              child:
                  const Icon(Icons.lightbulb_outline, color: Color(0xfff9ab00)),
            ),
            if (showLogoText) ...[
              const SizedBox(width: 12),
              Text(
                l10n.t('appName'),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(width: 24),
            ] else
              const SizedBox(width: 10),
            const Expanded(child: _SearchField()),
          ],
        ),
        actions: [
          if (desktop) ...[
            const _SyncIndicator(),
            AppIconButton(
              tooltip: l10n.t('settings'),
              icon: Icons.settings_outlined,
              onPressed: () => _openSettings(context),
            ),
          ],
          _AccountButton(email: session?.email ?? ''),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: notes.when(
          data: (items) =>
              _KeepWorkspace(notes: items, email: session?.email ?? ''),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => _ErrorState(
            message: error.toString(),
            onRetry: () =>
                ref.read(notesControllerProvider.notifier).pullRemote(),
          ),
        ),
      ),
    );
  }
}

class _KeepWorkspace extends ConsumerStatefulWidget {
  const _KeepWorkspace({
    required this.notes,
    required this.email,
  });

  final List<PlainNote> notes;
  final String email;

  @override
  ConsumerState<_KeepWorkspace> createState() => _KeepWorkspaceState();
}

class _KeepWorkspaceState extends ConsumerState<_KeepWorkspace> {
  String? _draggedId;
  int? _dropIndex;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final bucket = ref.watch(noteBucketProvider);
    ref.watch(noteSearchProvider);
    final baseNotes = _filteredNotes;
    final filtered = _previewNotes(baseNotes);
    final dragging = _draggedId != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (wide) const _SideRail(),
        Expanded(
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding:
                      EdgeInsets.fromLTRB(wide ? 32 : 16, 8, wide ? 32 : 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (bucket == 'active')
                        _QuickComposer(
                          onTap: () => _openEditor(
                            context,
                            ref,
                            ref
                                .read(notesControllerProvider.notifier)
                                .createEmptyNote(),
                          ),
                        ),
                      SizedBox(height: bucket == 'active' ? 28 : 8),
                    ],
                  ),
                ),
              ),
              if (filtered.isEmpty)
                const SliverFillRemaining(
                    hasScrollBody: false, child: _EmptyState())
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                      wide ? 32 : 12, 0, wide ? 32 : 12, 48),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: wide ? 290 : 460,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: wide ? 1.08 : 1.55,
                    ),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final note = filtered[index];
                      return DragTarget<PlainNote>(
                        key: ValueKey('note-drop-${note.localId}'),
                        onWillAcceptWithDetails: (_) => true,
                        onMove: (details) {
                          final nextIndex = _dropIndexForCard(
                            context: context,
                            globalOffset: details.offset,
                            cardIndex: index,
                            wide: wide,
                          );
                          if (_dropIndex == nextIndex) return;
                          setState(() => _dropIndex = nextIndex);
                        },
                        onLeave: (_) {
                          if (dragging) setState(() => _dropIndex = null);
                        },
                        onAcceptWithDetails: (details) {
                          _commitReorder(
                            details.data.localId,
                            _dropIndex ??
                                _dropIndexForCard(
                                  context: context,
                                  globalOffset: details.offset,
                                  cardIndex: index,
                                  wide: wide,
                                ),
                            bucket,
                          );
                        },
                        builder: (context, candidateData, _) {
                          final highlighted =
                              _dropIndex == index || _dropIndex == index + 1;
                          final card = _KeepNoteCard(
                            note: note,
                            dropHighlighted: highlighted,
                            onTap: () => _openEditor(context, ref, note),
                            onTogglePin: () => ref
                                .read(notesControllerProvider.notifier)
                                .togglePinned(note),
                            onInvite: () =>
                                _showInviteSheet(context, ref, note),
                            onArchive: () => ref
                                .read(notesControllerProvider.notifier)
                                .changeState(note, 'archived'),
                            onTrash: () => ref
                                .read(notesControllerProvider.notifier)
                                .changeState(note, 'trashed'),
                            onRestore: () => ref
                                .read(notesControllerProvider.notifier)
                                .changeState(note, 'active'),
                            onDeleteForever: () => ref
                                .read(notesControllerProvider.notifier)
                                .changeState(note, 'deleted'),
                          );
                          return LongPressDraggable<PlainNote>(
                            data: note,
                            feedback: _NoteDragFeedback(note: note),
                            onDragStarted: () => setState(() {
                              _draggedId = note.localId;
                              _dropIndex = null;
                            }),
                            onDraggableCanceled: (_, __) => _clearDragPreview(),
                            onDragEnd: (_) => _clearDragPreview(),
                            onDragCompleted: _clearDragPreview,
                            childWhenDragging:
                                Opacity(opacity: 0.34, child: card),
                            child: card,
                          );
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<PlainNote> _previewNotes(List<PlainNote> notes) {
    final draggedId = _draggedId;
    if (draggedId == null) return notes;
    final draggedIndex = notes.indexWhere((note) => note.localId == draggedId);
    if (draggedIndex < 0) return notes;
    final next = [...notes];
    final dragged = next.removeAt(draggedIndex);
    final targetIndex = _dropIndex;
    if (targetIndex == null) return notes;
    next.insert(targetIndex.clamp(0, next.length).toInt(), dragged);
    return next;
  }

  int _dropIndexForCard({
    required BuildContext context,
    required Offset globalOffset,
    required int cardIndex,
    required bool wide,
  }) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return cardIndex;
    final local = box.globalToLocal(globalOffset);
    final before =
        wide ? local.dx < box.size.width / 2 : local.dy < box.size.height / 2;
    return before ? cardIndex : cardIndex + 1;
  }

  void _commitReorder(String draggedId, int targetIndex, String bucket) {
    ref.read(notesControllerProvider.notifier).reorderNotes(
          draggedId: draggedId,
          targetIndex: targetIndex,
          bucket: bucket,
        );
    _clearDragPreview();
  }

  void _clearDragPreview() {
    if (!mounted) return;
    setState(() {
      _draggedId = null;
      _dropIndex = null;
    });
  }

  List<PlainNote> get _filteredNotes {
    final query = ref.read(noteSearchProvider).trim().toLowerCase();
    final bucket = ref.read(noteBucketProvider);
    final bucketNotes = widget.notes.where((note) => note.state == bucket);
    if (query.isEmpty) return bucketNotes.toList();
    return bucketNotes.where((note) {
      final checklist = note.checklist.map((item) => item.text).join(' ');
      return '${note.title} ${note.body} $checklist'
          .toLowerCase()
          .contains(query);
    }).toList();
  }
}

class _SideRail extends ConsumerWidget {
  const _SideRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final expanded = ref.watch(sideNavExpandedProvider);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: expanded ? 224 : 88,
      padding: EdgeInsets.fromLTRB(12, 12, expanded ? 16 : 12, 0),
      child: Column(
        crossAxisAlignment:
            expanded ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
        children: [
          _RailButton(
            bucket: 'active',
            icon: Icons.lightbulb_outline,
            label: l10n.t('notes'),
            expanded: expanded,
          ),
          const SizedBox(height: 8),
          _RailButton(
            bucket: 'archived',
            icon: Icons.archive_outlined,
            label: 'Archiv',
            expanded: expanded,
          ),
          const SizedBox(height: 8),
          _RailButton(
            bucket: 'trashed',
            icon: Icons.delete_outline,
            label: 'Papierkorb',
            expanded: expanded,
          ),
        ],
      ),
    );
  }
}

class _RailButton extends ConsumerWidget {
  const _RailButton({
    required this.bucket,
    required this.icon,
    required this.label,
    required this.expanded,
  });

  final String bucket;
  final IconData icon;
  final String label;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(noteBucketProvider) == bucket;
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: () => ref.read(noteBucketProvider.notifier).state = bucket,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutBack,
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 14 : 0),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(expanded ? 999 : 18),
          ),
          child: Row(
            mainAxisAlignment:
                expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? Theme.of(context).colorScheme.onSecondaryContainer
                      : Theme.of(context).colorScheme.onSurfaceVariant),
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                child: expanded
                    ? Padding(
                        padding: const EdgeInsets.only(left: 14),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: selected
                                        ? Theme.of(context)
                                            .colorScheme
                                            .onSecondaryContainer
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                    fontWeight: selected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SearchField extends ConsumerWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: TextField(
          onChanged: (value) =>
              ref.read(noteSearchProvider.notifier).state = value,
          decoration: InputDecoration(
            hintText: 'Search',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withValues(alpha: 0.68),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(999),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
        ),
      ),
    );
  }
}

class _QuickComposer extends ConsumerWidget {
  const _QuickComposer({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Material(
          elevation: 2,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.t('writeNote'),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ),
                  AppIconButton(
                    tooltip: l10n.t('checklist'),
                    onPressed: onTap,
                    icon: Icons.check_box_outlined,
                  ),
                  AppIconButton(
                    tooltip: l10n.t('newNote'),
                    onPressed: onTap,
                    icon: Icons.brush_outlined,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _KeepNoteCard extends StatefulWidget {
  const _KeepNoteCard({
    required this.note,
    this.dropHighlighted = false,
    required this.onTap,
    required this.onTogglePin,
    required this.onInvite,
    required this.onArchive,
    required this.onTrash,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final PlainNote note;
  final bool dropHighlighted;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onInvite;
  final VoidCallback onArchive;
  final VoidCallback onTrash;
  final VoidCallback onRestore;
  final VoidCallback onDeleteForever;

  @override
  State<_KeepNoteCard> createState() => _KeepNoteCardState();
}

class _KeepNoteCardState extends State<_KeepNoteCard> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final scheme = Theme.of(context).colorScheme;
    final bg = _noteColorFor(context, note.color);
    final isPlainWhite = note.color == 0xffffffff;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedScale(
        scale: _hovered ? 1.018 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: Material(
          color: isPlainWhite ? scheme.surface : bg,
          elevation: _hovered ? 4 : 0,
          shadowColor: Colors.black.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(8),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: widget.dropHighlighted
                      ? scheme.primary
                      : _hovered
                          ? scheme.outline
                          : scheme.outlineVariant.withValues(alpha: 0.8),
                  width: widget.dropHighlighted ? 2 : 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          note.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ),
                      AnimatedOpacity(
                        opacity: _hovered || note.pinned ? 1 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: AppIconButton(
                          tooltip: note.pinned ? 'Losloesen' : 'Anheften',
                          icon: note.pinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          selected: note.pinned,
                          onPressed: widget.onTogglePin,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: note.checklist.isNotEmpty && note.body.trim().isEmpty
                        ? _ChecklistPreview(items: note.checklist)
                        : _FormattedPreview(text: note.body),
                  ),
                  Row(
                    children: [
                      if (note.checklist.isNotEmpty)
                        _MetaPill(
                          icon: Icons.check_box_outlined,
                          label:
                              '${note.checklist.where((item) => item.done).length}/${note.checklist.length}',
                        ),
                      if (note.conflicted)
                        _MetaPill(
                          icon: Icons.error_outline,
                          label: 'Conflict',
                          color: scheme.error,
                        ),
                      if (note.dirty)
                        _MetaPill(
                          icon: Icons.cloud_upload_outlined,
                          label: 'Saving',
                          color: scheme.primary,
                        ),
                      const Spacer(),
                      AnimatedOpacity(
                        opacity: _hovered ? 1 : 0,
                        duration: const Duration(milliseconds: 120),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (note.state != 'active')
                              AppIconButton(
                                tooltip: 'Wiederherstellen',
                                icon: Icons.restore,
                                onPressed: widget.onRestore,
                              ),
                            if (note.state == 'active')
                              AppIconButton(
                                tooltip: 'Archivieren',
                                icon: Icons.archive_outlined,
                                onPressed: widget.onArchive,
                              ),
                            if (note.state == 'active')
                              AppIconButton(
                                tooltip: 'Mitarbeiter einladen',
                                icon: Icons.person_add_alt,
                                onPressed: widget.onInvite,
                              ),
                            if (note.state != 'trashed')
                              AppIconButton(
                                tooltip: 'Papierkorb',
                                icon: Icons.delete_outline,
                                onPressed: widget.onTrash,
                              )
                            else
                              AppIconButton(
                                tooltip: 'Endgueltig loeschen',
                                icon: Icons.delete_forever_outlined,
                                onPressed: widget.onDeleteForever,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteDragFeedback extends StatelessWidget {
  const _NoteDragFeedback({required this.note});

  final PlainNote note;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = _noteColorFor(context, note.color);
    return Material(
      color: note.color == 0xffffffff ? scheme.surface : bg,
      elevation: 10,
      shadowColor: Colors.black.withValues(alpha: 0.24),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 260,
        height: 170,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                note.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: note.checklist.isNotEmpty && note.body.trim().isEmpty
                    ? _ChecklistPreview(items: note.checklist)
                    : _FormattedPreview(text: note.body),
              ),
            ],
          ),
        ),
      ),
    );
  }
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

class _ChecklistPreview extends StatelessWidget {
  const _ChecklistPreview({required this.items});

  final List<ChecklistItem> items;

  @override
  Widget build(BuildContext context) {
    final visible = items.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in visible)
          Padding(
            padding: EdgeInsets.only(left: item.indent * 14.0, bottom: 5),
            child: Row(
              children: [
                Icon(
                  item.done ? Icons.check_box : Icons.check_box_outline_blank,
                  size: 14,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    item.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          decoration:
                              item.done ? TextDecoration.lineThrough : null,
                          color: item.done
                              ? Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.52)
                              : null,
                        ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _FormattedPreview extends StatelessWidget {
  const _FormattedPreview({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35);
    final lines =
        text.trim().isEmpty ? [''] : text.trim().split('\n').take(7).toList();
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            TextSpan(
              text: _clean(lines[i]),
              style: _styleFor(context, base, lines[i]),
            ),
            if (i != lines.length - 1) const TextSpan(text: '\n'),
          ],
        ],
      ),
      maxLines: 7,
      overflow: TextOverflow.ellipsis,
    );
  }

  TextStyle? _styleFor(BuildContext context, TextStyle? base, String line) {
    if (line.startsWith('# ')) {
      return base?.copyWith(fontSize: 18, fontWeight: FontWeight.w700);
    }
    if (line.startsWith('## ')) {
      return base?.copyWith(fontSize: 16, fontWeight: FontWeight.w700);
    }
    if (line.startsWith('### ')) {
      return base?.copyWith(fontWeight: FontWeight.w700);
    }
    if (line.startsWith('> ')) {
      return base?.copyWith(
        fontStyle: FontStyle.italic,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      );
    }
    if (line.contains('**')) return base?.copyWith(fontWeight: FontWeight.w700);
    if (line.contains('_')) return base?.copyWith(fontStyle: FontStyle.italic);
    if (line.contains('~~')) {
      return base?.copyWith(decoration: TextDecoration.lineThrough);
    }
    if (line.contains('`')) return base?.copyWith(fontFamily: 'monospace');
    return base;
  }

  String _clean(String line) {
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

class _MetaPill extends StatelessWidget {
  const _MetaPill({
    required this.icon,
    required this.label,
    this.color,
  });

  final IconData icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final effective = color ?? Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: effective),
          const SizedBox(width: 3),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: effective)),
        ],
      ),
    );
  }
}

class _SyncIndicator extends ConsumerWidget {
  const _SyncIndicator({this.showLabel = false});

  final bool showLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final status = ref.watch(syncStatusProvider);
    final (icon, label, color) = switch (status) {
      SyncStatus.saved => (
          Icons.cloud_done_outlined,
          l10n.t('saved'),
          Theme.of(context).colorScheme.onSurfaceVariant
        ),
      SyncStatus.saving => (
          Icons.pending_outlined,
          l10n.t('saving'),
          Theme.of(context).colorScheme.primary
        ),
      SyncStatus.syncing => (
          Icons.sync,
          l10n.t('syncing'),
          Theme.of(context).colorScheme.primary
        ),
      SyncStatus.offline => (
          Icons.cloud_off_outlined,
          l10n.t('offline'),
          Theme.of(context).colorScheme.error
        ),
      SyncStatus.conflict => (
          Icons.error_outline,
          l10n.t('conflict'),
          Theme.of(context).colorScheme.error
        ),
    };
    final content = Row(
      mainAxisSize: showLabel ? MainAxisSize.max : MainAxisSize.min,
      children: [
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          transitionBuilder: (child, animation) => ScaleTransition(
            scale:
                CurvedAnimation(parent: animation, curve: Curves.easeOutBack),
            child: child,
          ),
          child: Icon(icon, key: ValueKey(status), size: 18, color: color),
        ),
        if (showLabel) ...[
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: color, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ],
    );
    return Tooltip(
      message: label,
      child: showLabel
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(999),
              ),
              child: content,
            )
          : SizedBox(
              width: 40,
              child: Center(child: content),
            ),
    );
  }
}

class _AccountButton extends ConsumerWidget {
  const _AccountButton({required this.email});

  final String email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initial = email.isEmpty ? '?' : email.substring(0, 1).toUpperCase();
    return Tooltip(
      message: email,
      child: GestureDetector(
        onTap: () => _showAccountSideSheet(context, ref, email),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

void _openSettings(BuildContext context) {
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => const SettingsScreen(),
    ),
  );
}

void _showNavigationSheet(BuildContext context, WidgetRef ref) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Menue schliessen',
    barrierColor: Colors.black.withValues(alpha: 0.32),
    transitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (context, _, __) => Align(
      alignment: Alignment.centerLeft,
      child: const _NavigationSideSheet(),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(-1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class _NavigationSideSheet extends ConsumerWidget {
  const _NavigationSideSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(28)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: SizedBox(
          width: (MediaQuery.sizeOf(context).width * 0.86).clamp(280.0, 340.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: const Color(0xfffff4c2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.lightbulb_outline,
                          color: Color(0xfff9ab00), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      l10n.t('appName'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const Spacer(),
                    AppIconButton(
                      tooltip: 'Schliessen',
                      icon: Icons.close_rounded,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                _MobileMenuButton(
                  bucket: 'active',
                  icon: Icons.lightbulb_outline,
                  label: l10n.t('notes'),
                ),
                _MobileMenuButton(
                  bucket: 'archived',
                  icon: Icons.archive_outlined,
                  label: 'Archiv',
                ),
                _MobileMenuButton(
                  bucket: 'trashed',
                  icon: Icons.delete_outline,
                  label: 'Papierkorb',
                ),
                const Spacer(),
                const _SyncIndicator(showLabel: true),
                const SizedBox(height: 8),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _openSettings(context);
                  },
                  icon: const Icon(Icons.settings_outlined),
                  label: Text(l10n.t('settings')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileMenuButton extends ConsumerWidget {
  const _MobileMenuButton({
    required this.bucket,
    required this.icon,
    required this.label,
  });

  final String bucket;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(noteBucketProvider) == bucket;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: FilledButton.tonalIcon(
        style: FilledButton.styleFrom(
          alignment: Alignment.centerLeft,
          backgroundColor: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          foregroundColor: selected
              ? Theme.of(context).colorScheme.onSecondaryContainer
              : Theme.of(context).colorScheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        ),
        onPressed: () {
          ref.read(noteBucketProvider.notifier).state = bucket;
          Navigator.of(context).pop();
        },
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

void _showAccountSideSheet(BuildContext context, WidgetRef ref, String email) {
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Account schliessen',
    barrierColor: Colors.black.withValues(alpha: 0.34),
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (context, _, __) => Align(
      alignment: Alignment.centerRight,
      child: _AccountSideSheet(email: email),
    ),
    transitionBuilder: (context, animation, _, child) => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );
}

class _AccountSideSheet extends ConsumerWidget {
  const _AccountSideSheet({required this.email});

  final String email;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initial = email.isEmpty ? '?' : email.substring(0, 1).toUpperCase();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(30)),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        child: SizedBox(
          width: (MediaQuery.sizeOf(context).width * 0.92).clamp(320.0, 420.0),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Text(
                      'Account',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const Spacer(),
                    AppIconButton(
                      tooltip: 'Schliessen',
                      icon: Icons.close_rounded,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutBack,
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: scheme.primary.withValues(alpha: 0.18),
                          blurRadius: 28,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  email,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Angemeldet',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.of(context).pop();
                    _openSettings(context);
                  },
                  icon: const Icon(Icons.settings_outlined),
                  label: const Text('Einstellungen'),
                ),
                const SizedBox(height: 10),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.errorContainer,
                    foregroundColor: scheme.onErrorContainer,
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    ref.read(authControllerProvider.notifier).signOut();
                  },
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Logout'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _showInviteSheet(BuildContext context, WidgetRef ref, PlainNote note) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => _InviteSheet(note: note),
  );
}

class _InviteSheet extends ConsumerStatefulWidget {
  const _InviteSheet({required this.note});

  final PlainNote note;

  @override
  ConsumerState<_InviteSheet> createState() => _InviteSheetState();
}

class _InviteSheetState extends ConsumerState<_InviteSheet> {
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
    return Padding(
      padding: EdgeInsets.fromLTRB(
        24,
        12,
        24,
        MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Mitarbeiter einladen',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _recipient,
              decoration: const InputDecoration(
                labelText: 'User ID',
                prefixIcon: Icon(Icons.person_add_alt),
              ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              selected: {_role},
              segments: const [
                ButtonSegment(
                  value: 'editor',
                  label: Text('Editor'),
                  icon: Icon(Icons.edit),
                ),
                ButtonSegment(
                  value: 'viewer',
                  label: Text('Viewer'),
                  icon: Icon(Icons.visibility),
                ),
              ],
              onSelectionChanged: (value) =>
                  setState(() => _role = value.first),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy || widget.note.remoteId == null ? null : _invite,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              label: const Text('Einladen'),
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

class _EmptyState extends ConsumerWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lightbulb_outline,
              size: 86,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            const SizedBox(height: 16),
            Text(
              l10n.t('noNotes'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                color: Theme.of(context).colorScheme.error, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}

void _openEditor(BuildContext context, WidgetRef ref, PlainNote note) {
  final wide = MediaQuery.sizeOf(context).width >= 760;
  if (wide) {
    showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(32),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
          child: NoteEditorPanel(note: note),
        ),
      ),
    );
  } else {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(note: note)),
    );
  }
}

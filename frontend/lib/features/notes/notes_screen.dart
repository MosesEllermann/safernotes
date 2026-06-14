import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zknotes_app/features/auth/auth_controller.dart';
import 'package:zknotes_app/features/notes/note_editor_screen.dart';
import 'package:zknotes_app/features/notes/notes_controller.dart';
import 'package:zknotes_app/features/settings/settings_sheet.dart';
import 'package:zknotes_app/shared/app/app_l10n.dart';
import 'package:zknotes_app/shared/models/note.dart';
import 'package:zknotes_app/shared/widgets/animated_icon_button.dart';

final noteSearchProvider = StateProvider<String>((ref) => '');

class NotesScreen extends ConsumerWidget {
  const NotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final notes = ref.watch(notesControllerProvider);
    final session = ref.watch(authControllerProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        titleSpacing: 12,
        title: Row(
          children: [
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
            const SizedBox(width: 12),
            Text(
              l10n.t('appName'),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(width: 24),
            const Expanded(child: _SearchField()),
          ],
        ),
        actions: [
          const _SyncIndicator(),
          AppIconButton(
            tooltip: l10n.t('settings'),
            icon: Icons.settings_outlined,
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              builder: (_) => const SettingsSheet(),
            ),
          ),
          AppIconButton(
            tooltip: l10n.t('logout'),
            icon: Icons.logout,
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
          ),
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
  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final bucket = ref.watch(noteBucketProvider);
    ref.watch(noteSearchProvider);
    final filtered = _filteredNotes;
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
                      if (widget.email.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 8),
                          child: Text(
                            widget.email,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                          ),
                        ),
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
                      return _KeepNoteCard(
                        note: note,
                        onTap: () => _openEditor(context, ref, note),
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
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
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
    return Container(
      width: 88,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        children: [
          _RailButton(
            bucket: 'active',
            icon: Icons.lightbulb_outline,
            label: l10n.t('notes'),
          ),
          const SizedBox(height: 8),
          _RailButton(
            bucket: 'archived',
            icon: Icons.archive_outlined,
            label: 'Archiv',
          ),
          const SizedBox(height: 8),
          _RailButton(
            bucket: 'trashed',
            icon: Icons.delete_outline,
            label: 'Papierkorb',
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
  });

  final String bucket;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(noteBucketProvider) == bucket;
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: () => ref.read(noteBucketProvider.notifier).state = bucket,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          width: selected ? 62 : 54,
          height: 42,
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context).colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(icon,
              size: 18,
              color: selected
                  ? Theme.of(context).colorScheme.onSecondaryContainer
                  : Theme.of(context).colorScheme.onSurfaceVariant),
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
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide.none,
            ),
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
    required this.onTap,
    required this.onArchive,
    required this.onTrash,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final PlainNote note;
  final VoidCallback onTap;
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
                  color: _hovered
                      ? scheme.outline
                      : scheme.outlineVariant.withValues(alpha: 0.8),
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
                        child: Icon(
                          note.pinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          size: 18,
                          color: scheme.onSurfaceVariant,
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
                                onPressed: widget.onTap,
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
  const _SyncIndicator();

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
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 6),
            if (MediaQuery.sizeOf(context).width >= 720)
              Text(label,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: color)),
          ],
        ),
      ),
    );
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

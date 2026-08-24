import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/notes/note_editor_screen.dart';
import 'package:safernotes_app/features/notes/notes_controller.dart';
import 'package:safernotes_app/features/settings/settings_screen.dart';
import 'package:safernotes_app/shared/app/app_l10n.dart';
import 'package:safernotes_app/shared/api/api_client.dart';
import 'package:safernotes_app/shared/models/note.dart';
import 'package:safernotes_app/shared/notifications/reminder_notifications.dart';
import 'package:safernotes_app/shared/providers.dart';
import 'package:safernotes_app/shared/theme/app_theme.dart';
import 'package:safernotes_app/shared/widgets/animated_icon_button.dart';
import 'package:safernotes_app/shared/widgets/safernotes_logo.dart';

final noteSearchProvider = StateProvider<String>((ref) => '');
final sideNavExpandedProvider = StateProvider<bool>((ref) => true);

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({super.key, this.invitationId});

  final String? invitationId;

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final Map<String, Timer> _reminderTimers = {};
  var _invitationHandled = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(notesControllerProvider, (_, next) {
      final notes = next.valueOrNull;
      if (notes != null) _scheduleReminders(notes);
    }, fireImmediately: true);
    if (widget.invitationId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_reviewInvitation(widget.invitationId!));
      });
    }
  }

  Future<void> _reviewInvitation(String invitationId) async {
    if (_invitationHandled || !mounted) return;
    _invitationHandled = true;
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null) return;

    try {
      final invitation = await _loadInvitation(
        invitationId: invitationId,
        accessToken: session.accessToken,
      );
      if (!mounted) return;
      final noteId = invitation['note'] as String?;
      if (invitation['status'] == 'accepted' && noteId != null) {
        await _importSharedNote(noteId);
        if (mounted) {
          _showInvitationMessage(
            ref.read(l10nProvider).t('invitationAccepted'),
          );
        }
        return;
      }
      if (invitation['status'] != 'pending') {
        _showInvitationMessage(ref.read(l10nProvider).t('invitationClosed'));
        return;
      }
      final decision = await showDialog<_InvitationDecision>(
        context: context,
        builder: (_) => _InvitationDialog(
          role: invitation['role'] as String? ?? 'viewer',
        ),
      );
      if (decision == null || !mounted) return;
      final result = await _decideInvitation(
        invitationId: invitationId,
        accessToken: session.accessToken,
        decision: decision,
      );
      if (decision == _InvitationDecision.accept) {
        final accepted = result['invitation'] is Map
            ? Map<String, dynamic>.from(result['invitation'] as Map)
            : invitation;
        final acceptedNoteId = accepted['note'] as String? ?? noteId;
        if (acceptedNoteId == null) {
          throw StateError('Accepted invitation did not include a note.');
        }
        await _importSharedNote(acceptedNoteId);
      }
      if (mounted) {
        _showInvitationMessage(
          decision == _InvitationDecision.accept
              ? ref.read(l10nProvider).t('invitationAccepted')
              : ref.read(l10nProvider).t('invitationDeclined'),
        );
      }
    } catch (error) {
      if (mounted) {
        _showInvitationMessage(_invitationErrorMessage(error));
      }
    }
  }

  void _showInvitationMessage(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<Map<String, dynamic>> _loadInvitation({
    required String invitationId,
    required String accessToken,
  }) async {
    return ref.read(apiClientProvider).fetchShareInvitation(
          invitationId: invitationId,
          accessToken: accessToken,
        );
  }

  Future<Map<String, dynamic>> _decideInvitation({
    required String invitationId,
    required String accessToken,
    required _InvitationDecision decision,
  }) async {
    return ref.read(apiClientProvider).decideShareInvitation(
          invitationId: invitationId,
          accessToken: accessToken,
          decision: decision.name,
        );
  }

  Future<void> _importSharedNote(String noteId) async {
    await ref.read(authControllerProvider.notifier).ensureEncryptionKeys();
    await ref
        .read(notesControllerProvider.notifier)
        .pullRemote(requiredNoteId: noteId);
  }

  String _invitationErrorMessage(Object error) {
    if (error is TimeoutException ||
        error is ApiException && error.statusCode == 0) {
      return ref.read(l10nProvider).t('serverUnreachable');
    }
    if (error is ApiException && error.statusCode == 404) {
      return ref.read(l10nProvider).t('invitationNotFound');
    }
    if (error is ApiException) return error.message;
    if (error is StateError) {
      return ref.read(l10nProvider).t('sharedNoteImportFailed');
    }
    return ref.read(l10nProvider).t('invitationOpenFailed');
  }

  @override
  void dispose() {
    for (final timer in _reminderTimers.values) {
      timer.cancel();
    }
    _reminderTimers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final notes = ref.watch(notesControllerProvider);
    final session = ref.watch(authControllerProvider).valueOrNull;
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 900;
    final showLogoText = width >= 620;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: desktop ? 12 : 14,
        title: desktop
            ? Row(
                children: [
                  AppIconButton(
                    tooltip: l10n.t('menu'),
                    icon: LucideIcons.panelLeft,
                    onPressed: () {
                      final expanded = ref.read(sideNavExpandedProvider);
                      ref.read(sideNavExpandedProvider.notifier).state =
                          !expanded;
                    },
                  ),
                  const SizedBox(width: 8),
                  const SafernotesLogo(size: 38),
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
              )
            : Row(
                children: [
                  SizedBox(
                    width: 42,
                    child: Center(
                      child: AppIconButton(
                        tooltip: l10n.t('menu'),
                        icon: LucideIcons.menu,
                        onPressed: () => _showNavigationSheet(context, ref),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: _SearchField(compact: true)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 42,
                    child: Center(
                      child: _AccountButton(
                        email: session?.email ?? '',
                        compact: true,
                      ),
                    ),
                  ),
                ],
              ),
        actions: desktop
            ? [
                const _SyncIndicator(),
                AppIconButton(
                  tooltip: l10n.t('settings'),
                  icon: LucideIcons.settings,
                  onPressed: () => _openSettings(context),
                ),
                _AccountButton(email: session?.email ?? ''),
                const SizedBox(width: 8),
              ]
            : null,
      ),
      floatingActionButton: desktop
          ? null
          : _CreateNoteFab(
              onNewNote: () =>
                  _createNoteFromAction(context, ref, _CreateAction.note),
              onNewReminder: () => unawaited(_startReminderFlow(context, ref)),
              onNewList: () =>
                  _createNoteFromAction(context, ref, _CreateAction.list),
            ),
      bottomNavigationBar: desktop ? null : const _MobileBottomNav(),
      body: SafeArea(
        child: notes.when(
          data: (items) => Column(
            children: [
              if (session != null && !session.emailVerified)
                _EmailVerificationBanner(email: session.email),
              Expanded(
                child: _KeepWorkspace(
                  notes: items,
                  email: session?.email ?? '',
                ),
              ),
            ],
          ),
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

  void _scheduleReminders(List<PlainNote> notes) {
    final l10n = ref.read(l10nProvider);
    final now = DateTime.now();
    final nextIds = <String>{};
    for (final note in notes) {
      final reminderAt = note.reminderAt;
      if (reminderAt == null || note.state == 'deleted') continue;
      if (reminderAt.isBefore(now)) continue;
      final key = '${note.localId}-${reminderAt.toIso8601String()}';
      nextIds.add(key);
      if (_reminderTimers.containsKey(key)) continue;
      unawaited(scheduleReminderNotification(
        reminderId: key,
        title: note.title.trim().isEmpty ? l10n.t('reminder') : note.title,
        body: _reminderBody(note),
        scheduledAt: reminderAt,
      ));
      _reminderTimers[key] = Timer(reminderAt.difference(now), () async {
        _reminderTimers.remove(key);
        final shown = await showReminderNotification(
          title: note.title.trim().isEmpty ? l10n.t('reminder') : note.title,
          body: _reminderBody(note),
        );
        if (!shown && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                note.title.trim().isEmpty
                    ? l10n.t('reminder')
                    : l10n.t(
                        'reminderNotificationTitle',
                        params: {'title': note.title},
                      ),
              ),
              action: SnackBarAction(
                label: l10n.t('open'),
                onPressed: () => _openEditor(context, ref, note),
              ),
            ),
          );
        }
        await ref
            .read(notesControllerProvider.notifier)
            .setReminder(note, null);
      });
    }
    for (final entry in [..._reminderTimers.entries]) {
      if (!nextIds.contains(entry.key)) {
        entry.value.cancel();
        unawaited(cancelReminderNotification(entry.key));
        _reminderTimers.remove(entry.key);
      }
    }
  }

  String _reminderBody(PlainNote note) {
    if (note.body.trim().isNotEmpty) return note.body.trim();
    final checklist = note.checklist
        .where((item) => item.text.trim().isNotEmpty)
        .map((item) => item.text.trim())
        .take(3)
        .join(', ');
    return checklist.isEmpty
        ? ref.read(l10nProvider).t('reminderDefaultBody')
        : checklist;
  }
}

enum _InvitationDecision { accept, decline }

class _InvitationDialog extends StatelessWidget {
  const _InvitationDialog({required this.role});

  final String role;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n(Localizations.localeOf(context).languageCode);
    final canEdit = role == 'editor';
    return AlertDialog(
      icon: const Icon(LucideIcons.userRoundPlus),
      title: Text(l10n.t('noteInvitation')),
      content: Text(l10n.t(canEdit ? 'invitedToEdit' : 'invitedToView')),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            _InvitationDecision.decline,
          ),
          child: Text(l10n.t('decline')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            _InvitationDecision.accept,
          ),
          child: Text(l10n.t('accept')),
        ),
      ],
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
  late final ProviderSubscription<String> _bucketSubscription;

  @override
  void initState() {
    super.initState();
    _bucketSubscription = ref.listenManual<String>(
      noteBucketProvider,
      (_, __) => _clearDragPreview(),
    );
  }

  @override
  void dispose() {
    _bucketSubscription.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final wide = screenWidth >= 900;
    final compact = screenWidth < 700;
    final bucket = ref.watch(noteBucketProvider);
    ref.watch(noteSearchProvider);
    final baseNotes = _filteredNotes;
    final filtered = _previewNotes(baseNotes);
    final dragging = _draggedId != null;
    final noteColumnCount = compact ? 2 : _noteColumnCount(screenWidth, wide);
    final showTrashTarget = dragging && bucket != 'trashed';
    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide) const _SideRail(),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: SizedBox(height: wide ? 12 : 8),
                  ),
                  if (filtered.isEmpty)
                    const SliverFillRemaining(
                        hasScrollBody: false, child: _EmptyState())
                  else
                    SliverPadding(
                      padding: compact
                          ? const EdgeInsets.fromLTRB(12, 0, 12, 96)
                          : EdgeInsets.fromLTRB(
                              wide ? 32 : 12,
                              0,
                              wide ? 32 : 12,
                              48,
                            ),
                      sliver: SliverToBoxAdapter(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var column = 0;
                                column < noteColumnCount;
                                column += 1) ...[
                              Expanded(
                                child: _CompactNoteColumn(
                                  notes: [
                                    for (var i = column;
                                        i < filtered.length;
                                        i += noteColumnCount)
                                      (index: i, note: filtered[i]),
                                  ],
                                  dragging: dragging,
                                  dropIndex: _dropIndex,
                                  onDropIndexChanged: _setDropIndex,
                                  onCommitReorder: (draggedId, targetIndex) =>
                                      _commitReorder(
                                          draggedId, targetIndex, bucket),
                                  onDragStarted: _startDrag,
                                  onDragEnded: _clearDragPreview,
                                ),
                              ),
                              if (column != noteColumnCount - 1)
                                const SizedBox(width: 12),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: compact ? 12 : 20,
          child: IgnorePointer(
            ignoring: !showTrashTarget,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              offset: showTrashTarget ? Offset.zero : const Offset(0, 0.35),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 140),
                opacity: showTrashTarget ? 1 : 0,
                child: Center(
                  child: _AnimatedTrashDropTarget(
                    onAccepted: _moveToTrash,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  int _noteColumnCount(double screenWidth, bool wide) {
    if (!wide) return 2;
    final contentWidth =
        screenWidth - (ref.read(sideNavExpandedProvider) ? 212 : 78) - 64;
    return (contentWidth / 290).floor().clamp(2, 5).toInt();
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

  void _commitReorder(String draggedId, int targetIndex, String bucket) {
    ref.read(notesControllerProvider.notifier).reorderNotes(
          draggedId: draggedId,
          targetIndex: targetIndex,
          bucket: bucket,
        );
    _clearDragPreview();
  }

  void _setDropIndex(int? value) {
    if (!mounted || _dropIndex == value) return;
    setState(() => _dropIndex = value);
  }

  void _startDrag(PlainNote note) {
    if (!mounted) return;
    setState(() {
      _draggedId = note.localId;
      _dropIndex = null;
    });
  }

  void _clearDragPreview() {
    if (!mounted) return;
    if (_draggedId == null && _dropIndex == null) return;
    setState(() {
      _draggedId = null;
      _dropIndex = null;
    });
  }

  void _moveToTrash(PlainNote note) {
    final previousState = note.state;
    unawaited(
      ref.read(notesControllerProvider.notifier).changeState(note, 'trashed'),
    );
    _clearDragPreview();
    final l10n = ref.read(l10nProvider);
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(l10n.t('noteMovedToTrash')),
        action: SnackBarAction(
          label: l10n.t('undo'),
          onPressed: () => unawaited(
            ref
                .read(notesControllerProvider.notifier)
                .changeState(note, previousState),
          ),
        ),
      ),
    );
  }

  List<PlainNote> get _filteredNotes {
    final query = ref.read(noteSearchProvider).trim().toLowerCase();
    final bucket = ref.read(noteBucketProvider);
    final bucketNotes = switch (bucket) {
      'reminders' => widget.notes.where((note) =>
          note.reminderAt != null &&
          note.state != 'deleted' &&
          note.state != 'trashed'),
      'trashed' => widget.notes.where((note) => note.state == 'trashed'),
      _ => widget.notes
          .where((note) => note.state == bucket && note.reminderAt == null),
    };
    final visible = query.isEmpty
        ? bucketNotes.toList()
        : bucketNotes.where((note) {
            final checklist = note.checklist.map((item) => item.text).join(' ');
            return '${note.title} ${note.body} $checklist'
                .toLowerCase()
                .contains(query);
          }).toList();
    if (bucket == 'reminders') {
      visible.sort((a, b) => a.reminderAt!.compareTo(b.reminderAt!));
    }
    return visible;
  }
}

class _AnimatedTrashDropTarget extends StatefulWidget {
  const _AnimatedTrashDropTarget({required this.onAccepted});

  final ValueChanged<PlainNote> onAccepted;

  @override
  State<_AnimatedTrashDropTarget> createState() =>
      _AnimatedTrashDropTargetState();
}

class _AnimatedTrashDropTargetState extends State<_AnimatedTrashDropTarget> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<PlainNote>(
      key: const ValueKey('overview-trash-drop-target'),
      onWillAcceptWithDetails: (_) {
        if (!_hovered) setState(() => _hovered = true);
        return true;
      },
      onLeave: (_) {
        if (_hovered) setState(() => _hovered = false);
      },
      onAcceptWithDetails: (details) {
        if (_hovered) setState(() => _hovered = false);
        widget.onAccepted(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        return Tooltip(
          message: AppL10n(Localizations.localeOf(context).languageCode)
              .t('moveToTrash'),
          child: Semantics(
            label: AppL10n(Localizations.localeOf(context).languageCode)
                .t('moveToTrash'),
            child: AnimatedScale(
              duration: const Duration(milliseconds: 150),
              curve: Curves.easeOutBack,
              scale: _hovered ? 1.1 : 1,
              child: AnimatedContainer(
                key: ValueKey(
                  _hovered ? 'overview-trash-hovered' : 'overview-trash-idle',
                ),
                duration: const Duration(milliseconds: 150),
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: _hovered
                      ? scheme.errorContainer
                      : scheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _hovered
                        ? scheme.error.withValues(alpha: 0.72)
                        : scheme.outlineVariant.withValues(alpha: 0.78),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(
                        alpha: _hovered ? 0.18 : 0.1,
                      ),
                      blurRadius: _hovered ? 18 : 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  tween: Tween(end: _hovered ? 1 : 0),
                  builder: (context, progress, _) => CustomPaint(
                    painter: _TrashCanPainter(
                      progress: progress,
                      color: _hovered
                          ? scheme.onErrorContainer
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TrashCanPainter extends CustomPainter {
  const _TrashCanPainter({
    required this.progress,
    required this.color,
  });

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final centerX = size.width / 2;
    final body = RRect.fromRectAndRadius(
      Rect.fromLTRB(centerX - 12, 30, centerX + 12, 53),
      const Radius.circular(3.5),
    );
    canvas.drawRRect(body, paint);
    canvas.drawLine(Offset(centerX - 5, 36), Offset(centerX - 5, 47), paint);
    canvas.drawLine(Offset(centerX + 5, 36), Offset(centerX + 5, 47), paint);

    canvas.save();
    canvas.translate(centerX - 14, 28);
    canvas.rotate(-0.34 * progress);
    canvas.drawLine(const Offset(0, 0), const Offset(28, 0), paint);
    canvas.drawLine(const Offset(10, -5), const Offset(18, -5), paint);
    canvas.drawLine(const Offset(10, -5), const Offset(10, 0), paint);
    canvas.drawLine(const Offset(18, -5), const Offset(18, 0), paint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TrashCanPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color;
  }
}

class _CompactNoteColumn extends ConsumerWidget {
  const _CompactNoteColumn({
    required this.notes,
    required this.dragging,
    required this.dropIndex,
    required this.onDropIndexChanged,
    required this.onCommitReorder,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final List<({int index, PlainNote note})> notes;
  final bool dragging;
  final int? dropIndex;
  final ValueChanged<int?> onDropIndexChanged;
  final void Function(String draggedId, int targetIndex) onCommitReorder;
  final ValueChanged<PlainNote> onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        for (final entry in notes)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: DragTarget<PlainNote>(
              key: ValueKey('compact-note-drop-${entry.note.localId}'),
              onWillAcceptWithDetails: (_) => true,
              onMove: (details) {
                final box = context.findRenderObject() as RenderBox?;
                if (box == null || !box.hasSize) return;
                final local = box.globalToLocal(details.offset);
                final nextIndex = local.dy < box.size.height / 2
                    ? entry.index
                    : entry.index + 1;
                if (dropIndex != nextIndex) onDropIndexChanged(nextIndex);
              },
              onLeave: (_) {
                if (dragging) onDropIndexChanged(null);
              },
              onAcceptWithDetails: (details) => onCommitReorder(
                details.data.localId,
                dropIndex ?? entry.index,
              ),
              builder: (context, _, __) {
                final before = dropIndex == entry.index;
                final after = dropIndex == entry.index + 1;
                final card = _KeepNoteCard(
                  note: entry.note,
                  onTap: () => _openEditor(context, ref, entry.note),
                  onTogglePin: () => ref
                      .read(notesControllerProvider.notifier)
                      .togglePinned(entry.note),
                  onInvite: () => _showInviteSheet(context, ref, entry.note),
                  onReminder: () =>
                      _showReminderSheet(context, ref, entry.note),
                  onArchive: () => ref
                      .read(notesControllerProvider.notifier)
                      .changeState(entry.note, 'archived'),
                  onTrash: () => ref
                      .read(notesControllerProvider.notifier)
                      .changeState(entry.note, 'trashed'),
                  onRestore: () => ref
                      .read(notesControllerProvider.notifier)
                      .changeState(entry.note, 'active'),
                  onDeleteForever: () => ref
                      .read(notesControllerProvider.notifier)
                      .changeState(entry.note, 'deleted'),
                );
                return AnimatedPadding(
                  duration: const Duration(milliseconds: 140),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.only(
                    top: before ? 12 : 0,
                    bottom: after ? 12 : 0,
                  ),
                  child: _MeasuredNoteDraggable(
                    key: ValueKey('compact-note-drag-${entry.note.localId}'),
                    note: entry.note,
                    onDragStarted: () => onDragStarted(entry.note),
                    onDragEnded: onDragEnded,
                    childWhenDragging: Opacity(opacity: 0.34, child: card),
                    child: card,
                  ),
                );
              },
            ),
          ),
      ],
    );
  }
}

class _SideRail extends ConsumerWidget {
  const _SideRail();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final expanded = ref.watch(sideNavExpandedProvider);
    final bucket = ref.watch(noteBucketProvider);
    final canCreate = bucket == 'active' || bucket == 'reminders';
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: expanded ? 212 : 78,
      padding: EdgeInsets.fromLTRB(12, 10, expanded ? 12 : 10, 0),
      child: Column(
        crossAxisAlignment:
            expanded ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
        children: [
          if (canCreate) ...[
            _RailCreateButton(expanded: expanded),
            const SizedBox(height: 18),
          ],
          _RailButton(
            bucket: 'active',
            icon: LucideIcons.notebookText,
            label: l10n.t('notes'),
            expanded: expanded,
          ),
          const SizedBox(height: 6),
          _RailButton(
            bucket: 'reminders',
            icon: LucideIcons.bell,
            label: l10n.t('reminders'),
            expanded: expanded,
          ),
          const SizedBox(height: 6),
          _RailButton(
            bucket: 'archived',
            icon: LucideIcons.archive,
            label: l10n.t('archive'),
            expanded: expanded,
          ),
          const SizedBox(height: 6),
          _RailButton(
            bucket: 'trashed',
            icon: LucideIcons.trash,
            label: l10n.t('trash'),
            expanded: expanded,
          ),
        ],
      ),
    );
  }
}

class _RailCreateButton extends ConsumerWidget {
  const _RailCreateButton({required this.expanded});

  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final create = _createIntentFor(
      ref.watch(noteBucketProvider),
      ref.watch(l10nProvider),
    );
    if (create == null) return const SizedBox.shrink();
    return Tooltip(
      message: create.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(expanded ? 16 : 18),
        onTap: () => _createNoteForCurrentBucket(context, ref),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: expanded ? 50 : 46,
          width: expanded ? null : 46,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 0),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(expanded ? 16 : 18),
          ),
          child: Row(
            mainAxisAlignment:
                expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(create.icon, size: 21, color: scheme.onSurface),
              if (expanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    create.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSurface,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ],
          ),
        ),
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
          curve: Curves.easeOutCubic,
          height: 42,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.92)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment:
                expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? Theme.of(context).colorScheme.onSurface
                      : Theme.of(context).colorScheme.onSurfaceVariant),
              if (expanded)
                Expanded(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 14),
                      child: Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: selected
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                              fontWeight:
                                  selected ? FontWeight.w700 : FontWeight.w500,
                            ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileBottomNav extends ConsumerWidget {
  const _MobileBottomNav();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final bucket = ref.watch(noteBucketProvider);
    final selectedIndex = switch (bucket) {
      'reminders' => 1,
      'trashed' => 2,
      _ => 0,
    };
    return NavigationBar(
      height: 68,
      selectedIndex: selectedIndex,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      backgroundColor: Theme.of(context).colorScheme.surface,
      indicatorColor: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.9),
      destinations: [
        NavigationDestination(
          icon: const Icon(LucideIcons.notebookText),
          selectedIcon: const Icon(LucideIcons.notebookText),
          label: l10n.t('notes'),
        ),
        NavigationDestination(
          icon: const Icon(LucideIcons.bell),
          selectedIcon: const Icon(LucideIcons.bell),
          label: l10n.t('reminders'),
        ),
        NavigationDestination(
          icon: const Icon(LucideIcons.trash),
          selectedIcon: const Icon(LucideIcons.trash),
          label: l10n.t('trash'),
        ),
        NavigationDestination(
          icon: const Icon(LucideIcons.settings),
          selectedIcon: const Icon(LucideIcons.settings),
          label: l10n.t('settings'),
        ),
      ],
      onDestinationSelected: (index) {
        if (index == 3) {
          _openSettings(context);
          return;
        }
        ref.read(noteBucketProvider.notifier).state = switch (index) {
          1 => 'reminders',
          2 => 'trashed',
          _ => 'active',
        };
      },
    );
  }
}

class _SearchField extends ConsumerWidget {
  const _SearchField({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: TextField(
          onChanged: (value) =>
              ref.read(noteSearchProvider.notifier).state = value,
          decoration: InputDecoration(
            hintText: l10n.t('searchNotes'),
            prefixIcon: Padding(
              padding: EdgeInsets.only(left: compact ? 8 : 4),
              child: const Icon(LucideIcons.search, size: 19),
            ),
            prefixIconConstraints: BoxConstraints(minWidth: compact ? 48 : 44),
            filled: true,
            fillColor: Theme.of(context).colorScheme.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.5),
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.5),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          ),
        ),
      ),
    );
  }
}

class _EmailVerificationBanner extends ConsumerStatefulWidget {
  const _EmailVerificationBanner({required this.email});

  final String email;

  @override
  ConsumerState<_EmailVerificationBanner> createState() =>
      _EmailVerificationBannerState();
}

class _EmailVerificationBannerState
    extends ConsumerState<_EmailVerificationBanner> {
  Timer? _statusTimer;
  AppLifecycleListener? _lifecycleListener;
  var _refreshing = false;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(onResume: _refreshStatus);
    _statusTimer = Timer.periodic(
      const Duration(seconds: 20),
      (_) => _refreshStatus(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshStatus());
  }

  @override
  void dispose() {
    _statusTimer?.cancel();
    _lifecycleListener?.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    if (!mounted || _refreshing) return;
    _refreshing = true;
    try {
      await ref
          .read(authControllerProvider.notifier)
          .refreshEmailVerificationStatus();
    } on ApiException {
      // The banner remains available while the device is offline.
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showEmailVerificationDialog(context, ref, widget.email),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(LucideIcons.mailWarning,
                    size: 18, color: scheme.onSurface),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.t('emailConfirmBanner'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  l10n.t('enterCode'),
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void _showEmailVerificationDialog(
  BuildContext context,
  WidgetRef ref,
  String email,
) {
  showDialog<void>(
    context: context,
    builder: (_) => _EmailVerificationDialog(email: email),
  );
}

class _EmailVerificationDialog extends ConsumerStatefulWidget {
  const _EmailVerificationDialog({required this.email});

  final String email;

  @override
  ConsumerState<_EmailVerificationDialog> createState() =>
      _EmailVerificationDialogState();
}

class _EmailVerificationDialogState
    extends ConsumerState<_EmailVerificationDialog> {
  final _code = TextEditingController();
  var _busy = false;
  String? _message;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final scheme = Theme.of(context).colorScheme;
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(24),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
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
                      child: Icon(LucideIcons.mailCheck,
                          size: 21, color: scheme.onSurface),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        l10n.t('emailConfirmTitle'),
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    AppIconButton(
                      tooltip: l10n.t('close'),
                      icon: LucideIcons.x,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.t(
                    'emailConfirmDescription',
                    params: {'email': widget.email},
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  maxLength: 6,
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '123456',
                    prefixIcon: const Icon(LucideIcons.keyRound, size: 18),
                    filled: true,
                    fillColor:
                        scheme.surfaceContainerHighest.withValues(alpha: 0.46),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (_) => _confirm(),
                ),
                if (_message != null || _error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error ?? _message!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _error == null ? scheme.primary : scheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _resend,
                        icon: const Icon(LucideIcons.send),
                        label: Text(l10n.t('resend')),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy ? null : _confirm,
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(LucideIcons.circleCheck),
                        label: Text(l10n.t('confirm')),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _resend() async {
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await ref.read(authControllerProvider.notifier).resendEmailVerification();
      if (mounted) {
        setState(() => _message = ref.read(l10nProvider).t('codeResent'));
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = _mailErrorMessage(
              error,
              fallback: ref.read(l10nProvider).t('codeSendFailed'),
            ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length < 6) {
      setState(() => _error = ref.read(l10nProvider).t('completeCode'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _message = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .confirmEmailVerification(code);
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) {
        setState(() => _error = _mailErrorMessage(
              error,
              fallback: ref.read(l10nProvider).t('invalidCode'),
            ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _mailErrorMessage(Object error, {required String fallback}) {
    if (error is ApiException) return error.message;
    return fallback;
  }
}

class _CreateNoteFab extends StatefulWidget {
  const _CreateNoteFab({
    required this.onNewNote,
    required this.onNewReminder,
    required this.onNewList,
  });

  final VoidCallback onNewNote;
  final VoidCallback onNewReminder;
  final VoidCallback onNewList;

  @override
  State<_CreateNoteFab> createState() => _CreateNoteFabState();
}

class _CreateNoteFabState extends State<_CreateNoteFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curve;
  var _open = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _open = !_open);
    if (_open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  void _run(VoidCallback action) {
    _toggle();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n(Localizations.localeOf(context).languageCode);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: 270,
      height: 286,
      child: Stack(
        alignment: Alignment.bottomRight,
        clipBehavior: Clip.none,
        children: [
          if (_open)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _toggle,
                child: const SizedBox.expand(),
              ),
            ),
          _FabOption(
            animation: _curve,
            index: 2,
            icon: LucideIcons.listChecks,
            label: l10n.t('newChecklist'),
            onTap: () => _run(widget.onNewList),
          ),
          _FabOption(
            animation: _curve,
            index: 1,
            icon: LucideIcons.bellPlus,
            label: l10n.t('setReminder'),
            onTap: () => _run(widget.onNewReminder),
          ),
          _FabOption(
            animation: _curve,
            index: 0,
            icon: LucideIcons.filePlus2,
            label: l10n.t('newNote'),
            onTap: () => _run(widget.onNewNote),
          ),
          SizedBox(
            width: 66,
            height: 66,
            child: FloatingActionButton(
              tooltip: l10n.t('create'),
              elevation: _open ? 1 : 3,
              backgroundColor: _open
                  ? scheme.onSurface
                  : dark
                      ? scheme.surfaceContainerHighest
                      : scheme.surfaceContainer,
              foregroundColor: _open ? scheme.surface : scheme.onSurface,
              shape: const CircleBorder(),
              onPressed: _toggle,
              child: AnimatedRotation(
                turns: _open ? 0.125 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: const Icon(LucideIcons.plus, size: 32),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FabOption extends StatelessWidget {
  const _FabOption({
    required this.animation,
    required this.index,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Animation<double> animation;
  final int index;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final pillColor =
        dark ? scheme.surfaceContainerHighest : scheme.surfaceContainerLow;
    final textColor = scheme.onSurface;
    final bottom = 74 + index * 56.0;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final value = animation.value;
        return Positioned(
          right: 0,
          bottom: 24 + (bottom - 24) * value,
          child: IgnorePointer(
            ignoring: value < 0.85,
            child: Opacity(
              opacity: value,
              child: Transform.scale(
                scale: 0.9 + 0.1 * value,
                alignment: Alignment.centerRight,
                child: child,
              ),
            ),
          ),
        );
      },
      child: Material(
        color: pillColor,
        elevation: 2,
        shadowColor: Colors.black.withValues(alpha: dark ? 0.22 : 0.1),
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 26, 14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 19, color: textColor),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: textColor,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
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
    required this.onTogglePin,
    required this.onInvite,
    required this.onReminder,
    required this.onArchive,
    required this.onTrash,
    required this.onRestore,
    required this.onDeleteForever,
  });

  final PlainNote note;
  final VoidCallback onTap;
  final VoidCallback onTogglePin;
  final VoidCallback onInvite;
  final VoidCallback onReminder;
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
    final l10n = AppL10n(Localizations.localeOf(context).languageCode);
    final scheme = Theme.of(context).colorScheme;
    final bg = brandNoteSurfaceColor(context, note.color);
    final isPlainWhite = note.color == 0xffffffff;
    final showHoverActions = MediaQuery.sizeOf(context).width >= 700;
    final displayTitle =
        note.title.trim() == 'Untitled note' ? '' : note.title.trim();
    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: AnimatedScale(
        scale: 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: Material(
          color: isPlainWhite ? scheme.surface : bg,
          elevation: _hovered ? 1 : 0,
          shadowColor: Colors.black.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 132),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.fromLTRB(16, 15, 12, 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _hovered
                        ? scheme.outline.withValues(alpha: 0.72)
                        : scheme.outlineVariant.withValues(alpha: 0.58),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (displayTitle.isNotEmpty || note.pinned) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              displayTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          AnimatedOpacity(
                            opacity: _hovered || note.pinned ? 1 : 0,
                            duration: const Duration(milliseconds: 120),
                            child: AppIconButton(
                              tooltip:
                                  note.pinned ? l10n.t('unpin') : l10n.t('pin'),
                              icon: note.pinned
                                  ? LucideIcons.pin
                                  : LucideIcons.pinOff,
                              selected: note.pinned,
                              onPressed: widget.onTogglePin,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                    ],
                    note.checklist.isNotEmpty && note.body.trim().isEmpty
                        ? _ChecklistPreview(items: note.checklist)
                        : _FormattedPreview(
                            text: note.body,
                            delta: note.richTextDelta,
                          ),
                    const SizedBox(height: 14),
                    SizedBox(
                      height: 36,
                      child: Row(
                        children: [
                          if (note.checklist.isNotEmpty)
                            _MetaPill(
                              icon: LucideIcons.squareCheck,
                              label:
                                  '${note.checklist.where((item) => item.done).length}/${note.checklist.length}',
                            ),
                          if (note.conflicted)
                            _MetaPill(
                              icon: LucideIcons.circleAlert,
                              label: l10n.t('conflict'),
                              color: scheme.error,
                            ),
                          if (note.dirty)
                            _MetaPill(
                              icon: LucideIcons.cloudUpload,
                              label: l10n.t('synced'),
                              color: scheme.tertiary,
                            ),
                          if (note.reminderAt != null)
                            _MetaPill(
                              icon: LucideIcons.bell,
                              label: _formatReminder(note.reminderAt!, l10n),
                              color: scheme.primary,
                            ),
                          if (note.shared)
                            _MetaPill(
                              icon: LucideIcons.users,
                              label: l10n.t('shared'),
                              color: scheme.primary,
                            ),
                          const Spacer(),
                          if (_hovered && showHoverActions)
                            AnimatedOpacity(
                              opacity: 1,
                              duration: const Duration(milliseconds: 120),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (note.state != 'active')
                                    AppIconButton(
                                      tooltip: l10n.t('restore'),
                                      icon: LucideIcons.rotateCcw,
                                      onPressed: widget.onRestore,
                                    ),
                                  if (note.state == 'active')
                                    AppIconButton(
                                      tooltip: l10n.t('archiveAction'),
                                      icon: LucideIcons.archive,
                                      onPressed: widget.onArchive,
                                    ),
                                  if (note.state == 'active' &&
                                      note.reminderAt == null)
                                    AppIconButton(
                                      tooltip: l10n.t('collaboratorInvite'),
                                      icon: note.shared
                                          ? LucideIcons.users
                                          : LucideIcons.userPlus,
                                      onPressed: widget.onInvite,
                                    ),
                                  if (note.state != 'trashed')
                                    AppIconButton(
                                      tooltip: l10n.t('reminder'),
                                      icon: LucideIcons.bell,
                                      onPressed: widget.onReminder,
                                    ),
                                  if (note.state != 'trashed')
                                    AppIconButton(
                                      tooltip: l10n.t('trash'),
                                      icon: LucideIcons.trash,
                                      onPressed: widget.onTrash,
                                    )
                                  else
                                    AppIconButton(
                                      tooltip: l10n.t('deleteForever'),
                                      icon: LucideIcons.trash2,
                                      onPressed: widget.onDeleteForever,
                                    ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MeasuredNoteDraggable extends StatefulWidget {
  const _MeasuredNoteDraggable({
    super.key,
    required this.note,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.childWhenDragging,
    required this.child,
  });

  final PlainNote note;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;
  final Widget childWhenDragging;
  final Widget child;

  @override
  State<_MeasuredNoteDraggable> createState() => _MeasuredNoteDraggableState();
}

class _MeasuredNoteDraggableState extends State<_MeasuredNoteDraggable> {
  final _cardKey = GlobalKey();
  Size? _dragFeedbackSize;

  Size? get _cardSize {
    final renderObject = _cardKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.size;
  }

  @override
  Widget build(BuildContext context) {
    return LongPressDraggable<PlainNote>(
      data: widget.note,
      feedback: _NoteDragFeedback(
        key: ValueKey('note-drag-feedback-${widget.note.localId}'),
        sizeReader: () => _dragFeedbackSize ?? _cardSize,
        child: widget.child,
      ),
      onDragStarted: _handleDragStarted,
      onDraggableCanceled: (_, __) => _handleDragEnded(),
      onDragEnd: (_) => _handleDragEnded(),
      onDragCompleted: _handleDragEnded,
      childWhenDragging: widget.childWhenDragging,
      child: KeyedSubtree(
        key: _cardKey,
        child: widget.child,
      ),
    );
  }

  void _handleDragStarted() {
    _dragFeedbackSize = _cardSize;
    widget.onDragStarted();
  }

  void _handleDragEnded() {
    _dragFeedbackSize = null;
    widget.onDragEnded();
  }
}

class _NoteDragFeedback extends StatelessWidget {
  const _NoteDragFeedback({
    super.key,
    required this.sizeReader,
    required this.child,
  });

  final Size? Function() sizeReader;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = sizeReader() ?? const Size(260, 170);
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: child,
      ),
    );
  }
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
                  item.done ? LucideIcons.squareCheck : LucideIcons.square,
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
  const _FormattedPreview({required this.text, this.delta});

  final String text;
  final List<Map<String, dynamic>>? delta;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.35);
    if (delta != null && delta!.isNotEmpty) {
      return _buildDeltaPreview(context, base);
    }
    final lines = text.trim().isEmpty ? [''] : text.trim().split('\n').toList();
    final visibleLines = <({String line, bool code})>[];
    var inCodeBlock = false;
    for (final line in lines) {
      if (line.trim() == '```') {
        inCodeBlock = !inCodeBlock;
        continue;
      }
      visibleLines.add((line: line, code: inCodeBlock));
      if (visibleLines.length == 7) break;
    }
    return Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < visibleLines.length; i++) ...[
            TextSpan(
              text: _clean(visibleLines[i].line),
              style: _styleFor(
                context,
                base,
                visibleLines[i].line,
                inCodeBlock: visibleLines[i].code,
              ),
            ),
            if (i != visibleLines.length - 1) const TextSpan(text: '\n'),
          ],
        ],
      ),
      maxLines: 7,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildDeltaPreview(BuildContext context, TextStyle? base) {
    final lines = <TextSpan>[];
    var current = <InlineSpan>[];
    var orderedIndex = 1;

    void finishLine(Map<String, dynamic> blockAttributes) {
      if (lines.length >= 7) return;
      final list = blockAttributes['list'];
      final prefix = switch (list) {
        'bullet' => '\u2022 ',
        'ordered' => '${orderedIndex++}. ',
        _ => '',
      };
      if (list != 'ordered') orderedIndex = 1;
      lines.add(
        TextSpan(
          style: _blockStyle(context, base, blockAttributes),
          children: [
            if (prefix.isNotEmpty)
              TextSpan(
                text: prefix,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ...current,
          ],
        ),
      );
      current = <InlineSpan>[];
    }

    for (final operation in delta!) {
      if (lines.length >= 7) break;
      final insert = operation['insert'];
      if (insert is! String) continue;
      final attributes = operation['attributes'] is Map
          ? Map<String, dynamic>.from(operation['attributes'] as Map)
          : <String, dynamic>{};
      final parts = insert.split('\n');
      for (var index = 0; index < parts.length; index += 1) {
        if (parts[index].isNotEmpty) {
          current.add(
            TextSpan(
              text: parts[index],
              style: _inlineStyle(context, base, attributes),
            ),
          );
        }
        if (index != parts.length - 1) finishLine(attributes);
        if (lines.length >= 7) break;
      }
    }
    if (current.isNotEmpty && lines.length < 7) {
      finishLine(const <String, dynamic>{});
    }
    if (lines.isEmpty) lines.add(TextSpan(text: '', style: base));

    return Text.rich(
      TextSpan(
        children: [
          for (var index = 0; index < lines.length; index += 1) ...[
            lines[index],
            if (index != lines.length - 1) const TextSpan(text: '\n'),
          ],
        ],
      ),
      maxLines: 7,
      overflow: TextOverflow.ellipsis,
    );
  }

  TextStyle? _inlineStyle(
    BuildContext context,
    TextStyle? base,
    Map<String, dynamic> attributes,
  ) {
    final decorations = <TextDecoration>[
      if (attributes['strike'] == true) TextDecoration.lineThrough,
      if (attributes['underline'] == true || attributes['link'] != null)
        TextDecoration.underline,
    ];
    return base?.copyWith(
      fontWeight:
          attributes['bold'] == true ? FontWeight.w700 : FontWeight.normal,
      fontStyle:
          attributes['italic'] == true ? FontStyle.italic : FontStyle.normal,
      decoration:
          decorations.isEmpty ? null : TextDecoration.combine(decorations),
      color: attributes['link'] != null
          ? Theme.of(context).colorScheme.primary
          : null,
      fontFamily: attributes['code'] == true ? 'monospace' : null,
      backgroundColor: attributes['code'] == true
          ? Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.58)
          : null,
    );
  }

  TextStyle? _blockStyle(
    BuildContext context,
    TextStyle? base,
    Map<String, dynamic> attributes,
  ) {
    final header = attributes['header'];
    if (header == 1) {
      return base?.copyWith(fontSize: 18, fontWeight: FontWeight.w700);
    }
    if (header == 2) {
      return base?.copyWith(fontSize: 16, fontWeight: FontWeight.w700);
    }
    if (header == 3) return base?.copyWith(fontWeight: FontWeight.w700);
    if (attributes['code-block'] == true) {
      return base?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.58),
      );
    }
    return base;
  }

  TextStyle? _styleFor(
    BuildContext context,
    TextStyle? base,
    String line, {
    required bool inCodeBlock,
  }) {
    if (inCodeBlock) {
      return base?.copyWith(
        fontFamily: 'monospace',
        backgroundColor: Theme.of(context)
            .colorScheme
            .surfaceContainerHighest
            .withValues(alpha: 0.58),
      );
    }
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
    if (_containsItalicMarker(line)) {
      return base?.copyWith(fontStyle: FontStyle.italic);
    }
    if (line.contains('~~')) {
      return base?.copyWith(decoration: TextDecoration.lineThrough);
    }
    if (RegExp(r'\[(.*?)\]\((.*?)\)').hasMatch(line)) {
      return base?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        decoration: TextDecoration.underline,
      );
    }
    if (line.contains('`')) return base?.copyWith(fontFamily: 'monospace');
    return base;
  }

  String _clean(String line) {
    final cleaned = line
        .replaceFirst(RegExp(r'^#{1,3}\s'), '')
        .replaceFirst(RegExp(r'^>\s'), '')
        .replaceAll('**', '')
        .replaceAll('~~', '')
        .replaceAll('`', '')
        .replaceAll('<u>', '')
        .replaceAll('</u>', '')
        .replaceAll('```', '')
        .replaceAllMapped(
            RegExp(r'\[(.*?)\]\((.*?)\)'), (match) => match.group(1) ?? '');
    return _stripItalicMarkers(cleaned);
  }

  bool _containsItalicMarker(String line) {
    for (var index = 0; index < line.length; index++) {
      if (_isItalicMarker(line, index)) return true;
    }
    return false;
  }

  String _stripItalicMarkers(String line) {
    final buffer = StringBuffer();
    for (var index = 0; index < line.length; index++) {
      if (!_isItalicMarker(line, index)) buffer.write(line[index]);
    }
    return buffer.toString();
  }

  bool _isItalicMarker(String line, int index) {
    if (!line.startsWith('_', index)) return false;
    final beforeIsWord =
        index > 0 && _isWordCharacter(line.codeUnitAt(index - 1));
    final afterIsWord =
        index + 1 < line.length && _isWordCharacter(line.codeUnitAt(index + 1));
    return beforeIsWord != afterIsWord;
  }

  bool _isWordCharacter(int codeUnit) {
    return (codeUnit >= 48 && codeUnit <= 57) ||
        (codeUnit >= 65 && codeUnit <= 90) ||
        (codeUnit >= 97 && codeUnit <= 122) ||
        codeUnit >= 128;
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

String _formatReminder(DateTime value, [AppL10n? l10n]) {
  final local = value.toLocal();
  final now = DateTime.now();
  final sameDay = local.year == now.year &&
      local.month == now.month &&
      local.day == now.day;
  final date = sameDay
      ? (l10n?.t('today') ?? 'Today')
      : '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$date $time';
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
          LucideIcons.cloudCheck,
          l10n.t('saved'),
          Theme.of(context).colorScheme.tertiary
        ),
      SyncStatus.saving => (
          LucideIcons.clock3,
          l10n.t('saving'),
          Theme.of(context).colorScheme.primary
        ),
      SyncStatus.syncing => (
          LucideIcons.refreshCw,
          l10n.t('syncing'),
          Theme.of(context).colorScheme.primary
        ),
      SyncStatus.offline => (
          LucideIcons.cloudOff,
          l10n.t('offline'),
          Theme.of(context).colorScheme.error
        ),
      SyncStatus.conflict => (
          LucideIcons.circleAlert,
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
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
  const _AccountButton({
    required this.email,
    this.compact = false,
  });

  final String email;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final initial = email.isEmpty ? '?' : email.substring(0, 1).toUpperCase();
    return Tooltip(
      message: email,
      child: GestureDetector(
        onTap: () => _showAccountSideSheet(context, ref, email),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
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
  final l10n = ref.read(l10nProvider);
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l10n.t('closeMenu'),
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
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      borderRadius: const BorderRadius.horizontal(right: Radius.circular(18)),
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
                    const SafernotesLogo(size: 38),
                    const SizedBox(width: 12),
                    Text(
                      l10n.t('appName'),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const Spacer(),
                    AppIconButton(
                      tooltip: l10n.t('close'),
                      icon: LucideIcons.x,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Column(
                  children: [
                    _MobileMenuButton(
                      bucket: 'active',
                      icon: LucideIcons.notebookText,
                      label: l10n.t('notes'),
                    ),
                    _MobileMenuButton(
                      bucket: 'reminders',
                      icon: LucideIcons.bell,
                      label: l10n.t('reminders'),
                    ),
                    _MobileMenuButton(
                      bucket: 'archived',
                      icon: LucideIcons.archive,
                      label: l10n.t('archive'),
                    ),
                    _MobileMenuButton(
                      bucket: 'trashed',
                      icon: LucideIcons.trash,
                      label: l10n.t('trash'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.28),
                ),
                const Spacer(),
                const _SyncIndicator(showLabel: true),
                const SizedBox(height: 4),
                _MenuActionRow(
                  icon: LucideIcons.settings,
                  label: l10n.t('settings'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openSettings(context);
                  },
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
    return _MenuActionRow(
      icon: icon,
      label: label,
      selected: selected,
      onTap: () {
        ref.read(noteBucketProvider.notifier).state = bucket;
        Navigator.of(context).pop();
      },
    );
  }
}

class _MenuActionRow extends StatefulWidget {
  const _MenuActionRow({
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  @override
  State<_MenuActionRow> createState() => _MenuActionRowState();
}

class _MenuActionRowState extends State<_MenuActionRow> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: widget.selected
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.92)
                : _hovered
                    ? scheme.surfaceContainerHighest.withValues(alpha: 0.32)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: widget.selected
                    ? scheme.onSurface
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight:
                            widget.selected ? FontWeight.w700 : FontWeight.w500,
                        color: widget.selected
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                ),
              ),
              AnimatedScale(
                scale: widget.selected ? 1 : 0.76,
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: widget.selected ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Icon(
                    LucideIcons.check,
                    size: 18,
                    color: scheme.onSurface,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

void _showAccountSideSheet(BuildContext context, WidgetRef ref, String email) {
  final l10n = ref.read(l10nProvider);
  showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: l10n.t('closeAccount'),
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
    final l10n = ref.watch(l10nProvider);
    final initial = email.isEmpty ? '?' : email.substring(0, 1).toUpperCase();
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
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
                    Text(l10n.t('profile'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            )),
                    const Spacer(),
                    AppIconButton(
                      tooltip: l10n.t('close'),
                      icon: LucideIcons.x,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        initial,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            email.isEmpty ? l10n.t('localAccount') : email,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(LucideIcons.circleCheck,
                                  size: 15, color: scheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Text(
                                l10n.t('signedIn'),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Divider(
                  height: 1,
                  color: scheme.outlineVariant.withValues(alpha: 0.28),
                ),
                const SizedBox(height: 12),
                _AccountActionTile(
                  icon: LucideIcons.settings,
                  label: l10n.t('settings'),
                  onTap: () {
                    Navigator.of(context).pop();
                    _openSettings(context);
                  },
                ),
                _AccountActionTile(
                  icon: LucideIcons.logOut,
                  label: l10n.t('logout'),
                  destructive: true,
                  onTap: () {
                    Navigator.of(context).pop();
                    ref.read(authControllerProvider.notifier).signOut();
                  },
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountActionTile extends StatefulWidget {
  const _AccountActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  @override
  State<_AccountActionTile> createState() => _AccountActionTileState();
}

class _AccountActionTileState extends State<_AccountActionTile> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.destructive ? scheme.error : scheme.onSurface;
    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: _hovered
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.32)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 18, color: color),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Icon(LucideIcons.chevronRight,
                  size: 17, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

void _showInviteSheet(BuildContext context, WidgetRef ref, PlainNote note) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
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
                            icon: LucideIcons.x,
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
                                    ? LucideIcons.mail
                                    : LucideIcons.userRoundCheck,
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
                                icon: LucideIcons.userRoundX,
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
                              label: l10n.t('canEdit'),
                              onTap: () => onRoleChanged('editor'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _InviteRoleTile(
                              selected: role == 'viewer',
                              icon: LucideIcons.eye,
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
                            : const Icon(LucideIcons.send),
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
                  ? LucideIcons.mailOpen
                  : LucideIcons.send,
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

Future<void> _showReminderSheet(
    BuildContext context, WidgetRef ref, PlainNote note) async {
  var duplicateShared = false;
  if (note.shared && note.reminderAt == null) {
    duplicateShared = await _confirmDuplicateReminder(context) ?? false;
    if (!duplicateShared) return;
  }
  if (!context.mounted) return;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReminderSheet(
      note: note,
      duplicateShared: duplicateShared,
    ),
  );
}

Future<void> _startReminderFlow(BuildContext context, WidgetRef ref) async {
  final notes = ref.read(notesControllerProvider).valueOrNull ?? const [];
  final candidates = notes
      .where((note) =>
          note.state == 'active' &&
          note.reminderAt == null &&
          note.state != 'deleted' &&
          note.state != 'trashed')
      .toList()
    ..sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
  final selected = await showModalBottomSheet<PlainNote>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReminderNotePicker(notes: candidates),
  );
  if (selected == null || !context.mounted) return;
  await _showReminderSheet(context, ref, selected);
}

class _ReminderNotePicker extends StatefulWidget {
  const _ReminderNotePicker({required this.notes});

  final List<PlainNote> notes;

  @override
  State<_ReminderNotePicker> createState() => _ReminderNotePickerState();
}

class _ReminderNotePickerState extends State<_ReminderNotePicker> {
  final _search = TextEditingController();
  var _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = AppL10n(Localizations.localeOf(context).languageCode);
    final filtered = widget.notes.where((note) {
      if (_query.isEmpty) return true;
      final checklist = note.checklist.map((item) => item.text).join(' ');
      return '${note.title} ${note.body} $checklist'
          .toLowerCase()
          .contains(_query);
    }).toList();
    final height = (MediaQuery.sizeOf(context).height * 0.72)
        .clamp(360.0, 640.0)
        .toDouble();
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
              constraints: const BoxConstraints(maxWidth: 560),
              child: SizedBox(
                key: const ValueKey('reminder-note-picker'),
                height: height,
                child: Material(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  borderRadius: BorderRadius.circular(20),
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Icon(LucideIcons.bellPlus,
                                size: 21, color: scheme.onSurface),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                l10n.t('chooseNote'),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            AppIconButton(
                              tooltip: l10n.t('close'),
                              icon: LucideIcons.x,
                              onPressed: () => Navigator.of(context).pop(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          key: const ValueKey('reminder-note-search'),
                          controller: _search,
                          onChanged: (value) => setState(
                              () => _query = value.trim().toLowerCase()),
                          decoration: InputDecoration(
                            hintText: l10n.t('searchNotes'),
                            prefixIcon:
                                const Icon(LucideIcons.search, size: 18),
                            filled: true,
                            fillColor: scheme.surfaceContainerHighest
                                .withValues(alpha: 0.46),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: BorderSide.none,
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Expanded(
                          child: filtered.isEmpty
                              ? _ReminderPickerEmptyState(
                                  searchEmpty: widget.notes.isNotEmpty,
                                  l10n: l10n,
                                )
                              : ListView.builder(
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final note = filtered[index];
                                    return _ReminderNoteRow(
                                      key: ValueKey(
                                          'reminder-note-${note.localId}'),
                                      note: note,
                                      l10n: l10n,
                                      onTap: () =>
                                          Navigator.of(context).pop(note),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
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

class _ReminderNoteRow extends StatelessWidget {
  const _ReminderNoteRow({
    super.key,
    required this.note,
    required this.l10n,
    required this.onTap,
  });

  final PlainNote note;
  final AppL10n l10n;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _reminderNoteTitle(note, l10n);
    final preview = _reminderNotePreview(note, l10n);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
        child: Row(
          children: [
            SizedBox.square(
              dimension: 40,
              child: Icon(
                note.checklist.isEmpty
                    ? LucideIcons.notebookText
                    : LucideIcons.listChecks,
                size: 19,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Icon(LucideIcons.chevronRight,
                size: 18, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _ReminderPickerEmptyState extends StatelessWidget {
  const _ReminderPickerEmptyState({
    required this.searchEmpty,
    required this.l10n,
  });

  final bool searchEmpty;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          l10n.t(searchEmpty ? 'noMatchingNote' : 'createNoteFirst'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

String _reminderNotePreview(PlainNote note, AppL10n l10n) {
  if (note.body.trim().isNotEmpty) return note.body.trim();
  final checklist = note.checklist
      .where((item) => item.text.trim().isNotEmpty)
      .map((item) => item.text.trim())
      .take(3)
      .join(', ');
  if (checklist.isNotEmpty) return checklist;
  return l10n.t('emptyNote');
}

String _reminderNoteTitle(PlainNote note, AppL10n l10n) {
  if (note.title.trim().isEmpty || note.title == 'Untitled note') {
    return l10n.t('untitledNote');
  }
  return note.title.trim();
}

Future<bool?> _confirmDuplicateReminder(BuildContext context) {
  final l10n = AppL10n(Localizations.localeOf(context).languageCode);
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

class _ReminderSheet extends ConsumerStatefulWidget {
  const _ReminderSheet({
    required this.note,
    required this.duplicateShared,
  });

  final PlainNote note;
  final bool duplicateShared;

  @override
  ConsumerState<_ReminderSheet> createState() => _ReminderSheetState();
}

class _ReminderSheetState extends ConsumerState<_ReminderSheet> {
  late DateTime _selected = widget.note.reminderAt?.toLocal() ??
      DateTime.now().add(const Duration(hours: 1));
  var _busy = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = ref.watch(l10nProvider);
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
                              l10n.t('reminder'),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                          AppIconButton(
                            tooltip: l10n.t('close'),
                            icon: LucideIcons.x,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _reminderNoteTitle(widget.note, l10n),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 16),
                      _ReminderPickTile(
                        icon: LucideIcons.calendar,
                        label: l10n.t('date'),
                        value:
                            '${_selected.day.toString().padLeft(2, '0')}.${_selected.month.toString().padLeft(2, '0')}.${_selected.year}',
                        onTap: _pickDate,
                      ),
                      const SizedBox(height: 10),
                      _ReminderPickTile(
                        icon: LucideIcons.clock3,
                        label: l10n.t('time'),
                        value:
                            '${_selected.hour.toString().padLeft(2, '0')}:${_selected.minute.toString().padLeft(2, '0')}',
                        onTap: _pickTime,
                      ),
                      const SizedBox(height: 18),
                      FilledButton.icon(
                        onPressed: _busy ? null : () => _save(_selected),
                        icon: _busy
                            ? const SizedBox.square(
                                dimension: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(LucideIcons.bellRing),
                        label: Text(l10n.t('setReminder')),
                      ),
                      if (widget.note.reminderAt != null) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _busy ? null : () => _save(null),
                          icon: const Icon(LucideIcons.bellOff),
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

  Future<void> _save(DateTime? reminderAt) async {
    setState(() => _busy = true);
    if (reminderAt != null) await requestReminderPermission();
    if (widget.duplicateShared && reminderAt != null) {
      await ref.read(notesControllerProvider.notifier).duplicateAsReminder(
            source: widget.note,
            reminderAt: reminderAt.toUtc(),
          );
    } else {
      await ref.read(notesControllerProvider.notifier).setReminder(
            widget.note,
            reminderAt?.toUtc(),
          );
    }
    if (!mounted) return;
    Navigator.of(context).pop();
    _showReminderFeedback(
      context,
      ref,
      reminderAt != null,
      duplicated: widget.duplicateShared && reminderAt != null,
    );
  }
}

void _showReminderFeedback(BuildContext context, WidgetRef ref, bool added,
    {bool duplicated = false}) {
  final l10n = ref.read(l10nProvider);
  final messenger = ScaffoldMessenger.of(context);
  messenger.clearSnackBars();
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        l10n.t(
          added
              ? duplicated
                  ? 'reminderDuplicateAdded'
                  : 'reminderAdded'
              : 'reminderRemoved',
        ),
      ),
      action: added
          ? SnackBarAction(
              label: l10n.t('view'),
              onPressed: () {
                ref.read(noteBucketProvider.notifier).state = 'reminders';
              },
            )
          : null,
    ),
  );
}

class _ReminderPickTile extends StatelessWidget {
  const _ReminderPickTile({
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
              LucideIcons.notebookText,
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
    final l10n = AppL10n(Localizations.localeOf(context).languageCode);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.circleAlert,
                color: Theme.of(context).colorScheme.error, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(LucideIcons.refreshCw),
                label: Text(l10n.t('retry'))),
          ],
        ),
      ),
    );
  }
}

class _CreateIntent {
  const _CreateIntent({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

_CreateIntent? _createIntentFor(String bucket, AppL10n l10n) {
  return switch (bucket) {
    'active' => _CreateIntent(
        icon: LucideIcons.filePlus2,
        label: l10n.t('newNote'),
      ),
    'reminders' => _CreateIntent(
        icon: LucideIcons.bellPlus,
        label: l10n.t('setReminder'),
      ),
    _ => null,
  };
}

enum _CreateAction { note, list }

void _createNoteFromAction(
  BuildContext context,
  WidgetRef ref,
  _CreateAction action,
) {
  final controller = ref.read(notesControllerProvider.notifier);
  final note = switch (action) {
    _CreateAction.note => controller.createEmptyNote(),
    _CreateAction.list => controller.createChecklistNote(),
  };
  _openEditor(context, ref, note);
}

void _createNoteForCurrentBucket(BuildContext context, WidgetRef ref) {
  if (ref.read(noteBucketProvider) == 'reminders') {
    unawaited(_startReminderFlow(context, ref));
    return;
  }
  final controller = ref.read(notesControllerProvider.notifier);
  final note = switch (ref.read(noteBucketProvider)) {
    'active' => controller.createEmptyNote(),
    _ => null,
  };
  if (note == null) return;
  _openEditor(context, ref, note);
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

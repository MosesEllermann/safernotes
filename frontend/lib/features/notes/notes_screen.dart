import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safernotes_app/shared/theme/app_icons.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/notes/note_editor_screen.dart';
import 'package:safernotes_app/features/notes/notes_controller.dart';
import 'package:safernotes_app/features/settings/settings_screen.dart';
import 'package:safernotes_app/shared/app/app_l10n.dart';
import 'package:safernotes_app/shared/app/app_preferences.dart';
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
    final noteOverviewLayout =
        ref.watch(appPreferencesProvider).valueOrNull?.noteOverviewLayout ??
            NoteOverviewLayout.cards;
    return DecoratedBox(
      key: const ValueKey('notes-app-canvas'),
      decoration: appCanvasDecoration(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        extendBody: !desktop,
        appBar: desktop
            ? AppBar(
                toolbarHeight: 76,
                titleSpacing: 12,
                surfaceTintColor: Colors.transparent,
                backgroundColor: Colors.transparent,
                title: Row(
                  children: [
                    AppIconButton(
                      tooltip: l10n.t('menu'),
                      icon: AppIcons.panelLeft,
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
                ),
                actions: [
                  const _SyncIndicator(),
                  AppIconButton(
                    key: const ValueKey('note-overview-layout-toggle'),
                    tooltip: l10n.t(
                      noteOverviewLayout == NoteOverviewLayout.cards
                          ? 'switchToListView'
                          : 'switchToCardsView',
                    ),
                    icon: noteOverviewLayout == NoteOverviewLayout.cards
                        ? AppIcons.columns2
                        : AppIcons.grid2X2,
                    onPressed: () => ref
                        .read(appPreferencesProvider.notifier)
                        .setNoteOverviewLayout(
                          noteOverviewLayout == NoteOverviewLayout.cards
                              ? NoteOverviewLayout.list
                              : NoteOverviewLayout.cards,
                        ),
                  ),
                  AppIconButton(
                    tooltip: l10n.t('settings'),
                    icon: AppIcons.settings,
                    onPressed: () => _openSettings(context),
                  ),
                  _AccountButton(email: session?.email ?? ''),
                  const SizedBox(width: 8),
                ],
              )
            : null,
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
                    layout: noteOverviewLayout,
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
      icon: const Icon(AppIcons.userRoundPlus),
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
    required this.layout,
  });

  final List<PlainNote> notes;
  final String email;
  final NoteOverviewLayout layout;

  @override
  ConsumerState<_KeepWorkspace> createState() => _KeepWorkspaceState();
}

class _KeepWorkspaceState extends ConsumerState<_KeepWorkspace> {
  String? _draggedId;
  int? _dropIndex;
  String? _selectedNoteId;
  final _trashHovering = ValueNotifier(false);
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
    _trashHovering.dispose();
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
    final listLayout = widget.layout == NoteOverviewLayout.list;
    final splitLayout = wide && listLayout;
    final showTrashTarget = dragging && bucket != 'trashed';
    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide) const _SideRail(),
            Expanded(
              child: Column(
                children: [
                  _WorkspaceHeader(
                    noteCount: baseNotes.length,
                    compact: compact,
                    wide: wide,
                    email: widget.email,
                    layout: widget.layout,
                  ),
                  Expanded(
                    child: splitLayout
                        ? _buildSplitOverview(baseNotes, bucket)
                        : listLayout
                            ? _buildMobileList(baseNotes, bucket)
                            : _buildCardOverview(
                                sourceNotes: baseNotes,
                                filtered: filtered,
                                compact: compact,
                                wide: wide,
                                screenWidth: screenWidth,
                                dragging: dragging,
                                bucket: bucket,
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
                    onHoverChanged: (hovering) {
                      _trashHovering.value = hovering;
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCardOverview({
    required List<PlainNote> sourceNotes,
    required List<PlainNote> filtered,
    required bool compact,
    required bool wide,
    required double screenWidth,
    required bool dragging,
    required String bucket,
  }) {
    final noteColumnCount = compact ? 2 : _noteColumnCount(screenWidth, wide);
    return CustomScrollView(
      key: const ValueKey('cards-note-overview'),
      slivers: [
        SliverToBoxAdapter(child: SizedBox(height: wide ? 8 : 4)),
        if (filtered.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(),
          )
        else
          SliverPadding(
            padding: compact
                ? const EdgeInsets.fromLTRB(16, 0, 16, 104)
                : EdgeInsets.fromLTRB(
                    wide ? 32 : 12,
                    0,
                    wide ? 32 : 12,
                    48,
                  ),
            sliver: SliverToBoxAdapter(
              child: _AnimatedCardGrid(
                sourceNotes: sourceNotes,
                notes: filtered,
                columnCount: noteColumnCount,
                dropIndex: _dropIndex,
                onDropIndexChanged: _setDropIndex,
                onCommitReorder: (draggedId, targetIndex) =>
                    _commitReorder(draggedId, targetIndex, bucket),
                onDragStarted: _startDrag,
                onDragEnded: _clearDragPreview,
                trashHovering: _trashHovering,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMobileList(List<PlainNote> notes, String bucket) {
    if (notes.isEmpty) return const _EmptyState();
    return _NoteListPane(
      key: const ValueKey('mobile-note-list'),
      notes: notes,
      bottomPadding: 96,
      dragging: _draggedId != null,
      dropIndex: _dropIndex,
      trashHovering: _trashHovering,
      onDropIndexChanged: _setDropIndex,
      onCommitReorder: (draggedId, targetIndex) =>
          _commitReorder(draggedId, targetIndex, bucket),
      onDragStarted: _startDrag,
      onDragEnded: _clearDragPreview,
      onSelected: (note) => _openEditor(context, ref, note),
    );
  }

  Widget _buildSplitOverview(List<PlainNote> notes, String bucket) {
    final selected = _selectedNote(notes);
    return Row(
      key: const ValueKey('desktop-split-layout'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: _NoteListPane(
            key: const ValueKey('desktop-note-list-pane'),
            notes: notes,
            selectedNoteId: selected?.localId,
            dragging: _draggedId != null,
            dropIndex: _dropIndex,
            trashHovering: _trashHovering,
            onDropIndexChanged: _setDropIndex,
            onCommitReorder: (draggedId, targetIndex) =>
                _commitReorder(draggedId, targetIndex, bucket),
            onDragStarted: _startDrag,
            onDragEnded: _clearDragPreview,
            onSelected: (note) {
              if (_selectedNoteId == note.localId) return;
              setState(() => _selectedNoteId = note.localId);
            },
          ),
        ),
        Expanded(
          key: const ValueKey('desktop-note-editor-pane'),
          flex: 7,
          child: ClipRRect(
            key: const ValueKey('desktop-note-editor-frame'),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(12),
            ),
            child: CustomPaint(
              key: const ValueKey('desktop-note-editor-border'),
              foregroundPainter: _TopLeftBorderPainter(
                color: Theme.of(context)
                    .colorScheme
                    .outlineVariant
                    .withValues(alpha: 0.42),
              ),
              child: selected == null
                  ? const _SelectNoteState()
                  : NoteEditorPanel(note: selected, embedded: true),
            ),
          ),
        ),
      ],
    );
  }

  PlainNote? _selectedNote(List<PlainNote> notes) {
    if (notes.isEmpty) return null;
    for (final note in notes) {
      if (note.localId == _selectedNoteId) return note;
    }
    return notes.first;
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
    _trashHovering.value = false;
    setState(() {
      _draggedId = note.localId;
      _dropIndex = null;
    });
  }

  void _clearDragPreview() {
    if (!mounted) return;
    _trashHovering.value = false;
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

class _WorkspaceHeader extends ConsumerWidget {
  const _WorkspaceHeader({
    required this.noteCount,
    required this.compact,
    required this.wide,
    required this.email,
    required this.layout,
  });

  final int noteCount;
  final bool compact;
  final bool wide;
  final String email;
  final NoteOverviewLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final bucket = ref.watch(noteBucketProvider);
    final title = switch (bucket) {
      'reminders' => l10n.t('reminders'),
      'archived' => l10n.t('archive'),
      'trashed' => l10n.t('trash'),
      _ => l10n.t('notes'),
    };
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 32,
        wide ? 20 : (compact ? 16 : 10),
        compact ? 16 : 32,
        compact ? 14 : 18,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MobileLayoutButton(
                  layout: layout,
                ),
                _AccountButton(
                  key: const ValueKey('mobile-account-menu'),
                  email: email,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (compact
                          ? Theme.of(context).textTheme.headlineMedium
                          : Theme.of(context).textTheme.headlineLarge)
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (!compact)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                  ),
                  child: Text(
                    '$noteCount',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onSecondaryContainer,
                        ),
                  ),
                ),
            ],
          ),
          if (compact) ...[
            const SizedBox(height: 16),
            const _SearchField(compact: true),
          ],
        ],
      ),
    );
  }
}

class _MobileLayoutButton extends ConsumerWidget {
  const _MobileLayoutButton({
    required this.layout,
  });

  final NoteOverviewLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final scheme = Theme.of(context).colorScheme;
    final cards = layout == NoteOverviewLayout.cards;
    final tooltip = l10n.t(
      cards ? 'switchToListView' : 'switchToCardsView',
    );
    return Tooltip(
      message: tooltip,
      child: Material(
        key: const ValueKey('mobile-layout-toggle'),
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () =>
              ref.read(appPreferencesProvider.notifier).setNoteOverviewLayout(
                    cards ? NoteOverviewLayout.list : NoteOverviewLayout.cards,
                  ),
          child: Ink(
            height: 52,
            width: 52,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
              shape: BoxShape.circle,
              border: Border.all(
                color: scheme.outlineVariant.withValues(alpha: 0.24),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  cards ? AppIcons.columns2 : AppIcons.grid2X2,
                  size: 20,
                  color: scheme.onSurface,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AnimatedTrashDropTarget extends StatefulWidget {
  const _AnimatedTrashDropTarget({
    required this.onAccepted,
    required this.onHoverChanged,
  });

  final ValueChanged<PlainNote> onAccepted;
  final ValueChanged<bool> onHoverChanged;

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
        if (!_hovered) {
          setState(() => _hovered = true);
          widget.onHoverChanged(true);
        }
        return true;
      },
      onLeave: (_) {
        if (_hovered) {
          setState(() => _hovered = false);
          widget.onHoverChanged(false);
        }
      },
      onAcceptWithDetails: (details) {
        if (_hovered) {
          setState(() => _hovered = false);
          widget.onHoverChanged(false);
        }
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

class _TopLeftBorderPainter extends CustomPainter {
  const _TopLeftBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const radius = 12.0;
    final path = Path()
      ..moveTo(0.5, size.height)
      ..lineTo(0.5, radius)
      ..quadraticBezierTo(0.5, 0.5, radius, 0.5)
      ..lineTo(size.width, 0.5);
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _TopLeftBorderPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _NoteListPane extends ConsumerWidget {
  const _NoteListPane({
    super.key,
    required this.notes,
    required this.onSelected,
    required this.dragging,
    required this.dropIndex,
    required this.onDropIndexChanged,
    required this.onCommitReorder,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.trashHovering,
    this.selectedNoteId,
    this.bottomPadding = 24,
  });

  final List<PlainNote> notes;
  final ValueChanged<PlainNote> onSelected;
  final bool dragging;
  final int? dropIndex;
  final ValueChanged<int?> onDropIndexChanged;
  final void Function(String draggedId, int targetIndex) onCommitReorder;
  final ValueChanged<PlainNote> onDragStarted;
  final VoidCallback onDragEnded;
  final ValueListenable<bool> trashHovering;
  final String? selectedNoteId;
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final scheme = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: EdgeInsets.fromLTRB(12, 8, 12, bottomPadding),
      itemCount: notes.length,
      separatorBuilder: (_, index) {
        final touchesSelection = notes[index].localId == selectedNoteId ||
            notes[index + 1].localId == selectedNoteId;
        if (touchesSelection) {
          return SizedBox(
            key: ValueKey('note-list-divider-hidden-$index'),
            height: 1,
          );
        }
        return Divider(
          key: ValueKey('note-list-divider-$index'),
          height: 1,
          indent: 16,
          endIndent: 16,
          color: scheme.outlineVariant.withValues(alpha: 0.34),
        );
      },
      itemBuilder: (context, index) {
        final note = notes[index];
        final item = _NoteListItem(
          note: note,
          l10n: l10n,
          selected: note.localId == selectedNoteId,
          onTap: () => onSelected(note),
        );
        return _DraggableNoteListEntry(
          key: ValueKey('note-list-item-${note.localId}'),
          note: note,
          index: index,
          dragging: dragging,
          dropIndex: dropIndex,
          trashHovering: trashHovering,
          onDropIndexChanged: onDropIndexChanged,
          onCommitReorder: onCommitReorder,
          onDragStarted: () => onDragStarted(note),
          onDragEnded: onDragEnded,
          child: item,
        );
      },
    );
  }
}

class _DraggableNoteListEntry extends StatefulWidget {
  const _DraggableNoteListEntry({
    super.key,
    required this.note,
    required this.index,
    required this.dragging,
    required this.dropIndex,
    required this.trashHovering,
    required this.onDropIndexChanged,
    required this.onCommitReorder,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.child,
  });

  final PlainNote note;
  final int index;
  final bool dragging;
  final int? dropIndex;
  final ValueListenable<bool> trashHovering;
  final ValueChanged<int?> onDropIndexChanged;
  final void Function(String draggedId, int targetIndex) onCommitReorder;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;
  final Widget child;

  @override
  State<_DraggableNoteListEntry> createState() =>
      _DraggableNoteListEntryState();
}

class _DraggableNoteListEntryState extends State<_DraggableNoteListEntry> {
  final _entryKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final before = widget.dropIndex == widget.index;
    final after = widget.dropIndex == widget.index + 1;
    return DragTarget<PlainNote>(
      key: ValueKey('note-list-drop-${widget.note.localId}'),
      onWillAcceptWithDetails: (_) => true,
      onMove: (details) {
        final box = _entryKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final local = box.globalToLocal(details.offset);
        final nextIndex =
            local.dy < box.size.height / 2 ? widget.index : widget.index + 1;
        if (widget.dropIndex != nextIndex) {
          widget.onDropIndexChanged(nextIndex);
        }
      },
      onLeave: (_) {
        if (widget.dragging) widget.onDropIndexChanged(null);
      },
      onAcceptWithDetails: (details) => widget.onCommitReorder(
        details.data.localId,
        widget.dropIndex ?? widget.index,
      ),
      builder: (context, _, __) => KeyedSubtree(
        key: _entryKey,
        child: AnimatedPadding(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.only(
            top: before ? 8 : 0,
            bottom: after ? 8 : 0,
          ),
          child: _MeasuredNoteDraggable(
            key: ValueKey('note-list-drag-${widget.note.localId}'),
            note: widget.note,
            trashHovering: widget.trashHovering,
            onDragStarted: widget.onDragStarted,
            onDragUpdate: (_) {},
            onDragEnded: widget.onDragEnded,
            childWhenDragging: Opacity(opacity: 0.28, child: widget.child),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _NoteListItem extends StatelessWidget {
  const _NoteListItem({
    required this.note,
    required this.l10n,
    required this.selected,
    required this.onTap,
  });

  final PlainNote note;
  final AppL10n l10n;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _noteListTitle(note, l10n);
    final preview = _noteListPreview(note);
    final showPreview = preview.isNotEmpty && preview != title;
    final noteColor = note.color == 0xffffffff
        ? scheme.outlineVariant
        : brandNoteSurfaceColor(context, note.color);
    return Material(
      color: selected ? scheme.surfaceContainerHighest : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          key: ValueKey('note-list-content-${note.localId}'),
          padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 38,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: noteColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        if (note.pinned)
                          Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Icon(
                              AppIcons.pin,
                              size: 15,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Text(
                          _noteListDate(note.updatedAt, l10n),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        if (showPreview) ...[
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              preview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ] else
                          const Spacer(),
                        if (note.checklist.isNotEmpty)
                          _NoteListMetaIcon(
                            icon: AppIcons.squareCheck,
                            label:
                                '${note.checklist.where((item) => item.done).length}/${note.checklist.length}',
                          ),
                        if (note.shared)
                          const _NoteListMetaIcon(icon: AppIcons.users),
                        if (note.reminderAt != null)
                          const _NoteListMetaIcon(icon: AppIcons.bell),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoteListMetaIcon extends StatelessWidget {
  const _NoteListMetaIcon({required this.icon, this.label});

  final IconData icon;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          if (label != null) ...[
            const SizedBox(width: 3),
            Text(
              label!,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color),
            ),
          ],
        ],
      ),
    );
  }
}

class _SelectNoteState extends ConsumerWidget {
  const _SelectNoteState();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            AppIcons.notebookText,
            size: 42,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 12),
          Text(
            ref.watch(l10nProvider).t('selectNote'),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

String _noteListTitle(PlainNote note, AppL10n l10n) {
  final title = note.title.trim();
  if (title.isNotEmpty && title != 'Untitled note') return title;
  final preview = _noteListPreview(note);
  return preview.isEmpty ? l10n.t('emptyNote') : preview;
}

String _noteListPreview(PlainNote note) {
  final body = note.body.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (body.isNotEmpty) return body;
  final pending = note.checklist
      .where((item) => !item.done && item.text.trim().isNotEmpty)
      .map((item) => item.text.trim())
      .take(3)
      .join(' · ');
  if (pending.isNotEmpty) return pending;
  return note.checklist
      .where((item) => item.text.trim().isNotEmpty)
      .map((item) => item.text.trim())
      .take(3)
      .join(' · ');
}

String _noteListDate(DateTime value, AppL10n l10n) {
  final local = value.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return l10n.t('today');
  }
  return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}.';
}

class _AnimatedCardGrid extends ConsumerStatefulWidget {
  const _AnimatedCardGrid({
    required this.sourceNotes,
    required this.notes,
    required this.columnCount,
    required this.dropIndex,
    required this.onDropIndexChanged,
    required this.onCommitReorder,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.trashHovering,
  });

  final List<PlainNote> sourceNotes;
  final List<PlainNote> notes;
  final int columnCount;
  final int? dropIndex;
  final ValueChanged<int?> onDropIndexChanged;
  final void Function(String draggedId, int targetIndex) onCommitReorder;
  final ValueChanged<PlainNote> onDragStarted;
  final VoidCallback onDragEnded;
  final ValueListenable<bool> trashHovering;

  @override
  ConsumerState<_AnimatedCardGrid> createState() => _AnimatedCardGridState();
}

class _AnimatedCardGridState extends ConsumerState<_AnimatedCardGrid> {
  static const _gap = 12.0;
  static const _fallbackHeight = 144.0;
  static const _motionDuration = Duration(milliseconds: 190);
  static const _motionCurve = Curves.easeOutCubic;

  final Map<String, double> _heights = {};
  final _gridKey = GlobalKey();
  String? _activeDraggedId;
  int? _activeDropIndex;
  var _animatePositions = false;

  void _reportHeight(String noteId, Size size) {
    final previous = _heights[noteId];
    if (!mounted ||
        (previous != null && (previous - size.height).abs() < 0.5)) {
      return;
    }
    setState(() => _heights[noteId] = size.height);
    if (!_animatePositions &&
        widget.notes.every((note) => _heights.containsKey(note.localId))) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _animatePositions = true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final columns = math.max(1, widget.columnCount);
      final cardWidth = (constraints.maxWidth - _gap * (columns - 1)) / columns;
      final columnHeights = List<double>.filled(columns, 0);
      final placements = <({PlainNote note, double left, double top})>[];
      for (var index = 0; index < widget.notes.length; index += 1) {
        final note = widget.notes[index];
        final column = index % columns;
        placements.add((
          note: note,
          left: column * (cardWidth + _gap),
          top: columnHeights[column],
        ));
        columnHeights[column] +=
            (_heights[note.localId] ?? _fallbackHeight) + _gap;
      }
      final gridHeight = columnHeights.reduce(math.max) - _gap;
      int nearestDropIndex(PlainNote dragged, Offset globalPosition) {
        final box = _gridKey.currentContext?.findRenderObject() as RenderBox?;
        final sourceIndex = widget.sourceNotes
            .indexWhere((note) => note.localId == dragged.localId);
        if (box == null || !box.hasSize) {
          return widget.dropIndex ?? math.max(sourceIndex, 0);
        }
        final local = box.globalToLocal(globalPosition);
        final available = widget.sourceNotes
            .where((note) => note.localId != dragged.localId)
            .toList();
        if (available.isEmpty) return 0;
        final dragHeight = _heights[dragged.localId] ?? _fallbackHeight;
        final stableColumnHeights = List<double>.filled(columns, 0);
        var nearestIndex = math.max(sourceIndex, 0);
        var nearestDistance = double.infinity;
        for (var index = 0; index <= available.length; index += 1) {
          final column = index % columns;
          final centerX = column * (cardWidth + _gap) + cardWidth / 2;
          final centerY = stableColumnHeights[column] + dragHeight / 2;
          final dx = local.dx - centerX;
          final dy = local.dy - centerY;
          final distance = dx * dx + dy * dy;
          if (distance < nearestDistance) {
            nearestDistance = distance;
            nearestIndex = index;
          }
          if (index < available.length) {
            stableColumnHeights[column] +=
                (_heights[available[index].localId] ?? _fallbackHeight) + _gap;
          }
        }
        return nearestIndex;
      }

      void updateDropIndex(PlainNote dragged, Offset globalPosition) {
        final nextIndex = nearestDropIndex(dragged, globalPosition);
        _activeDraggedId = dragged.localId;
        _activeDropIndex = nextIndex;
        if (widget.dropIndex != nextIndex) {
          widget.onDropIndexChanged(nextIndex);
        }
      }

      void startDrag(PlainNote note) {
        _activeDraggedId = note.localId;
        _activeDropIndex = widget.sourceNotes
            .indexWhere((candidate) => candidate.localId == note.localId);
        widget.onDragStarted(note);
      }

      void endDrag() {
        _activeDraggedId = null;
        _activeDropIndex = null;
        widget.onDragEnded();
      }

      return DragTarget<PlainNote>(
        key: const ValueKey('card-grid-drop-surface'),
        hitTestBehavior: HitTestBehavior.translucent,
        onWillAcceptWithDetails: (_) => true,
        onAcceptWithDetails: (details) {
          final sourceIndex = widget.sourceNotes.indexWhere(
            (note) => note.localId == details.data.localId,
          );
          final targetIndex = _activeDraggedId == details.data.localId
              ? _activeDropIndex
              : null;
          widget.onCommitReorder(
            details.data.localId,
            targetIndex ?? math.max(sourceIndex, 0),
          );
        },
        builder: (context, _, __) => KeyedSubtree(
          key: _gridKey,
          child: AnimatedSize(
            duration: _motionDuration,
            curve: _motionCurve,
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: gridHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final placement in placements)
                    AnimatedPositioned(
                      key: ValueKey(
                          'animated-note-placement-${placement.note.localId}'),
                      duration:
                          _animatePositions ? _motionDuration : Duration.zero,
                      curve: _motionCurve,
                      left: placement.left,
                      top: placement.top,
                      width: cardWidth,
                      child: _MeasureSize(
                        onChange: (size) =>
                            _reportHeight(placement.note.localId, size),
                        child: _CardDropPlacement(
                          note: placement.note,
                          onDragStarted: startDrag,
                          onDragUpdate: updateDropIndex,
                          onDragEnded: endDrag,
                          trashHovering: widget.trashHovering,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _CardDropPlacement extends ConsumerStatefulWidget {
  const _CardDropPlacement({
    required this.note,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnded,
    required this.trashHovering,
  });

  final PlainNote note;
  final ValueChanged<PlainNote> onDragStarted;
  final void Function(PlainNote note, Offset globalPosition) onDragUpdate;
  final VoidCallback onDragEnded;
  final ValueListenable<bool> trashHovering;

  @override
  ConsumerState<_CardDropPlacement> createState() => _CardDropPlacementState();
}

class _CardDropPlacementState extends ConsumerState<_CardDropPlacement> {
  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final card = _KeepNoteCard(
      note: note,
      onTap: () => _openEditor(context, ref, note),
      onTogglePin: () =>
          ref.read(notesControllerProvider.notifier).togglePinned(note),
      onInvite: () => _showInviteSheet(context, ref, note),
      onReminder: () => _showReminderSheet(context, ref, note),
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
    return _MeasuredNoteDraggable(
      key: ValueKey('compact-note-drag-${note.localId}'),
      note: note,
      trashHovering: widget.trashHovering,
      onDragStarted: () => widget.onDragStarted(note),
      onDragUpdate: (position) => widget.onDragUpdate(note, position),
      onDragEnded: widget.onDragEnded,
      childWhenDragging: Opacity(opacity: 0.28, child: card),
      child: card,
    );
  }
}

class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureSizeRenderObject(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _MeasureSizeRenderObject renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  ValueChanged<Size> onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    if (size == _oldSize) return;
    _oldSize = size;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(size));
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
      padding: EdgeInsets.fromLTRB(12, 20, expanded ? 12 : 10, 0),
      decoration: BoxDecoration(
        color: Theme.of(context)
            .colorScheme
            .surfaceContainerLow
            .withValues(alpha: 0.68),
      ),
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
            icon: AppIcons.notebookText,
            label: l10n.t('notes'),
            expanded: expanded,
          ),
          const SizedBox(height: 6),
          _RailButton(
            bucket: 'reminders',
            icon: AppIcons.bell,
            label: l10n.t('reminders'),
            expanded: expanded,
          ),
          const SizedBox(height: 6),
          _RailButton(
            bucket: 'archived',
            icon: AppIcons.archive,
            label: l10n.t('archive'),
            expanded: expanded,
          ),
          const SizedBox(height: 6),
          _RailButton(
            bucket: 'trashed',
            icon: AppIcons.trash,
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
        borderRadius: BorderRadius.circular(AppRadii.xl),
        onTap: () => _createNoteForCurrentBucket(context, ref),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: expanded ? 54 : 48,
          width: expanded ? null : 46,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 0),
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(AppRadii.xl),
          ),
          child: Row(
            mainAxisAlignment:
                expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(create.icon, size: 21, color: scheme.onPrimary),
              if (expanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    create.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: scheme.onPrimary,
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
          height: 46,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 12 : 0),
          decoration: BoxDecoration(
            color: selected
                ? Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.74)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.lg),
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

class _MobileBottomNav extends ConsumerStatefulWidget {
  const _MobileBottomNav();

  @override
  ConsumerState<_MobileBottomNav> createState() => _MobileBottomNavState();
}

class _MobileBottomNavState extends ConsumerState<_MobileBottomNav> {
  var _expanded = false;
  double? _pressedAnchorX;

  void _toggleCreate() {
    setState(() => _expanded = !_expanded);
  }

  void _setPressedAnchor(double? anchorX) {
    if (_pressedAnchorX == anchorX) return;
    setState(() => _pressedAnchorX = anchorX);
  }

  void _collapse() {
    if (_expanded) setState(() => _expanded = false);
  }

  Future<void> _runCreateAction(_MobileCreateAction action) async {
    _collapse();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    switch (action) {
      case _MobileCreateAction.note:
        _createNoteFromAction(context, ref, _CreateAction.note);
      case _MobileCreateAction.reminder:
        await _startReminderFlow(context, ref);
      case _MobileCreateAction.list:
        _createNoteFromAction(context, ref, _CreateAction.list);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final bucket = ref.watch(noteBucketProvider);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final targetRadius = _expanded ? 24.0 : 36.0;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Center(
        heightFactor: 1,
        child: AnimatedSize(
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          alignment: Alignment.bottomCenter,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _pressedAnchorX == null ? 0 : 1),
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            builder: (context, press, child) => Transform.scale(
              alignment: Alignment(_pressedAnchorX ?? 0, 1),
              scaleX: 1 + press * 0.018,
              scaleY: 1 - press * 0.012,
              child: child,
            ),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: targetRadius),
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutQuart,
              builder: (context, radiusValue, child) {
                final radius = BorderRadius.circular(radiusValue);
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 360),
                  curve: Curves.easeOutQuart,
                  width: 264,
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    boxShadow: [
                      BoxShadow(
                        color:
                            Colors.black.withValues(alpha: dark ? 0.24 : 0.06),
                        blurRadius: _expanded ? 30 : 16,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: radius,
                    child: child,
                  ),
                );
              },
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Material(
                  key: const ValueKey('mobile-bottom-nav-pill'),
                  color: dark
                      ? const Color(0xff252927).withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.7),
                  elevation: 0,
                  borderRadius: BorderRadius.circular(targetRadius),
                  clipBehavior: Clip.none,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ClipRect(
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 340),
                            curve: Curves.easeOutQuart,
                            alignment: Alignment.topCenter,
                            heightFactor: _expanded ? 1 : 0,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutCubic,
                              opacity: _expanded ? 1 : 0,
                              child: IgnorePointer(
                                ignoring: !_expanded,
                                child: AnimatedSlide(
                                  duration: const Duration(milliseconds: 340),
                                  curve: Curves.easeOutQuart,
                                  offset: _expanded
                                      ? Offset.zero
                                      : const Offset(0, .16),
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(0, 0, 0, 8),
                                    child: Column(
                                      children: [
                                        _MobileCreateInlineAction(
                                          key: const ValueKey(
                                            'mobile-create-note-action',
                                          ),
                                          icon: AppIcons.filePlus2,
                                          label: l10n.t('newNote'),
                                          onTap: () => unawaited(
                                            _runCreateAction(
                                              _MobileCreateAction.note,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        _MobileCreateInlineAction(
                                          key: const ValueKey(
                                            'mobile-create-reminder-action',
                                          ),
                                          icon: AppIcons.bellPlus,
                                          label: l10n.t('setReminder'),
                                          onTap: () => unawaited(
                                            _runCreateAction(
                                              _MobileCreateAction.reminder,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        _MobileCreateInlineAction(
                                          key: const ValueKey(
                                            'mobile-create-list-action',
                                          ),
                                          icon: AppIcons.listChecks,
                                          label: l10n.t('newChecklist'),
                                          onTap: () => unawaited(
                                            _runCreateAction(
                                              _MobileCreateAction.list,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _MobileNavIcon(
                              key: const ValueKey('mobile-nav-notes'),
                              icon: AppIcons.notebookText,
                              tooltip: l10n.t('notes'),
                              selected:
                                  bucket == 'active' || bucket == 'archived',
                              accent: scheme.primary,
                              onPressChanged: (pressed) =>
                                  _setPressedAnchor(pressed ? -0.72 : null),
                              onPressed: () {
                                _collapse();
                                ref.read(noteBucketProvider.notifier).state =
                                    'active';
                              },
                            ),
                            const SizedBox(width: 8),
                            _MobileNavIcon(
                              key: const ValueKey('mobile-nav-reminders'),
                              icon: AppIcons.bell,
                              tooltip: l10n.t('reminders'),
                              selected: bucket == 'reminders',
                              accent: scheme.primary,
                              onPressChanged: (pressed) =>
                                  _setPressedAnchor(pressed ? -0.24 : null),
                              onPressed: () {
                                _collapse();
                                ref.read(noteBucketProvider.notifier).state =
                                    'reminders';
                              },
                            ),
                            const SizedBox(width: 8),
                            _MobileNavIcon(
                              key: const ValueKey('mobile-nav-trash'),
                              icon: AppIcons.trash2,
                              tooltip: l10n.t('trash'),
                              selected: bucket == 'trashed',
                              accent: scheme.primary,
                              onPressChanged: (pressed) =>
                                  _setPressedAnchor(pressed ? 0.24 : null),
                              onPressed: () {
                                _collapse();
                                ref.read(noteBucketProvider.notifier).state =
                                    'trashed';
                              },
                            ),
                            const SizedBox(width: 8),
                            _MobileCreateToggleButton(
                              expanded: _expanded,
                              dark: dark,
                              onPressChanged: (pressed) =>
                                  _setPressedAnchor(pressed ? 0.72 : null),
                              onPressed: _toggleCreate,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileCreateInlineAction extends StatefulWidget {
  const _MobileCreateInlineAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_MobileCreateInlineAction> createState() =>
      _MobileCreateInlineActionState();
}

class _MobileCreateInlineActionState extends State<_MobileCreateInlineAction> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: _pressed ? 1 : 0),
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOutCubic,
        builder: (context, value, child) => Transform.scale(
          scaleX: 1 + value * 0.025,
          scaleY: 1 - value * 0.045,
          child: child,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: dark
                ? Colors.white.withValues(alpha: 0.08)
                : const Color(0xfffbfaf6).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 32,
                alignment: Alignment.center,
                child: Icon(
                  widget.icon,
                  size: 20,
                  color: dark
                      ? Colors.white.withValues(alpha: 0.82)
                      : const Color(0xff171c19),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.86)
                            : scheme.onSurface,
                        fontWeight: FontWeight.w700,
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

class _MobileCreateToggleButton extends StatefulWidget {
  const _MobileCreateToggleButton({
    required this.expanded,
    required this.dark,
    required this.onPressChanged,
    required this.onPressed,
  });

  final bool expanded;
  final bool dark;
  final ValueChanged<bool> onPressChanged;
  final VoidCallback onPressed;

  @override
  State<_MobileCreateToggleButton> createState() =>
      _MobileCreateToggleButtonState();
}

class _MobileCreateToggleButtonState extends State<_MobileCreateToggleButton> {
  var _pressed = false;

  void _release() {
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final tooltip = AppL10n(Localizations.localeOf(context).languageCode).t(
      widget.expanded ? 'close' : 'create',
    );
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: GestureDetector(
          key: const ValueKey('mobile-nav-create'),
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            setState(() => _pressed = true);
            widget.onPressChanged(true);
          },
          onTapCancel: () {
            _release();
            widget.onPressChanged(false);
          },
          onTapUp: (_) {
            _release();
            widget.onPressChanged(false);
            widget.onPressed();
          },
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _pressed ? 1 : 0),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Transform.scale(
              scaleX: 1 + value * 0.08,
              scaleY: 1 - value * 0.07,
              child: child,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutQuart,
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: widget.dark ? Colors.white : const Color(0xff111514),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: AnimatedRotation(
                turns: widget.expanded ? 0.125 : 0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutBack,
                child: Icon(
                  AppIcons.plus,
                  size: 21,
                  color: widget.dark ? const Color(0xff111514) : Colors.white,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileNavIcon extends StatefulWidget {
  const _MobileNavIcon({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.accent,
    required this.onPressChanged,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final Color accent;
  final ValueChanged<bool> onPressChanged;
  final VoidCallback onPressed;

  @override
  State<_MobileNavIcon> createState() => _MobileNavIconState();
}

class _MobileNavIconState extends State<_MobileNavIcon> {
  var _pressed = false;

  void _release() {
    if (_pressed) setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final lightIconColor = const Color(0xff171c19).withValues(
      alpha: widget.selected ? 0.78 : 0.72,
    );
    final background = dark
        ? Colors.white.withValues(alpha: widget.selected ? 0.16 : 0.07)
        : const Color(0xfffbfaf6).withValues(
            alpha: widget.selected ? 0.96 : 0.84,
          );
    final foreground = dark
        ? (widget.selected
            ? widget.accent
            : Colors.white.withValues(alpha: 0.7))
        : lightIconColor;
    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        selected: widget.selected,
        label: widget.tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) {
            setState(() => _pressed = true);
            widget.onPressChanged(true);
          },
          onTapCancel: () {
            _release();
            widget.onPressChanged(false);
          },
          onTapUp: (_) {
            _release();
            widget.onPressChanged(false);
            widget.onPressed();
          },
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _pressed ? 1 : 0),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Transform.scale(
              scaleX: 1 + value * 0.07,
              scaleY: 1 - value * 0.06,
              child: child,
            ),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutQuart,
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: background,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(
                widget.icon,
                size: 18,
                color: foreground,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends ConsumerWidget {
  const _SearchField({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final scheme = Theme.of(context).colorScheme;
    final design = context.safernotesTheme;
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
              child: const Icon(AppIcons.search, size: 19),
            ),
            prefixIconConstraints: BoxConstraints(minWidth: compact ? 48 : 44),
            filled: true,
            fillColor: Theme.of(context).inputDecorationTheme.fillColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(design.controlRadius),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(design.controlRadius),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(design.controlRadius),
              borderSide: BorderSide(
                color: scheme.primary.withValues(alpha: 0.44),
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
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _showEmailVerificationDialog(context, ref, widget.email),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(AppIcons.mailWarning, size: 18, color: scheme.onSurface),
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
                      child: Icon(AppIcons.mailCheck,
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
                      icon: AppIcons.x,
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
                    prefixIcon: const Icon(AppIcons.keyRound, size: 18),
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
                        icon: const Icon(AppIcons.send),
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
                            : const Icon(AppIcons.circleCheck),
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

enum _MobileCreateAction { note, reminder, list }

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
    final design = context.safernotesTheme;
    final bg = brandNoteSurfaceColor(context, note.color);
    final showHoverActions = MediaQuery.sizeOf(context).width >= 700;
    final displayTitle =
        note.title.trim() == 'Untitled note' ? '' : note.title.trim();
    final hasMetadata = note.checklist.isNotEmpty ||
        note.conflicted ||
        note.dirty ||
        note.reminderAt != null ||
        note.shared;
    final showFooter = hasMetadata || (_hovered && showHoverActions);
    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: AnimatedScale(
        scale: _hovered ? 1.006 : 1,
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(design.noteCardRadius),
          ),
          clipBehavior: Clip.antiAlias,
          child: Ink(
            decoration: BoxDecoration(
              color: bg,
              gradient: brandNoteGradient(context, note.color),
            ),
            child: InkWell(
              onTap: widget.onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 144),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 19, 14, 14),
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
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                            ),
                            AnimatedOpacity(
                              opacity: _hovered || note.pinned ? 1 : 0,
                              duration: const Duration(milliseconds: 120),
                              child: AppIconButton(
                                tooltip: note.pinned
                                    ? l10n.t('unpin')
                                    : l10n.t('pin'),
                                icon: note.pinned
                                    ? AppIcons.pin
                                    : AppIcons.pinOff,
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
                      if (showFooter) ...[
                        const SizedBox(height: 14),
                        SizedBox(
                          height: 36,
                          child: Row(
                            children: [
                              if (note.checklist.isNotEmpty)
                                _MetaPill(
                                  icon: AppIcons.squareCheck,
                                  label:
                                      '${note.checklist.where((item) => item.done).length}/${note.checklist.length}',
                                ),
                              if (note.conflicted)
                                _MetaPill(
                                  icon: AppIcons.circleAlert,
                                  label: l10n.t('conflict'),
                                  color: scheme.error,
                                ),
                              if (note.dirty)
                                _MetaPill(
                                  icon: AppIcons.cloudUpload,
                                  label: l10n.t('synced'),
                                  color: scheme.tertiary,
                                ),
                              if (note.reminderAt != null)
                                _MetaPill(
                                  icon: AppIcons.bell,
                                  label:
                                      _formatReminder(note.reminderAt!, l10n),
                                  color: scheme.primary,
                                ),
                              if (note.shared)
                                _MetaPill(
                                  icon: AppIcons.users,
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
                                          icon: AppIcons.rotateCcw,
                                          onPressed: widget.onRestore,
                                        ),
                                      if (note.state == 'active')
                                        AppIconButton(
                                          tooltip: l10n.t('archiveAction'),
                                          icon: AppIcons.archive,
                                          onPressed: widget.onArchive,
                                        ),
                                      if (note.state == 'active' &&
                                          note.reminderAt == null)
                                        AppIconButton(
                                          tooltip: l10n.t('collaboratorInvite'),
                                          icon: note.shared
                                              ? AppIcons.users
                                              : AppIcons.userPlus,
                                          onPressed: widget.onInvite,
                                        ),
                                      if (note.state != 'trashed')
                                        AppIconButton(
                                          tooltip: l10n.t('reminder'),
                                          icon: AppIcons.bell,
                                          onPressed: widget.onReminder,
                                        ),
                                      if (note.state != 'trashed')
                                        AppIconButton(
                                          tooltip: l10n.t('trash'),
                                          icon: AppIcons.trash,
                                          onPressed: widget.onTrash,
                                        )
                                      else
                                        AppIconButton(
                                          tooltip: l10n.t('deleteForever'),
                                          icon: AppIcons.trash2,
                                          onPressed: widget.onDeleteForever,
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
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
    required this.trashHovering,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnded,
    required this.childWhenDragging,
    required this.child,
  });

  final PlainNote note;
  final ValueListenable<bool> trashHovering;
  final VoidCallback onDragStarted;
  final ValueChanged<Offset> onDragUpdate;
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
      delay: const Duration(milliseconds: 260),
      feedback: _NoteDragFeedback(
        key: ValueKey('note-drag-feedback-${widget.note.localId}'),
        noteId: widget.note.localId,
        trashHovering: widget.trashHovering,
        sizeReader: () => _dragFeedbackSize ?? _cardSize,
        child: widget.child,
      ),
      onDragStarted: _handleDragStarted,
      onDragUpdate: (details) => widget.onDragUpdate(details.globalPosition),
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
    required this.noteId,
    required this.trashHovering,
    required this.sizeReader,
    required this.child,
  });

  final String noteId;
  final ValueListenable<bool> trashHovering;
  final Size? Function() sizeReader;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final size = sizeReader() ?? const Size(260, 170);
    return Material(
      type: MaterialType.transparency,
      child: ValueListenableBuilder<bool>(
        valueListenable: trashHovering,
        builder: (context, hovering, _) => AnimatedOpacity(
          key: ValueKey('note-drag-trash-opacity-$noteId'),
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          opacity: hovering ? 0.52 : 1,
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: child,
          ),
        ),
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
                  item.done ? AppIcons.squareCheck : AppIcons.square,
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
          AppIcons.cloudCheck,
          l10n.t('saved'),
          Theme.of(context).colorScheme.tertiary
        ),
      SyncStatus.saving => (
          AppIcons.clock3,
          l10n.t('saving'),
          Theme.of(context).colorScheme.primary
        ),
      SyncStatus.syncing => (
          AppIcons.refreshCw,
          l10n.t('syncing'),
          Theme.of(context).colorScheme.primary
        ),
      SyncStatus.offline => (
          AppIcons.cloudOff,
          l10n.t('offline'),
          Theme.of(context).colorScheme.error
        ),
      SyncStatus.conflict => (
          AppIcons.circleAlert,
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
    super.key,
    required this.email,
    this.compact = false,
  });

  final String email;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: email.isEmpty ? l10n.t('profile') : email,
      child: GestureDetector(
        onTap: () => _showAccountSideSheet(context, ref, email),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutBack,
            width: compact ? 52 : 34,
            height: compact ? 52 : 34,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(
                alpha: compact ? 0.42 : 1,
              ),
              shape: BoxShape.circle,
              border: compact
                  ? Border.all(
                      color: scheme.outlineVariant.withValues(alpha: 0.24),
                    )
                  : null,
            ),
            alignment: Alignment.center,
            child: Icon(
              AppIcons.user,
              size: compact ? 22 : 18,
              color: scheme.onSurface,
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
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: widget.selected
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.4)
                : _hovered
                    ? scheme.surfaceContainerHighest.withValues(alpha: 0.22)
                    : scheme.surfaceContainerHighest.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(
                alpha: widget.selected ? 0.18 : 0.08,
              ),
            ),
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
                    AppIcons.check,
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
    final dark = scheme.brightness == Brightness.dark;
    const radius = BorderRadius.only(
      topLeft: Radius.circular(30),
      bottomLeft: Radius.circular(30),
    );
    return SafeArea(
      minimum: EdgeInsets.zero,
      child: SizedBox(
        height: double.infinity,
        width: (MediaQuery.sizeOf(context).width * 0.88).clamp(304.0, 390.0),
        child: ClipRRect(
          borderRadius: radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
            child: DecoratedBox(
              key: const ValueKey('mobile-account-side-sheet'),
              decoration: BoxDecoration(
                color: dark
                    ? const Color(0xff202624).withValues(alpha: 0.82)
                    : Colors.white.withValues(alpha: 0.72),
                borderRadius: radius,
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: dark ? 0.24 : 0.1),
                    blurRadius: 28,
                    offset: const Offset(-8, 10),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Text(
                            l10n.t('profile'),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          AppIconButton(
                            tooltip: l10n.t('close'),
                            icon: AppIcons.x,
                            size: 42,
                            iconSize: 18,
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest
                                  .withValues(alpha: 0.46),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: scheme.outlineVariant
                                    .withValues(alpha: 0.22),
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              initial,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: scheme.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  email.isEmpty
                                      ? l10n.t('localAccount')
                                      : email,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 5),
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
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Divider(
                        height: 1,
                        color: scheme.outlineVariant.withValues(alpha: 0.22),
                      ),
                      const SizedBox(height: 12),
                      _MobileMenuButton(
                        bucket: 'active',
                        icon: AppIcons.notebookText,
                        label: l10n.t('notes'),
                      ),
                      const SizedBox(height: 4),
                      _MobileMenuButton(
                        bucket: 'reminders',
                        icon: AppIcons.bell,
                        label: l10n.t('reminders'),
                      ),
                      const SizedBox(height: 4),
                      _MobileMenuButton(
                        bucket: 'archived',
                        icon: AppIcons.archive,
                        label: l10n.t('archive'),
                      ),
                      const SizedBox(height: 4),
                      _MobileMenuButton(
                        bucket: 'trashed',
                        icon: AppIcons.trash,
                        label: l10n.t('trash'),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        key: const ValueKey('mobile-sidebar-sync-status'),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: const _SyncIndicator(showLabel: true),
                      ),
                      const Spacer(),
                      _AccountActionTile(
                        icon: AppIcons.settings,
                        label: l10n.t('settings'),
                        onTap: () {
                          Navigator.of(context).pop();
                          _openSettings(context);
                        },
                      ),
                      const SizedBox(height: 4),
                      _AccountActionTile(
                        icon: AppIcons.logOut,
                        label: l10n.t('logout'),
                        destructive: true,
                        onTap: () {
                          Navigator.of(context).pop();
                          ref.read(authControllerProvider.notifier).signOut();
                        },
                      ),
                    ],
                  ),
                ),
              ),
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
        borderRadius: BorderRadius.circular(18),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          decoration: BoxDecoration(
            color: _hovered
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.24)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.08),
            ),
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
              Icon(AppIcons.chevronRight,
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
              child: Icon(AppIcons.check, size: 17, color: scheme.onSurface),
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
                            Icon(AppIcons.bellPlus,
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
                              icon: AppIcons.x,
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
                            prefixIcon: const Icon(AppIcons.search, size: 18),
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
                    ? AppIcons.notebookText
                    : AppIcons.listChecks,
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
            Icon(AppIcons.chevronRight,
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
                        icon: AppIcons.calendar,
                        label: l10n.t('date'),
                        value:
                            '${_selected.day.toString().padLeft(2, '0')}.${_selected.month.toString().padLeft(2, '0')}.${_selected.year}',
                        onTap: _pickDate,
                      ),
                      const SizedBox(height: 10),
                      _ReminderPickTile(
                        icon: AppIcons.clock3,
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
                            : const Icon(AppIcons.bellRing),
                        label: Text(l10n.t('setReminder')),
                      ),
                      if (widget.note.reminderAt != null) ...[
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: _busy ? null : () => _save(null),
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
              AppIcons.notebookText,
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
            Icon(AppIcons.circleAlert,
                color: Theme.of(context).colorScheme.error, size: 40),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton.icon(
                onPressed: onRetry,
                icon: const Icon(AppIcons.refreshCw),
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
        icon: AppIcons.filePlus2,
        label: l10n.t('newNote'),
      ),
    'reminders' => _CreateIntent(
        icon: AppIcons.bellPlus,
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
        elevation: 0,
        shape: const RoundedRectangleBorder(),
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

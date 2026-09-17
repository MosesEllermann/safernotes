import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/foundation.dart'
    show ValueListenable, defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:safernotes_app/shared/widgets/app_canvas.dart';
import 'package:safernotes_app/shared/widgets/app_info_bar.dart';
import 'package:safernotes_app/shared/widgets/animated_icon_button.dart';
import 'package:safernotes_app/shared/widgets/app_motion.dart';
import 'package:safernotes_app/shared/widgets/glass_surface.dart';
import 'package:safernotes_app/shared/widgets/safernotes_logo.dart';

final noteSearchProvider = StateProvider<String>((ref) => '');

/// Header chip filters, layered on top of the current bucket.
enum NoteQuickFilter { all, favorites, todo, label }

final noteQuickFilterProvider =
    StateProvider<NoteQuickFilter>((ref) => NoteQuickFilter.all);

/// Selected label when [noteQuickFilterProvider] is [NoteQuickFilter.label].
final noteLabelFilterProvider = StateProvider<String?>((ref) => null);
final _draggedNoteProvider = StateProvider<PlainNote?>((ref) => null);
final _dragTrashHoverProvider = StateProvider<bool>((ref) => false);
final _noteOverviewResetProvider = StateProvider<int>((ref) => 0);
final _selectedNoteIdsProvider =
    StateProvider.autoDispose<Set<String>>((ref) => const {});
final _accountUsageProvider = FutureProvider.autoDispose
    .family<SubscriptionUsage, ({String accessToken, String tenant})>(
        (ref, credentials) async {
  final cacheKey = 'zk.account_usage.${credentials.tenant}';
  try {
    final usage = await ref.read(apiClientProvider).fetchSubscriptionUsage(
          accessToken: credentials.accessToken,
          tenant: credentials.tenant,
        );
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(cacheKey, jsonEncode(usage.toJson()));
    return usage;
  } catch (error, stackTrace) {
    final preferences = await SharedPreferences.getInstance();
    final cached = preferences.getString(cacheKey);
    if (cached != null) {
      try {
        return SubscriptionUsage.fromJson(
          Map<String, dynamic>.from(jsonDecode(cached) as Map),
        );
      } catch (_) {
        await preferences.remove(cacheKey);
      }
    }
    Error.throwWithStackTrace(error, stackTrace);
  }
});

/// The Pixel-class Android path has a tighter raster budget than iOS for
/// several overlapping backdrop filters. Keep this centralized so expensive
/// visual effects can retain their full fidelity everywhere else.
bool get _usesAndroidRasterBudget =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

bool get _usesIosNativeControls =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

class NotesScreen extends ConsumerStatefulWidget {
  const NotesScreen({
    super.key,
    this.invitationId,
    this.invitationRevision = 0,
  });

  final String? invitationId;
  final int invitationRevision;

  @override
  ConsumerState<NotesScreen> createState() => _NotesScreenState();
}

class _NotesScreenState extends ConsumerState<NotesScreen> {
  final Map<String, Timer> _reminderTimers = {};
  int? _handledInvitationRevision;
  var _invitationReviewInProgress = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(notesControllerProvider, (_, next) {
      final notes = next.valueOrNull;
      if (notes != null) _scheduleReminders(notes);
    }, fireImmediately: true);
    _scheduleInvitationReview();
    _scheduleBillingReturnReview();
  }

  Future<void> _scheduleBillingReturnReview() async {
    if (!kIsWeb) return;
    final preferences = await SharedPreferences.getInstance();
    final hasPendingCheckout =
        preferences.getString(pendingBillingPlanPreferenceKey) != null;
    final completed = ref.read(billingReturnStatusProvider) == 'success';
    if (!mounted || (!hasPendingCheckout && !completed)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _openSettings(context, ref, openPlan: true);
    });
  }

  @override
  void didUpdateWidget(covariant NotesScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.invitationRevision != oldWidget.invitationRevision ||
        widget.invitationId != oldWidget.invitationId) {
      _scheduleInvitationReview();
    }
  }

  void _scheduleInvitationReview() {
    final invitationId = widget.invitationId;
    if (invitationId == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(
        _reviewInvitation(invitationId, widget.invitationRevision),
      );
    });
  }

  Future<void> _reviewInvitation(
    String invitationId,
    int invitationRevision,
  ) async {
    if (_handledInvitationRevision == invitationRevision ||
        _invitationReviewInProgress ||
        !mounted) {
      return;
    }
    _handledInvitationRevision = invitationRevision;
    _invitationReviewInProgress = true;
    try {
      await _performInvitationReview(invitationId);
    } finally {
      _invitationReviewInProgress = false;
    }
  }

  Future<void> _performInvitationReview(String invitationId) async {
    final session = await ref.read(authControllerProvider.future);
    if (!mounted) return;
    if (session == null) {
      _handledInvitationRevision = null;
      return;
    }

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
    showAppInfoBar(
      context,
      message: message,
      avoidMobileNavigation: true,
    );
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
    return retryInvitationDecision(
      () => ref.read(apiClientProvider).decideShareInvitation(
            invitationId: invitationId,
            accessToken: accessToken,
            decision: decision.name,
          ),
    );
  }

  Future<void> _importSharedNote(String noteId) async {
    await ref.read(authControllerProvider.notifier).ensureEncryptionKeys();
    await retrySharedNoteImport(
      () => ref
          .read(notesControllerProvider.notifier)
          .pullRemote(requiredNoteId: noteId),
    );
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
    final selectedNoteIds = ref.watch(_selectedNoteIdsProvider);
    final selectionActive = selectedNoteIds.isNotEmpty;
    final session = ref.watch(authControllerProvider).valueOrNull;
    final width = MediaQuery.sizeOf(context).width;
    final desktop = width >= 900;
    final showLogoText = width >= 620;
    final mediaQuery = MediaQuery.of(context);
    final systemGestureGuardHeight = math.max(
      mediaQuery.viewPadding.bottom,
      mediaQuery.systemGestureInsets.bottom,
    );
    final noteOverviewLayout =
        ref.watch(appPreferencesProvider).valueOrNull?.noteOverviewLayout ??
            NoteOverviewLayout.cards;
    final systemOverlayStyle = (Theme.of(context).brightness == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(
      statusBarColor: Colors.transparent,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarContrastEnforced: false,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      key: const ValueKey('notes-system-ui-overlay'),
      value: systemOverlayStyle,
      child: AppCanvas(
        key: const ValueKey('notes-app-canvas'),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          extendBody: !desktop,
          appBar: desktop
              ? AppBar(
                  toolbarHeight: 96,
                  titleSpacing: 24,
                  actionsPadding: const EdgeInsets.only(bottom: 16),
                  surfaceTintColor: Colors.transparent,
                  backgroundColor: Colors.transparent,
                  title: Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      children: [
                        const SafernotesLogo(size: 38),
                        if (showLogoText) ...[
                          const SizedBox(width: 12),
                          Text(
                            l10n.t('appName'),
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(width: 24),
                        ] else
                          const SizedBox(width: 10),
                        const Expanded(child: _SearchField()),
                      ],
                    ),
                  ),
                  actions: selectionActive
                      ? const [
                          _MultiSelectionToolbar(),
                          SizedBox(width: 8),
                        ]
                      : [
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
                            onPressed: () => _openSettings(context, ref),
                          ),
                          _AccountButton(
                            key: const ValueKey('desktop-account-menu'),
                            email: session?.email ?? '',
                          ),
                          const SizedBox(width: 8),
                        ],
                )
              : null,
          body: Stack(
            children: [
              Positioned.fill(
                child: SafeArea(
                  top: desktop,
                  bottom: desktop,
                  child: notes.when(
                    data: (items) => _KeepWorkspace(
                      notes: items,
                      email: session?.email ?? '',
                      showEmailVerification:
                          session != null && !session.emailVerified,
                      layout: noteOverviewLayout,
                    ),
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (error, _) => _ErrorState(
                      message: error.toString(),
                      onRetry: () => ref
                          .read(notesControllerProvider.notifier)
                          .pullRemote(),
                    ),
                  ),
                ),
              ),
              if (!desktop &&
                  _usesAndroidRasterBudget &&
                  systemGestureGuardHeight > 0)
                Positioned(
                  key: const ValueKey('android-system-gesture-guard'),
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: systemGestureGuardHeight + 8,
                  child: const Listener(
                    behavior: HitTestBehavior.opaque,
                    child: SizedBox.expand(),
                  ),
                ),
              if (!desktop)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _usesIosNativeControls
                      ? const _MobileBottomNav(
                          key: ValueKey('mobile-standard-navigation'),
                        )
                      : AnimatedSwitcher(
                          duration: AppMotion.duration(
                            context,
                            const Duration(milliseconds: 340),
                          ),
                          reverseDuration: AppMotion.duration(
                            context,
                            const Duration(milliseconds: 240),
                          ),
                          switchInCurve: Curves.easeOutBack,
                          switchOutCurve: Curves.easeInCubic,
                          layoutBuilder: (currentChild, previousChildren) =>
                              Stack(
                            alignment: Alignment.bottomCenter,
                            children: [
                              ...previousChildren,
                              if (currentChild != null) currentChild,
                            ],
                          ),
                          transitionBuilder: (child, animation) {
                            final slide = Tween<Offset>(
                              begin: const Offset(0, 0.32),
                              end: Offset.zero,
                            ).animate(animation);
                            final scale =
                                Tween<double>(begin: 0.82, end: 1).animate(
                              animation,
                            );
                            return FadeTransition(
                              opacity: animation,
                              child: SlideTransition(
                                position: slide,
                                child:
                                    ScaleTransition(scale: scale, child: child),
                              ),
                            );
                          },
                          child: selectionActive
                              ? const _MultiSelectionToolbar(
                                  key: ValueKey('mobile-selection-toolbar'),
                                  compact: true,
                                )
                              : const _MobileBottomNav(
                                  key: ValueKey('mobile-standard-navigation'),
                                ),
                        ),
                ),
            ],
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
      unawaited(
        scheduleReminderNotification(
          reminderId: key,
          title: note.title.trim().isEmpty ? l10n.t('reminder') : note.title,
          body: _reminderBody(note),
          scheduledAt: reminderAt,
        ).catchError((Object _) {
          // The in-app timer below remains a useful fallback if the platform
          // rejects an alarm because of device-specific scheduler limits.
        }),
      );
      _reminderTimers[key] = Timer(reminderAt.difference(now), () async {
        _reminderTimers.remove(key);
        final shown = await showReminderNotification(
          reminderId: key,
          title: note.title.trim().isEmpty ? l10n.t('reminder') : note.title,
          body: _reminderBody(note),
        );
        if (!shown && mounted) {
          showAppInfoBar(
            context,
            message: note.title.trim().isEmpty
                ? l10n.t('reminder')
                : l10n.t(
                    'reminderNotificationTitle',
                    params: {'title': note.title},
                  ),
            actionLabel: l10n.t('open'),
            onAction: () => _openEditor(context, ref, note),
            avoidMobileNavigation: true,
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
        unawaited(
          cancelReminderNotification(entry.key).catchError((Object _) {}),
        );
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

@visibleForTesting
Future<void> retrySharedNoteImport(
  Future<void> Function() importNote, {
  List<Duration> retryDelays = const [
    Duration(milliseconds: 250),
    Duration(milliseconds: 750),
    Duration(milliseconds: 1500),
  ],
  Future<void> Function(Duration) wait = Future.delayed,
}) async {
  for (var attempt = 0;; attempt += 1) {
    try {
      await importNote();
      return;
    } catch (_) {
      if (attempt >= retryDelays.length) rethrow;
      await wait(retryDelays[attempt]);
    }
  }
}

@visibleForTesting
Future<T> retryInvitationDecision<T>(
  Future<T> Function() decide, {
  List<Duration> retryDelays = const [
    Duration(milliseconds: 350),
    Duration(milliseconds: 900),
  ],
  Future<void> Function(Duration) wait = Future.delayed,
}) async {
  for (var attempt = 0;; attempt += 1) {
    try {
      return await decide();
    } catch (error) {
      final transient = error is TimeoutException ||
          error is ApiException &&
              (error.statusCode == 0 || error.statusCode >= 500);
      if (!transient || attempt >= retryDelays.length) rethrow;
      await wait(retryDelays[attempt]);
    }
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
    required this.showEmailVerification,
    required this.layout,
  });

  final List<PlainNote> notes;
  final String email;
  final bool showEmailVerification;
  final NoteOverviewLayout layout;

  @override
  ConsumerState<_KeepWorkspace> createState() => _KeepWorkspaceState();
}

class _KeepWorkspaceState extends ConsumerState<_KeepWorkspace>
    with WidgetsBindingObserver {
  static const _cardPageSize = 48;

  String? _draggedId;
  int? _dropIndex;
  String? _selectedNoteId;
  final _trashHovering = ValueNotifier(false);
  final _overviewScrollController = ScrollController();
  final _compactHeaderOpacity = ValueNotifier<double>(1);

  late final ProviderSubscription<String> _bucketSubscription;
  late final ProviderSubscription<int> _resetSubscription;
  late final ProviderSubscription<String> _searchSubscription;
  late final ProviderSubscription<NoteQuickFilter> _quickFilterSubscription;
  late final ProviderSubscription<String?> _labelFilterSubscription;
  double _compactHeaderHeight = 190;
  int _visibleCardLimit = _cardPageSize;
  bool _emptyingTrash = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _overviewScrollController.addListener(_updateCompactHeaderOpacity);
    _bucketSubscription = ref.listenManual<String>(
      noteBucketProvider,
      (_, __) {
        _clearDragPreview();
        _clearSelection();
        _resetOverviewScroll();
      },
    );
    _resetSubscription = ref.listenManual<int>(
      _noteOverviewResetProvider,
      (_, __) => _resetOverviewScroll(),
    );
    _searchSubscription = ref.listenManual<String>(
      noteSearchProvider,
      (_, __) => _resetCardLimit(),
    );
    _quickFilterSubscription = ref.listenManual<NoteQuickFilter>(
      noteQuickFilterProvider,
      (_, __) => _resetCardLimit(),
    );
    _labelFilterSubscription = ref.listenManual<String?>(
      noteLabelFilterProvider,
      (_, __) => _resetCardLimit(),
    );
  }

  @override
  void didUpdateWidget(covariant _KeepWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.layout != widget.layout) _resetOverviewScroll();
    final liveIds = widget.notes.map((note) => note.localId).toSet();
    final selectedIds = ref.read(_selectedNoteIdsProvider);
    if (!liveIds.containsAll(selectedIds)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(_selectedNoteIdsProvider.notifier).state =
            selectedIds.intersection(liveIds);
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _resetOverviewScroll();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _overviewScrollController
      ..removeListener(_updateCompactHeaderOpacity)
      ..dispose();
    _compactHeaderOpacity.dispose();
    _bucketSubscription.close();
    _resetSubscription.close();
    _searchSubscription.close();
    _quickFilterSubscription.close();
    _labelFilterSubscription.close();
    _trashHovering.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final wide = screenWidth >= 900;
    final compact = screenWidth < 700;
    final bucket = ref.watch(noteBucketProvider);
    final selectionActive = ref.watch(_selectedNoteIdsProvider).isNotEmpty;
    ref.watch(noteSearchProvider);
    ref.watch(noteQuickFilterProvider);
    ref.watch(noteLabelFilterProvider);
    final baseNotes = _filteredNotes;
    final filtered = _previewNotes(baseNotes);
    final trashCount =
        widget.notes.where((note) => note.state == 'trashed').length;
    final dragging = _draggedId != null;
    final listLayout = widget.layout == NoteOverviewLayout.list;
    final splitLayout = wide && listLayout;
    final showTrashTarget = dragging && bucket != 'trashed' && !compact;
    final header = _WorkspaceHeader(
      noteCount: baseNotes.length,
      compact: compact,
      wide: wide,
      email: widget.email,
      showEmailVerification: widget.showEmailVerification,
      layout: widget.layout,
      labels: _availableLabels,
      onEmptyTrash: trashCount == 0 ? null : _emptyTrash,
      emptyingTrash: _emptyingTrash,
      inlineFilters: splitLayout,
    );
    final compactHeaderChrome = _WorkspaceHeader(
      noteCount: baseNotes.length,
      compact: compact,
      wide: wide,
      email: widget.email,
      showEmailVerification: widget.showEmailVerification,
      layout: widget.layout,
      labels: _availableLabels,
      onEmptyTrash: trashCount == 0 ? null : _emptyTrash,
      emptyingTrash: _emptyingTrash,
      compactPart: _CompactHeaderPart.chrome,
    );
    final compactHeaderBody = _WorkspaceHeader(
      noteCount: baseNotes.length,
      compact: compact,
      wide: wide,
      email: widget.email,
      showEmailVerification: widget.showEmailVerification,
      layout: widget.layout,
      labels: _availableLabels,
      onEmptyTrash: trashCount == 0 ? null : _emptyTrash,
      emptyingTrash: _emptyingTrash,
      compactPart: _CompactHeaderPart.body,
    );
    final overview = splitLayout
        ? _buildSplitOverview(baseNotes, bucket)
        : listLayout
            ? _buildMobileList(
                baseNotes,
                bucket,
                topPadding: compact ? _compactHeaderHeight : 0,
                controller: compact ? _overviewScrollController : null,
              )
            : _buildCardOverview(
                sourceNotes: baseNotes,
                filtered: filtered,
                compact: compact,
                wide: wide,
                screenWidth: screenWidth,
                dragging: dragging,
                bucket: bucket,
                topPadding: compact ? _compactHeaderHeight : 0,
                controller: compact ? _overviewScrollController : null,
              );
    return GestureDetector(
      key: const ValueKey('notes-workspace-selection-dismiss-area'),
      behavior: HitTestBehavior.translucent,
      // Do not add a tap recognizer during normal browsing: even an idle
      // recognizer subtly changes the scroll gesture arena and its momentum.
      onTap: selectionActive ? _clearSelection : null,
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (wide) const _SideRail(),
              Expanded(
                child: compact
                    ? Stack(
                        children: [
                          Positioned.fill(
                            child: RepaintBoundary(child: overview),
                          ),
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: _MeasureSize(
                              onChange: _updateCompactHeaderHeight,
                              child: _FadingCompactHeader(
                                opacity: _compactHeaderOpacity,
                                child: _NotesGlassHeaderCard(
                                  child: compactHeaderBody,
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: compactHeaderChrome,
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          header,
                          Expanded(child: overview),
                        ],
                      ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            // Stay above the floating mobile navigation while dragging so the
            // drop target remains reachable even though the nav overlays notes.
            bottom: compact ? 92 : 20,
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
      ),
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
    double topPadding = 0,
    ScrollController? controller,
  }) {
    final selectedNoteIds = ref.watch(_selectedNoteIdsProvider);
    final selectionActive = selectedNoteIds.isNotEmpty;
    final noteColumnCount = compact ? 2 : _noteColumnCount(screenWidth, wide);
    final progressivelyRendered =
        compact && filtered.length > _visibleCardLimit;
    final renderedNotes = progressivelyRendered
        ? filtered.take(_visibleCardLimit).toList(growable: false)
        : filtered;
    return CustomScrollView(
      key: const ValueKey('cards-note-overview'),
      controller: controller,
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(height: topPadding + (wide ? 8 : 10)),
        ),
        if (filtered.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(),
          )
        else
          SliverPadding(
            padding: compact
                ? const EdgeInsets.fromLTRB(12, 0, 12, 112)
                : EdgeInsets.fromLTRB(
                    wide ? 32 : 12,
                    0,
                    wide ? 32 : 12,
                    48,
                  ),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  _AnimatedCardGrid(
                    sourceNotes: sourceNotes,
                    notes: renderedNotes,
                    columnCount: noteColumnCount,
                    dropIndex: _dropIndex,
                    onDropIndexChanged: _setDropIndex,
                    onCommitReorder: (draggedId, targetIndex) =>
                        _commitReorder(draggedId, targetIndex, bucket),
                    onDragStarted: _startDrag,
                    onDragEnded: _clearDragPreview,
                    trashHovering: _trashHovering,
                    selectedNoteIds: selectedNoteIds,
                    selectionActive: selectionActive,
                    onToggleSelection: _toggleSelection,
                    onLongPressSelect: _selectFromLongPress,
                  ),
                  if (progressivelyRendered)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: OutlinedButton.icon(
                        key: const ValueKey('load-more-note-cards'),
                        onPressed: () => setState(
                          () => _visibleCardLimit += _cardPageSize,
                        ),
                        icon: const Icon(AppIcons.chevronDown),
                        label: Text(
                          ref.read(l10nProvider).t('loadMoreNotes'),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMobileList(
    List<PlainNote> notes,
    String bucket, {
    double topPadding = 0,
    ScrollController? controller,
  }) {
    if (notes.isEmpty) return const _EmptyState();
    return _NoteListPane(
      key: const ValueKey('mobile-note-list'),
      notes: notes,
      controller: controller,
      topPadding: topPadding + 8,
      bottomPadding: 96,
      dragging: _draggedId != null,
      draggedId: _draggedId,
      dropIndex: _dropIndex,
      trashHovering: _trashHovering,
      onDropIndexChanged: _setDropIndex,
      onCommitReorder: (draggedId, targetIndex) =>
          _commitReorder(draggedId, targetIndex, bucket),
      onDragStarted: _startDrag,
      onDragEnded: _clearDragPreview,
      selectedNoteIds: ref.watch(_selectedNoteIdsProvider),
      selectionActive: ref.watch(_selectedNoteIdsProvider).isNotEmpty,
      onToggleSelection: _toggleSelection,
      onLongPressSelect: _selectFromLongPress,
      onSelected: _openOrToggleSelection,
    );
  }

  void _updateCompactHeaderHeight(Size size) {
    if (!mounted || (size.height - _compactHeaderHeight).abs() < 0.5) return;
    setState(() => _compactHeaderHeight = size.height);
  }

  void _updateCompactHeaderOpacity() {
    if (!_overviewScrollController.hasClients) return;
    final next = (1 - (_overviewScrollController.offset / 30)).clamp(0.0, 1.0);
    if ((next - _compactHeaderOpacity.value).abs() < 0.01) return;
    _compactHeaderOpacity.value = next;
  }

  void _resetOverviewScroll() {
    if (!mounted) return;
    _compactHeaderOpacity.value = 1;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_overviewScrollController.hasClients) return;
      _overviewScrollController.jumpTo(0);
    });
  }

  void _resetCardLimit() {
    if (!mounted || _visibleCardLimit == _cardPageSize) return;
    setState(() => _visibleCardLimit = _cardPageSize);
  }

  Widget _buildSplitOverview(List<PlainNote> notes, String bucket) {
    final selected = _selectedNote(notes);
    final editorShape = RoundedSuperellipseBorder(
      borderRadius: const BorderRadius.only(
        topLeft: Radius.circular(AppRadii.xxl),
      ),
      side: BorderSide(
        color: Theme.of(context)
            .colorScheme
            .outlineVariant
            .withValues(alpha: 0.42),
      ),
    );
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
            draggedId: _draggedId,
            dropIndex: _dropIndex,
            trashHovering: _trashHovering,
            onDropIndexChanged: _setDropIndex,
            onCommitReorder: (draggedId, targetIndex) =>
                _commitReorder(draggedId, targetIndex, bucket),
            onDragStarted: _startDrag,
            onDragEnded: _clearDragPreview,
            selectedNoteIds: ref.watch(_selectedNoteIdsProvider),
            selectionActive: ref.watch(_selectedNoteIdsProvider).isNotEmpty,
            onToggleSelection: _toggleSelection,
            onLongPressSelect: _selectFromLongPress,
            onSelected: (note) {
              if (ref.read(_selectedNoteIdsProvider).isNotEmpty) {
                _toggleSelection(note);
                return;
              }
              if (_selectedNoteId == note.localId) return;
              setState(() => _selectedNoteId = note.localId);
            },
          ),
        ),
        Expanded(
          key: const ValueKey('desktop-note-editor-pane'),
          flex: 7,
          child: ClipPath(
            key: const ValueKey('desktop-note-editor-frame'),
            clipper: ShapeBorderClipper(
              shape: editorShape,
            ),
            child: DecoratedBox(
              key: const ValueKey('desktop-note-editor-border'),
              decoration: ShapeDecoration(shape: editorShape),
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
    final contentWidth = screenWidth - 212 - 64;
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

  void _openOrToggleSelection(PlainNote note) {
    if (ref.read(_selectedNoteIdsProvider).isNotEmpty) {
      _toggleSelection(note);
      return;
    }
    _openEditor(context, ref, note);
  }

  void _selectFromLongPress(PlainNote note) {
    _toggleSelection(note);
  }

  void _toggleSelection(PlainNote note) {
    if (!mounted) return;
    final next = {...ref.read(_selectedNoteIdsProvider)};
    if (!next.add(note.localId)) next.remove(note.localId);
    ref.read(_selectedNoteIdsProvider.notifier).state = next;
  }

  void _clearSelection() {
    if (ref.read(_selectedNoteIdsProvider).isEmpty) return;
    ref.read(_selectedNoteIdsProvider.notifier).state = const {};
  }

  void _setDropIndex(int? value) {
    if (!mounted || _dropIndex == value) return;
    setState(() => _dropIndex = value);
  }

  void _startDrag(PlainNote note) {
    if (!mounted || ref.read(_selectedNoteIdsProvider).isNotEmpty) return;
    _trashHovering.value = false;
    ref.read(_dragTrashHoverProvider.notifier).state = false;
    // Seed the drop index with the note's own position so the placeholder
    // gap opens exactly where the note sat. Without this the list collapses
    // by one row the moment the drag starts and the pointer ends up over the
    // wrong half of the row below.
    final origin = _filteredNotes.indexWhere(
      (candidate) => candidate.localId == note.localId,
    );
    setState(() {
      _draggedId = note.localId;
      _dropIndex = origin < 0 ? null : origin;
    });
    ref.read(_draggedNoteProvider.notifier).state = note;
  }

  void _clearDragPreview() {
    if (!mounted) return;
    _trashHovering.value = false;
    ref.read(_dragTrashHoverProvider.notifier).state = false;
    if (_draggedId == null && _dropIndex == null) return;
    setState(() {
      _draggedId = null;
      _dropIndex = null;
    });
    ref.read(_draggedNoteProvider.notifier).state = null;
  }

  void _moveToTrash(PlainNote note) {
    _clearDragPreview();
    _changeNoteStateWithFeedback(
      context: context,
      ref: ref,
      note: note,
      nextState: 'trashed',
    );
  }

  Future<void> _emptyTrash() async {
    if (_emptyingTrash) return;
    final trashedCount =
        widget.notes.where((note) => note.state == 'trashed').length;
    if (trashedCount == 0) return;
    final l10n = ref.read(l10nProvider);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(AppIcons.trash2),
        title: Text(l10n.t('emptyTrashTitle')),
        content: Text(
          l10n.t(
            'emptyTrashConfirmation',
            params: {'count': trashedCount},
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.t('cancel')),
          ),
          FilledButton(
            key: const ValueKey('confirm-empty-trash'),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(l10n.t('deleteAll')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _emptyingTrash = true);
    try {
      final deletedCount =
          await ref.read(notesControllerProvider.notifier).emptyTrash();
      if (!mounted) return;
      showAppInfoBar(
        context,
        message: l10n.t('trashEmptied', params: {'count': deletedCount}),
        avoidMobileNavigation: true,
      );
    } catch (_) {
      if (!mounted) return;
      showAppInfoBar(
        context,
        message: l10n.t('emptyTrashFailed'),
        avoidMobileNavigation: true,
      );
    } finally {
      if (mounted) setState(() => _emptyingTrash = false);
    }
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
    return switch (ref.read(noteQuickFilterProvider)) {
      NoteQuickFilter.favorites =>
        visible.where((note) => note.pinned).toList(),
      NoteQuickFilter.todo =>
        visible.where((note) => note.checklist.isNotEmpty).toList(),
      NoteQuickFilter.label => () {
          final label = ref.read(noteLabelFilterProvider);
          if (label == null) return visible;
          return visible.where((note) => note.labels.contains(label)).toList();
        }(),
      NoteQuickFilter.all => visible,
    };
  }

  /// Every label in use across the current note set, alphabetically.
  List<String> get _availableLabels {
    final labels = <String>{};
    for (final note in widget.notes) {
      if (note.state == 'deleted') continue;
      labels.addAll(note.labels);
    }
    final sorted = labels.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }
}

void _changeNoteStateWithFeedback({
  required BuildContext context,
  required WidgetRef ref,
  required PlainNote note,
  required String nextState,
}) {
  final previousState = note.state;
  final notesController = ref.read(notesControllerProvider.notifier);
  final transition = notesController.changeState(note, nextState);
  final l10n = ref.read(l10nProvider);
  final messageKey = switch (nextState) {
    'archived' => 'noteArchived',
    'active' => 'noteRestored',
    'deleted' => 'noteDeletedPermanently',
    _ => 'noteMovedToTrash',
  };
  showAppInfoBar(
    context,
    message: l10n.t(messageKey),
    actionLabel: l10n.t('undo'),
    avoidMobileNavigation: true,
    onAction: () => unawaited(() async {
      await transition;
      await notesController.changeState(note, previousState);
    }()),
  );
}

enum _CompactHeaderPart { all, chrome, body }

class _WorkspaceHeader extends ConsumerWidget {
  const _WorkspaceHeader({
    required this.noteCount,
    required this.compact,
    required this.wide,
    required this.email,
    required this.showEmailVerification,
    required this.layout,
    required this.labels,
    required this.onEmptyTrash,
    required this.emptyingTrash,
    this.compactPart = _CompactHeaderPart.all,
    this.inlineFilters = false,
  });

  final int noteCount;
  final bool compact;
  final bool wide;
  final String email;
  final bool showEmailVerification;
  final NoteOverviewLayout layout;
  final List<String> labels;
  final VoidCallback? onEmptyTrash;
  final bool emptyingTrash;
  final _CompactHeaderPart compactPart;
  final bool inlineFilters;

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
    final textTheme = Theme.of(context).textTheme;
    final compactTopPadding = MediaQuery.paddingOf(context).top + 8;
    final compactHorizontalPadding = compact ? 16.0 : 32.0;
    final compactToolbarHeight = 46.0;
    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: compact ? textTheme.headlineMedium : textTheme.displayMedium,
        ),
        SizedBox(height: compact ? 1 : 4),
        _HeaderDateLine(compact: compact),
      ],
    );
    final trashButton = bucket == 'trashed' && onEmptyTrash != null
        ? Padding(
            padding: EdgeInsets.only(
              left: compact ? 8 : 16,
              bottom: compact ? 0 : 4,
            ),
            child: _EmptyTrashButton(
              compact: compact,
              busy: emptyingTrash,
              onPressed: onEmptyTrash,
            ),
          )
        : null;
    final count = Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        '$noteCount',
        style: textTheme.titleMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
    final filters = _QuickFilterChips(
      noteCount: noteCount,
      labels: labels,
      dense: inlineFilters,
    );
    final titleAndFilters = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (inlineFilters)
          Row(
            key: const ValueKey('desktop-inline-note-filters'),
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 230),
                child: titleBlock,
              ),
              if (trashButton != null) trashButton,
              const SizedBox(width: 24),
              Expanded(child: filters),
            ],
          )
        else ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: titleBlock),
              if (trashButton != null) trashButton,
              if (!compact) count,
            ],
          ),
          SizedBox(height: compact ? 12 : 18),
          filters,
        ],
        if (showEmailVerification) ...[
          SizedBox(height: compact ? 10 : 12),
          _EmailVerificationBanner(email: email),
        ],
      ],
    );
    if (compact && compactPart == _CompactHeaderPart.chrome) {
      return Padding(
        key: const ValueKey('notes-workspace-header-chrome'),
        padding: EdgeInsets.fromLTRB(
          compactHorizontalPadding,
          compactTopPadding,
          compactHorizontalPadding,
          0,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _MobileLayoutButton(layout: layout),
            _AccountButton(
              key: const ValueKey('mobile-account-menu'),
              email: email,
              compact: true,
            ),
          ],
        ),
      );
    }
    if (compact && compactPart == _CompactHeaderPart.body) {
      return Padding(
        key: const ValueKey('notes-workspace-header-body'),
        padding: EdgeInsets.fromLTRB(
          compactHorizontalPadding,
          compactTopPadding + compactToolbarHeight + 14,
          compactHorizontalPadding,
          16,
        ),
        child: titleAndFilters,
      );
    }
    return Padding(
      key: const ValueKey('notes-workspace-header'),
      padding: EdgeInsets.fromLTRB(
        compactHorizontalPadding,
        wide ? 18 : (compact ? compactTopPadding : 10),
        compactHorizontalPadding,
        16,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MobileLayoutButton(layout: layout),
                _AccountButton(
                  key: const ValueKey('mobile-account-menu'),
                  email: email,
                  compact: true,
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],
          titleAndFilters,
        ],
      ),
    );
  }
}

class _EmptyTrashButton extends ConsumerWidget {
  const _EmptyTrashButton({
    required this.compact,
    required this.busy,
    required this.onPressed,
  });

  final bool compact;
  final bool busy;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final scheme = Theme.of(context).colorScheme;
    return TextButton.icon(
      key: const ValueKey('empty-trash-button'),
      onPressed: busy ? null : onPressed,
      style: TextButton.styleFrom(
        foregroundColor: scheme.error,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12,
          vertical: compact ? 7 : 9,
        ),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      icon: busy
          ? SizedBox.square(
              dimension: compact ? 16 : 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.error,
              ),
            )
          : Icon(AppIcons.trash2, size: compact ? 17 : 19),
      label: Text(
        l10n.t('emptyTrash'),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// A viewport-fixed content header for mobile/tablet. It reserves space above
/// the notes and fades out as the list scrolls underneath it.
class _NotesGlassHeaderCard extends StatelessWidget {
  const _NotesGlassHeaderCard({required this.child});

  final Widget child;
  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      key: const ValueKey('notes-glass-header-card'),
      child: child,
    );
  }
}

class _FadingCompactHeader extends StatelessWidget {
  const _FadingCompactHeader({
    required this.opacity,
    required this.child,
  });

  final ValueListenable<double> opacity;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: opacity,
      child: child,
      builder: (context, value, child) {
        return TweenAnimationBuilder<double>(
          tween: Tween<double>(end: value),
          duration: const Duration(milliseconds: 170),
          curve: Curves.easeOutCubic,
          child: child,
          builder: (context, animated, child) {
            final eased = Curves.easeOutCubic.transform(animated);
            return IgnorePointer(
              ignoring: animated < 0.05,
              child: Opacity(
                key: const ValueKey('notes-header-scroll-fade'),
                opacity: animated,
                child: Transform.translate(
                  offset: Offset(0, -18 * (1 - eased)),
                  child: Transform.scale(
                    alignment: Alignment.topCenter,
                    scale: 0.985 + 0.015 * eased,
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _HeaderDateLine extends ConsumerWidget {
  const _HeaderDateLine({required this.compact});

  final bool compact;

  static const _months = {
    'en': [
      'january',
      'february',
      'march',
      'april',
      'may',
      'june',
      'july',
      'august',
      'september',
      'october',
      'november',
      'december'
    ],
    'de': [
      'januar',
      'februar',
      'märz',
      'april',
      'mai',
      'juni',
      'juli',
      'august',
      'september',
      'oktober',
      'november',
      'dezember'
    ],
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final now = DateTime.now();
    final months = _months[l10n.languageCode] ?? _months['en']!;
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontSize: compact ? 14 : 15,
        );
    return Text.rich(
      key: const ValueKey('notes-header-date'),
      TextSpan(
        children: [
          TextSpan(
            text: '${now.day} ',
            style: base?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface.withValues(alpha: 0.75),
            ),
          ),
          TextSpan(text: months[now.month - 1], style: base),
        ],
      ),
    );
  }
}

class _QuickFilterChips extends ConsumerWidget {
  const _QuickFilterChips({
    required this.noteCount,
    required this.labels,
    this.dense = false,
  });

  final int noteCount;
  final List<String> labels;
  final bool dense;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final active = ref.watch(noteQuickFilterProvider);
    final activeLabel = ref.watch(noteLabelFilterProvider);

    void select(NoteQuickFilter filter, [String? label]) {
      ref.read(noteQuickFilterProvider.notifier).state = filter;
      ref.read(noteLabelFilterProvider.notifier).state = label;
    }

    return SingleChildScrollView(
      key: const ValueKey('note-filter-chips'),
      scrollDirection: Axis.horizontal,
      clipBehavior: Clip.none,
      child: Row(
        children: [
          _FilterChip(
            key: const ValueKey('note-filter-all'),
            label: l10n.t('filterAll'),
            count: noteCount,
            dense: dense,
            selected: active == NoteQuickFilter.all,
            onTap: () => select(NoteQuickFilter.all),
          ),
          SizedBox(width: dense ? 8 : 10),
          _FilterChip(
            label: l10n.t('filterFavorites'),
            dense: dense,
            selected: active == NoteQuickFilter.favorites,
            onTap: () => select(NoteQuickFilter.favorites),
          ),
          SizedBox(width: dense ? 8 : 10),
          _FilterChip(
            label: l10n.t('filterTodo'),
            dense: dense,
            selected: active == NoteQuickFilter.todo,
            onTap: () => select(NoteQuickFilter.todo),
          ),
          for (final label in labels) ...[
            SizedBox(width: dense ? 8 : 10),
            _FilterChip(
              label: label,
              accent: true,
              dense: dense,
              selected: active == NoteQuickFilter.label && activeLabel == label,
              onTap: () => select(NoteQuickFilter.label, label),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.accent = false,
    this.dense = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final bool accent;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = selected
        ? (accent
            ? brandLavender
            : (dark ? const Color(0xffe8e1f2) : const Color(0xfffffcff)))
        : (dark ? const Color(0xff2a3432) : const Color(0xffe9e3ec));
    final textColor = selected
        ? (accent ? const Color(0xff231a38) : const Color(0xff211d27))
        : scheme.onSurface.withValues(alpha: 0.9);
    final borderColor = selected
        ? (dark
            ? Colors.white.withValues(alpha: 0.24)
            : Colors.white.withValues(alpha: 0.9))
        : (dark
            ? Colors.white.withValues(alpha: 0.1)
            : scheme.outlineVariant.withValues(alpha: 0.72));
    final countFill = dark && selected
        ? const Color(0xff4b4354)
        : dark
            ? const Color(0xffd8dfdc)
            : const Color(0xffd9d4da);
    final countTextColor =
        dark && selected ? const Color(0xfff8f4fa) : const Color(0xff27302e);
    final verticalPadding = dense ? 7.0 : (compact ? 8.0 : 11.0);
    final horizontalPadding = dense ? 14.0 : (compact ? 16.0 : 20.0);
    final content = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.fromLTRB(
            count != null ? (dense ? 6 : 7) : horizontalPadding,
            verticalPadding,
            horizontalPadding,
            verticalPadding,
          ),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            border: Border.all(color: borderColor, width: 0.8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (count != null) ...[
                Container(
                  key: const ValueKey('note-filter-count-badge'),
                  width: dense ? 22 : (compact ? 24 : 26),
                  height: dense ? 22 : (compact ? 24 : 26),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: countFill,
                  ),
                  child: Text(
                    '$count',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: dense ? 12 : 13,
                          fontWeight: FontWeight.w700,
                          color: countTextColor,
                        ),
                  ),
                ),
                SizedBox(width: dense ? 7 : (compact ? 8 : 10)),
              ],
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontSize: dense ? 14 : null,
                      color: textColor,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadii.pill),
      // Compact chips are deliberately near-opaque foreground surfaces. A
      // second blur here would muddy their colour and add three saveLayers to
      // every scrolling frame without improving their separation.
      child: compact
          ? content
          : BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
              child: content,
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final iosIconTint = dark ? const Color(0xfff8fbf9) : scheme.onSurface;
    final cards = layout == NoteOverviewLayout.cards;
    final tooltip = l10n.t(
      cards ? 'switchToListView' : 'switchToCardsView',
    );
    void toggleLayout() =>
        ref.read(appPreferencesProvider.notifier).setNoteOverviewLayout(
              cards ? NoteOverviewLayout.list : NoteOverviewLayout.cards,
            );
    if (_usesIosNativeControls) {
      return Tooltip(
        message: tooltip,
        child: SizedBox.square(
          key: const ValueKey('mobile-layout-toggle'),
          dimension: _MobileBottomNavState._iosItemSize,
          child: CNButton.icon(
            icon: CNSymbol(
              'square.grid.2x2',
              size: AppSizes.iosCompactHeaderIcon,
              mode: CNSymbolRenderingMode.monochrome,
            ),
            onPressed: toggleLayout,
            tint: iosIconTint,
            config: const CNButtonConfig(
              style: CNButtonStyle.glass,
              width: _MobileBottomNavState._iosItemSize,
              minHeight: _MobileBottomNavState._iosItemSize,
              padding: EdgeInsets.all(18),
              glassEffectId: 'notes-layout-toggle',
              glassEffectInteractive: true,
            ),
          ),
        ),
      );
    }
    return Tooltip(
      message: tooltip,
      child: _MobileHeaderGlassButtonSurface(
        key: const ValueKey('mobile-layout-toggle'),
        onTap: toggleLayout,
        child: Icon(
          AppIcons.grid2X2,
          size: 20,
          color: scheme.onSurface,
        ),
      ),
    );
  }
}

class _MobileHeaderGlassButtonSurface extends StatelessWidget {
  const _MobileHeaderGlassButtonSurface({
    super.key,
    required this.child,
    required this.onTap,
  });

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(_MobileBottomNavState._itemSize / 2),
    );
    final surface = Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          key: const ValueKey('mobile-header-button-fill'),
          decoration: ShapeDecoration(
            color: AppChromeGlass.tint(brightness),
            shape: shape.copyWith(
              side: BorderSide(
                color: AppChromeGlass.outerStroke(brightness),
                width: 1,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(0.75),
          child: DecoratedBox(
            key: const ValueKey('mobile-header-button-highlight'),
            decoration: ShapeDecoration(
              shape: shape.copyWith(
                side: BorderSide(
                  color: AppChromeGlass.innerStroke(brightness),
                  width: 0.55,
                ),
              ),
            ),
          ),
        ),
        Center(child: child),
      ],
    );
    final interactiveSurface = Material(
      color: Colors.transparent,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: surface,
      ),
    );
    return SizedBox.square(
      dimension: _MobileBottomNavState._itemSize,
      child: RepaintBoundary(
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: shape,
            shadows: [
              BoxShadow(
                color: AppChromeGlass.shadow(brightness),
                blurRadius: brightness == Brightness.dark ? 14 : 12,
                spreadRadius: brightness == Brightness.dark ? 0 : -1,
                offset: Offset(0, brightness == Brightness.dark ? 8 : 4),
              ),
            ],
          ),
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: shape),
            child: BackdropFilter(
              key: const ValueKey('mobile-header-button-backdrop'),
              filter: _NotesChromeGlass.filter(brightness),
              child: interactiveSurface,
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
    required this.selectedNoteIds,
    required this.selectionActive,
    required this.onToggleSelection,
    required this.onLongPressSelect,
    this.draggedId,
    this.selectedNoteId,
    this.controller,
    this.topPadding = 8,
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
  final Set<String> selectedNoteIds;
  final bool selectionActive;
  final ValueChanged<PlainNote> onToggleSelection;
  final ValueChanged<PlainNote> onLongPressSelect;
  final String? draggedId;
  final String? selectedNoteId;
  final ScrollController? controller;
  final double topPadding;
  final double bottomPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    // The dragged row stays mounted (collapsed to zero height) so Flutter keeps
    // delivering onDragUpdate — it guards that callback with `mounted`. Its
    // slot is represented by the animated gap instead.
    final draggedIndex = draggedId == null
        ? -1
        : notes.indexWhere((note) => note.localId == draggedId);

    /// Maps a display index to the insertion index space `reorderNotes`
    /// expects: the position within the list *without* the dragged note.
    int insertionIndexFor(int displayIndex) =>
        draggedIndex < 0 || displayIndex < draggedIndex
            ? displayIndex
            : displayIndex - 1;

    final trailingIndex = notes.length - (draggedIndex >= 0 ? 1 : 0);

    return ListView.builder(
      controller: controller,
      padding: EdgeInsets.fromLTRB(12, topPadding, 12, bottomPadding),
      itemCount: notes.length + 1,
      itemBuilder: (context, index) {
        // Trailing drop zone so a note can be moved to the very end.
        if (index == notes.length) {
          return _NoteListDropEdge(
            index: trailingIndex,
            active: dropIndex == trailingIndex && draggedIndex >= 0,
            dragging: dragging,
            onDropIndexChanged: onDropIndexChanged,
            onCommitReorder: onCommitReorder,
          );
        }
        final note = notes[index];
        final isDragged = index == draggedIndex;
        final item = _NoteListItem(
          note: note,
          l10n: l10n,
          selected: selectionActive
              ? selectedNoteIds.contains(note.localId)
              : note.localId == selectedNoteId,
          multiSelected: selectedNoteIds.contains(note.localId),
          selectionActive: selectionActive,
          onToggleSelection: () => onToggleSelection(note),
          onTap: () => onSelected(note),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _NoteListGap(
              active: draggedIndex >= 0 &&
                  !isDragged &&
                  dropIndex == insertionIndexFor(index),
            ),
            _DraggableNoteListEntry(
              key: ValueKey('note-list-item-${note.localId}'),
              note: note,
              index: index,
              insertionIndex: insertionIndexFor(index),
              dragging: dragging,
              dropIndex: dropIndex,
              trashHovering: trashHovering,
              onDropIndexChanged: onDropIndexChanged,
              onCommitReorder: onCommitReorder,
              onDragStarted: () => onDragStarted(note),
              onDragEnded: () {
                final stillPendingHere =
                    ref.read(_draggedNoteProvider)?.localId == note.localId;
                if (stillPendingHere && dropIndex != null) {
                  onCommitReorder(note.localId, dropIndex!);
                } else {
                  onDragEnded();
                }
              },
              dragEnabled: !selectionActive,
              onLongPressSelect: () => onLongPressSelect(note),
              child: item,
            ),
            _NoteListSeparator(collapsed: isDragged),
          ],
        );
      },
    );
  }
}

/// Animated placeholder that opens up where the dragged note will land.
class _NoteListGap extends StatelessWidget {
  const _NoteListGap({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: active
          ? Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: SizedBox(
                height: 64,
                width: double.infinity,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: brandLavender.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(AppRadii.md),
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

/// Keeps row spacing in the same animated slot as the row itself. This avoids
/// a six-pixel snap when a drag preview becomes the committed list order.
class _NoteListSeparator extends StatelessWidget {
  const _NoteListSeparator({required this.collapsed});

  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      height: collapsed ? 0 : 6,
    );
  }
}

/// Drop target covering the empty space after the last row.
class _NoteListDropEdge extends StatelessWidget {
  const _NoteListDropEdge({
    required this.index,
    required this.active,
    required this.dragging,
    required this.onDropIndexChanged,
    required this.onCommitReorder,
  });

  final int index;
  final bool active;
  final bool dragging;
  final ValueChanged<int?> onDropIndexChanged;
  final void Function(String draggedId, int targetIndex) onCommitReorder;

  @override
  Widget build(BuildContext context) {
    return DragTarget<PlainNote>(
      onWillAcceptWithDetails: (_) => dragging,
      onMove: (_) {
        if (dragging) onDropIndexChanged(index);
      },
      onAcceptWithDetails: (details) =>
          onCommitReorder(details.data.localId, index),
      builder: (context, _, __) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _NoteListGap(active: active),
          SizedBox(height: dragging ? 96 : 8, width: double.infinity),
        ],
      ),
    );
  }
}

class _DraggableNoteListEntry extends StatefulWidget {
  const _DraggableNoteListEntry({
    super.key,
    required this.note,
    required this.index,
    required this.insertionIndex,
    required this.dragging,
    required this.dropIndex,
    required this.trashHovering,
    required this.onDropIndexChanged,
    required this.onCommitReorder,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.dragEnabled,
    required this.onLongPressSelect,
    required this.child,
  });

  final PlainNote note;
  final int index;

  /// Position of this row in the list *without* the dragged note.
  final int insertionIndex;
  final bool dragging;
  final int? dropIndex;
  final ValueListenable<bool> trashHovering;
  final ValueChanged<int?> onDropIndexChanged;
  final void Function(String draggedId, int targetIndex) onCommitReorder;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;
  final bool dragEnabled;
  final VoidCallback onLongPressSelect;
  final Widget child;

  @override
  State<_DraggableNoteListEntry> createState() =>
      _DraggableNoteListEntryState();
}

class _DraggableNoteListEntryState extends State<_DraggableNoteListEntry> {
  final _entryKey = GlobalKey();
  int? _hoverDropIndex;

  @override
  Widget build(BuildContext context) {
    return DragTarget<PlainNote>(
      key: ValueKey('note-list-drop-${widget.note.localId}'),
      onWillAcceptWithDetails: (_) => widget.dragging,
      onMove: (details) {
        final box = _entryKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        // Draggables use [pointerDragAnchorStrategy], so the target offset is
        // the live pointer position and is available before onDragUpdate.
        final pointer = details.offset;
        final local = box.globalToLocal(pointer);
        final nextIndex = local.dy < box.size.height / 2
            ? widget.insertionIndex
            : widget.insertionIndex + 1;
        _hoverDropIndex = nextIndex;
        if (widget.dropIndex != nextIndex) {
          widget.onDropIndexChanged(nextIndex);
        }
      },
      onAcceptWithDetails: (details) {
        final targetIndex =
            _hoverDropIndex ?? widget.dropIndex ?? widget.insertionIndex;
        _hoverDropIndex = null;
        widget.onCommitReorder(
          details.data.localId,
          targetIndex,
        );
      },
      builder: (context, _, __) => AnimatedSize(
        key: ValueKey('animated-note-list-entry-${widget.note.localId}'),
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: KeyedSubtree(
          key: _entryKey,
          child: _MeasuredNoteDraggable(
            key: ValueKey('note-list-drag-${widget.note.localId}'),
            note: widget.note,
            trashHovering: widget.trashHovering,
            onDragStarted: widget.onDragStarted,
            onDragEnded: widget.onDragEnded,
            dragEnabled: widget.dragEnabled,
            onLongPressSelect: widget.onLongPressSelect,
            childWhenDragging: const SizedBox.shrink(),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

class _NoteListItem extends StatefulWidget {
  const _NoteListItem({
    required this.note,
    required this.l10n,
    required this.selected,
    required this.multiSelected,
    required this.selectionActive,
    required this.onToggleSelection,
    required this.onTap,
  });

  final PlainNote note;
  final AppL10n l10n;
  final bool selected;
  final bool multiSelected;
  final bool selectionActive;
  final VoidCallback onToggleSelection;
  final VoidCallback onTap;

  @override
  State<_NoteListItem> createState() => _NoteListItemState();
}

class _NoteListItemState extends State<_NoteListItem> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final note = widget.note;
    final l10n = widget.l10n;
    final scheme = Theme.of(context).colorScheme;
    final title = _noteListTitle(note, l10n);
    final preview = _noteListPreview(note);
    final showPreview = preview.isNotEmpty && preview != title;
    final noteColor = note.color == 0xffffffff
        ? scheme.outlineVariant
        : brandNoteSurfaceColor(context, note.color);
    final desktop = MediaQuery.sizeOf(context).width >= 700;
    final showSelectionControl = desktop && (_hovered || widget.multiSelected);
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SizedBox(
        height: 64,
        child: Material(
          color: widget.selected
              ? scheme.surfaceContainerHighest
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            child: Padding(
              key: ValueKey('note-list-content-${note.localId}'),
              padding: const EdgeInsets.fromLTRB(12, 9, 10, 9),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (desktop) ...[
                    SizedBox(
                      width: 28,
                      height: 38,
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: _NoteSelectionControl(
                          noteId: note.localId,
                          visible: showSelectionControl,
                          selected: widget.multiSelected,
                          showCheck: _hovered,
                          onPressed: widget.onToggleSelection,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
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
                                  AppIcons.heartFill,
                                  size: 15,
                                  color: brandLavender,
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
                                      ?.copyWith(
                                          color: scheme.onSurfaceVariant),
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
    required this.selectedNoteIds,
    required this.selectionActive,
    required this.onToggleSelection,
    required this.onLongPressSelect,
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
  final Set<String> selectedNoteIds;
  final bool selectionActive;
  final ValueChanged<PlainNote> onToggleSelection;
  final ValueChanged<PlainNote> onLongPressSelect;

  @override
  ConsumerState<_AnimatedCardGrid> createState() => _AnimatedCardGridState();
}

class _AnimatedCardGridState extends ConsumerState<_AnimatedCardGrid> {
  static const _gap = 12.0;
  static const _fallbackHeight = 144.0;
  static const _motionDuration = Duration(milliseconds: 190);
  static const _motionCurve = Curves.easeOutCubic;

  final Map<String, double> _heights = {};
  final Map<String, double> _pendingHeights = {};
  final _gridKey = GlobalKey();
  String? _activeDraggedId;
  int? _activeDropIndex;
  var _animatePositions = false;
  var _heightUpdateScheduled = false;
  Offset? _lastEvaluatedDragPosition;

  @override
  void didUpdateWidget(covariant _AnimatedCardGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.notes, widget.notes)) return;
    final liveIds = widget.notes.map((note) => note.localId).toSet();
    _heights.removeWhere((noteId, _) => !liveIds.contains(noteId));
    _pendingHeights.removeWhere((noteId, _) => !liveIds.contains(noteId));
  }

  void _reportHeight(String noteId, Size size) {
    final previous = _pendingHeights[noteId] ?? _heights[noteId];
    if (!mounted ||
        (previous != null && (previous - size.height).abs() < 0.5)) {
      return;
    }
    _pendingHeights[noteId] = size.height;
    if (_heightUpdateScheduled) return;
    _heightUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _heightUpdateScheduled = false;
      if (!mounted || _pendingHeights.isEmpty) return;
      setState(() {
        _heights.addAll(_pendingHeights);
        _pendingHeights.clear();
        if (!_animatePositions &&
            widget.notes.every((note) => _heights.containsKey(note.localId))) {
          _animatePositions = true;
        }
      });
    });
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
        final previousPosition = _lastEvaluatedDragPosition;
        if (previousPosition != null &&
            (globalPosition - previousPosition).distanceSquared < 16) {
          return;
        }
        _lastEvaluatedDragPosition = globalPosition;
        final nextIndex = nearestDropIndex(dragged, globalPosition);
        _activeDraggedId = dragged.localId;
        _activeDropIndex = nextIndex;
        if (widget.dropIndex != nextIndex) {
          widget.onDropIndexChanged(nextIndex);
        }
      }

      void startDrag(PlainNote note) {
        _lastEvaluatedDragPosition = null;
        _activeDraggedId = note.localId;
        _activeDropIndex = widget.sourceNotes
            .indexWhere((candidate) => candidate.localId == note.localId);
        widget.onDragStarted(note);
      }

      void endDrag() {
        final draggedId = _activeDraggedId;
        final targetIndex = _activeDropIndex;
        final stillPendingHere = draggedId != null &&
            ref.read(_draggedNoteProvider)?.localId == draggedId;
        _lastEvaluatedDragPosition = null;
        _activeDraggedId = null;
        _activeDropIndex = null;
        if (stillPendingHere && targetIndex != null) {
          widget.onCommitReorder(draggedId, targetIndex);
        } else {
          widget.onDragEnded();
        }
      }

      return DragTarget<PlainNote>(
        key: const ValueKey('card-grid-drop-surface'),
        hitTestBehavior: HitTestBehavior.translucent,
        onWillAcceptWithDetails: (details) =>
            _activeDraggedId == details.data.localId,
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
            duration: AppMotion.duration(context, _motionDuration),
            curve: _motionCurve,
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: gridHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final placement in placements)
                    Positioned(
                      key: ValueKey(
                        'animated-note-placement-${placement.note.localId}',
                      ),
                      left: 0,
                      top: 0,
                      width: cardWidth,
                      child: TweenAnimationBuilder<Offset>(
                        key: ValueKey(
                          'animated-note-motion-${placement.note.localId}',
                        ),
                        tween:
                            Tween(end: Offset(placement.left, placement.top)),
                        duration: _animatePositions
                            ? AppMotion.duration(context, _motionDuration)
                            : Duration.zero,
                        curve: _motionCurve,
                        builder: (context, offset, child) =>
                            Transform.translate(
                          offset: offset,
                          child: child,
                        ),
                        child: _MeasureSize(
                          onChange: (size) =>
                              _reportHeight(placement.note.localId, size),
                          child: _CardDropPlacement(
                            note: placement.note,
                            selected: widget.selectedNoteIds
                                .contains(placement.note.localId),
                            selectionActive: widget.selectionActive,
                            onToggleSelection: widget.onToggleSelection,
                            onLongPressSelect: widget.onLongPressSelect,
                            onDragStarted: startDrag,
                            onDragUpdate: updateDropIndex,
                            onDragEnded: endDrag,
                            trashHovering: widget.trashHovering,
                          ),
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
    required this.selected,
    required this.selectionActive,
    required this.onToggleSelection,
    required this.onLongPressSelect,
    required this.onDragStarted,
    required this.onDragUpdate,
    required this.onDragEnded,
    required this.trashHovering,
  });

  final PlainNote note;
  final bool selected;
  final bool selectionActive;
  final ValueChanged<PlainNote> onToggleSelection;
  final ValueChanged<PlainNote> onLongPressSelect;
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
    final card = RepaintBoundary(
      child: _KeepNoteCard(
        note: note,
        selected: widget.selected,
        selectionActive: widget.selectionActive,
        onToggleSelection: () => widget.onToggleSelection(note),
        onTap: () => widget.selectionActive
            ? widget.onToggleSelection(note)
            : _openEditor(context, ref, note),
        onTogglePin: () =>
            ref.read(notesControllerProvider.notifier).togglePinned(note),
        onInvite: () => _showInviteSheet(context, ref, note),
        onReminder: () => _showReminderSheet(context, ref, note),
        onArchive: () => _changeNoteStateWithFeedback(
          context: context,
          ref: ref,
          note: note,
          nextState: 'archived',
        ),
        onTrash: () => _changeNoteStateWithFeedback(
          context: context,
          ref: ref,
          note: note,
          nextState: 'trashed',
        ),
        onRestore: () => _changeNoteStateWithFeedback(
          context: context,
          ref: ref,
          note: note,
          nextState: 'active',
        ),
        onDeleteForever: () => _changeNoteStateWithFeedback(
          context: context,
          ref: ref,
          note: note,
          nextState: 'deleted',
        ),
      ),
    );
    return _MeasuredNoteDraggable(
      key: ValueKey('compact-note-drag-${note.localId}'),
      note: note,
      trashHovering: widget.trashHovering,
      onDragStarted: () => widget.onDragStarted(note),
      onDragUpdate: (position) => widget.onDragUpdate(note, position),
      onDragEnded: widget.onDragEnded,
      dragEnabled: !widget.selectionActive,
      onLongPressSelect: () => widget.onLongPressSelect(note),
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
    final bucket = ref.watch(noteBucketProvider);
    final canCreate = bucket == 'active' || bucket == 'reminders';
    return SizedBox(
      width: 216,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (canCreate) ...[
              const _RailCreateButton(expanded: true),
              const SizedBox(height: 18),
            ],
            _RailButton(
              bucket: 'active',
              icon: AppIcons.notebookText,
              label: l10n.t('notes'),
              expanded: true,
            ),
            const SizedBox(height: 6),
            _RailButton(
              bucket: 'reminders',
              icon: AppIcons.bell,
              label: l10n.t('reminders'),
              expanded: true,
            ),
            const SizedBox(height: 6),
            _RailButton(
              bucket: 'archived',
              icon: AppIcons.archive,
              label: l10n.t('archive'),
              expanded: true,
            ),
            const SizedBox(height: 6),
            _RailButton(
              bucket: 'trashed',
              icon: AppIcons.trash,
              label: l10n.t('trash'),
              expanded: true,
            ),
          ],
        ),
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final fill = dark ? Colors.white : scheme.onSurface;
    final onFill = dark ? const Color(0xff17201f) : Colors.white;
    return Tooltip(
      message: create.label,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.pill),
        onTap: () => _createNoteForCurrentBucket(context, ref),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: expanded ? 56 : 52,
          width: expanded ? null : 52,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 20 : 0),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(AppRadii.pill),
          ),
          child: Row(
            mainAxisAlignment:
                expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              Icon(create.icon, size: 21, color: onFill),
              if (expanded) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    create.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: onFill,
                          fontWeight: FontWeight.w600,
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
          height: 50,
          padding: EdgeInsets.symmetric(horizontal: expanded ? 16 : 0),
          decoration: BoxDecoration(
            color: selected
                ? context.safernotesTheme.glassFill
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadii.pill),
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

class _MultiSelectionToolbar extends ConsumerStatefulWidget {
  const _MultiSelectionToolbar({
    super.key,
    this.compact = false,
    this.embeddedInNativeGlass = false,
  });

  final bool compact;
  final bool embeddedInNativeGlass;

  @override
  ConsumerState<_MultiSelectionToolbar> createState() =>
      _MultiSelectionToolbarState();
}

class _MultiSelectionToolbarState
    extends ConsumerState<_MultiSelectionToolbar> {
  var _busy = false;

  List<PlainNote> get _selectedNotes {
    final ids = ref.read(_selectedNoteIdsProvider);
    final notes = ref.read(notesControllerProvider).valueOrNull ?? const [];
    return notes.where((note) => ids.contains(note.localId)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final ids = ref.watch(_selectedNoteIdsProvider);
    final notes = ref.watch(notesControllerProvider).valueOrNull ?? const [];
    final selected = notes.where((note) => ids.contains(note.localId)).toList();
    final l10n = ref.watch(l10nProvider);
    final allPinned =
        selected.isNotEmpty && selected.every((note) => note.pinned);
    final buttonSize = widget.compact ? 48.0 : 36.0;
    final iconSize = widget.embeddedInNativeGlass
        ? AppSizes.iosCompactHeaderIcon
        : widget.compact
            ? 22.0
            : 18.0;
    Widget actionButton({
      required Key key,
      required String tooltip,
      required IconData icon,
      required String nativeSymbol,
      required VoidCallback? onPressed,
      bool selected = false,
    }) {
      if (widget.embeddedInNativeGlass && _usesIosNativeControls) {
        return Tooltip(
          message: tooltip,
          child: CNButton.icon(
            key: key,
            icon: CNSymbol(
              nativeSymbol,
              size: iconSize,
              mode: CNSymbolRenderingMode.monochrome,
            ),
            tint: Theme.of(context).colorScheme.onSurface,
            onPressed: onPressed,
            config: CNButtonConfig(
              width: buttonSize,
              minHeight: buttonSize,
              padding: const EdgeInsets.all(15),
              style: CNButtonStyle.plain,
              glassEffectInteractive: false,
            ),
          ),
        );
      }
      return AppIconButton(
        key: key,
        tooltip: tooltip,
        icon: icon,
        selected: selected,
        size: buttonSize,
        iconSize: iconSize,
        onPressed: onPressed,
      );
    }

    final actions = Row(
      key: const ValueKey('multi-selection-toolbar'),
      mainAxisSize: MainAxisSize.min,
      children: [
        actionButton(
          key: const ValueKey('clear-note-selection'),
          tooltip: l10n.t('clearSelection'),
          icon: AppIcons.x,
          nativeSymbol: 'xmark',
          onPressed: _busy ? null : _clearSelection,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text(
            l10n.t('selectedNotes', params: {'count': selected.length}),
            key: const ValueKey('selected-note-count'),
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        actionButton(
          key: const ValueKey('delete-selected-notes'),
          tooltip: l10n.t('deleteSelection'),
          icon: AppIcons.trash2,
          nativeSymbol: 'trash',
          onPressed: _busy || selected.isEmpty ? null : _deleteSelected,
        ),
        actionButton(
          key: const ValueKey('archive-selected-notes'),
          tooltip: l10n.t('archiveSelection'),
          icon: AppIcons.archive,
          nativeSymbol: 'archivebox',
          onPressed: _busy || selected.isEmpty ? null : _archiveSelected,
        ),
        actionButton(
          key: const ValueKey('background-selected-notes'),
          tooltip: l10n.t('backgroundSelection'),
          icon: AppIcons.palette,
          nativeSymbol: 'paintpalette',
          onPressed: _busy || selected.isEmpty ? null : _changeBackground,
        ),
        actionButton(
          key: const ValueKey('pin-selected-notes'),
          tooltip: l10n.t(allPinned ? 'unpin' : 'pin'),
          icon: allPinned ? AppIcons.heartFill : AppIcons.heart,
          nativeSymbol: allPinned ? 'heart.fill' : 'heart',
          selected: allPinned,
          onPressed:
              _busy || selected.isEmpty ? null : () => _setPinned(!allPinned),
        ),
      ],
    );

    if (!widget.compact) return actions;
    if (widget.embeddedInNativeGlass) {
      return Padding(
        key: const ValueKey('ios-native-selection-toolbar-content'),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        child: FittedBox(fit: BoxFit.scaleDown, child: actions),
      );
    }
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadii.pill),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 30,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              key: const ValueKey('mobile-selection-toolbar-glass'),
              borderRadius: BorderRadius.circular(AppRadii.pill),
              child: BackdropFilter(
                key: const ValueKey('mobile-selection-toolbar-backdrop'),
                filter: _NotesChromeGlass.filter(Theme.of(context).brightness),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppChromeGlass.tint(Theme.of(context).brightness),
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    border: Border.all(
                      color: AppChromeGlass.outerStroke(
                        Theme.of(context).brightness,
                      ),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 9,
                    ),
                    child: FittedBox(fit: BoxFit.scaleDown, child: actions),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _clearSelection() {
    ref.read(_selectedNoteIdsProvider.notifier).state = const {};
  }

  Future<void> _run(Future<void> Function(List<PlainNote>) action) async {
    if (_busy) return;
    final notes = _selectedNotes;
    if (notes.isEmpty) {
      _clearSelection();
      return;
    }
    setState(() => _busy = true);
    try {
      await action(notes);
      _clearSelection();
    } catch (error) {
      if (mounted) {
        showAppInfoBar(
          context,
          message: error.toString(),
          avoidMobileNavigation: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSelected() => _run((notes) async {
        final permanently = notes.every((note) => note.state == 'trashed');
        final nextState = permanently ? 'deleted' : 'trashed';
        final controller = ref.read(notesControllerProvider.notifier);
        for (final note in notes) {
          await controller.changeState(note, nextState);
        }
      });

  Future<void> _archiveSelected() => _run((notes) async {
        final controller = ref.read(notesControllerProvider.notifier);
        for (final note in notes) {
          await controller.changeState(note, 'archived');
        }
      });

  Future<void> _setPinned(bool pinned) => _run((notes) async {
        final controller = ref.read(notesControllerProvider.notifier);
        for (final note in notes) {
          if (note.pinned == pinned) continue;
          await controller.saveDraft(
            draft: note.copyWith(pinned: pinned),
            syncImmediately: true,
          );
        }
      });

  Future<void> _changeBackground() async {
    final notes = _selectedNotes;
    if (notes.isEmpty) return;
    final commonColor = notes.every(
      (note) =>
          normalizeBrandNoteColor(note.color) ==
          normalizeBrandNoteColor(notes.first.color),
    )
        ? normalizeBrandNoteColor(notes.first.color)
        : brandNoteColors.first;
    final color = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _MultiSelectionBackgroundSheet(
        selectedColor: commonColor,
      ),
    );
    if (color == null || !mounted) return;
    await _run((currentNotes) async {
      final controller = ref.read(notesControllerProvider.notifier);
      for (final note in currentNotes) {
        await controller.saveDraft(
          draft: note.copyWith(color: color),
          syncImmediately: true,
        );
      }
    });
  }
}

class _MultiSelectionBackgroundSheet extends StatelessWidget {
  const _MultiSelectionBackgroundSheet({required this.selectedColor});

  final int selectedColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n(Localizations.localeOf(context).languageCode);
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(12),
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
                    Icon(AppIcons.palette, color: scheme.onSurface),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        l10n.t('background'),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final color in brandNoteColors)
                      InkWell(
                        key: ValueKey('selection-background-$color'),
                        borderRadius: BorderRadius.circular(AppRadii.xl),
                        onTap: () => Navigator.of(context).pop(color),
                        child: Container(
                          width: 64,
                          height: 56,
                          decoration: BoxDecoration(
                            color: brandNoteSurfaceColor(context, color),
                            gradient: brandNoteGradient(context, color),
                            borderRadius: BorderRadius.circular(AppRadii.xl),
                            border: color == selectedColor
                                ? Border.all(color: scheme.primary, width: 2)
                                : null,
                          ),
                          child: color == selectedColor
                              ? Icon(AppIcons.check,
                                  size: 18, color: scheme.onSurface)
                              : null,
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
}

class _MobileBottomNav extends ConsumerStatefulWidget {
  const _MobileBottomNav({super.key});

  @override
  ConsumerState<_MobileBottomNav> createState() => _MobileBottomNavState();
}

class _MobileBottomNavState extends ConsumerState<_MobileBottomNav>
    with TickerProviderStateMixin {
  /// Concentric geometry: outer radius == item radius + inset, so every
  /// corner in the bar reads as part of one shape.
  static const double _itemSize = 50;
  static const double _gap = 7;
  static const double _inset = 6;
  static const double _barRadius = _itemSize / 2 + _inset;
  static const double _iosItemSize = 54;
  static const double _iosNativeBarHeight = 64;
  static const double _iosCreateButtonSize = 48;
  static const double _iosNavIconSize = 14;
  static const double _iosIndicatorRestSize = _iosItemSize;
  static const double _iosIndicatorGrowSize = 16;
  static const double _iosNavContentWidth = _iosItemSize * 5 + _iosGap * 4;
  static const double _iosBarHorizontalInset = 5.5;
  static const double _iosTabBarInset = 5;
  static const double _iosTabBarWidth = _iosItemSize * 4 + _iosTabBarInset * 2;
  static const double _iosDockWidth =
      _iosNavContentWidth + _iosBarHorizontalInset * 2;
  static const double _iosSearchHeight = _iosNativeBarHeight;
  static const double _iosExpandedBarHeight = 141;
  static const double _iosGap = 7;
  static const double _trashDropSize = 88;
  static const double _createMenuContentHeight = 76;
  static const double _createMenuSpacing = 7;
  static const double _createMenuInset = 8;
  static const double _expandedDrawerTopRadius = 32;
  static const double _createActionRadius =
      _expandedDrawerTopRadius - _createMenuInset;
  static const Color _lightSelectionOverlay = Color(0x12000000);
  static const Color _darkSelectionOverlay = Color(0x24ffffff);
  static const Duration _createDuration = Duration(milliseconds: 230);
  static const Duration _createReverseDuration = Duration(milliseconds: 180);
  static const Duration _iosCreateDuration = Duration(milliseconds: 320);
  static const Duration _iosCreateReverseDuration = Duration(milliseconds: 250);
  static const Duration _modeDuration = Duration(milliseconds: 320);
  static const Duration _indicatorLiftDuration = Duration(milliseconds: 150);
  static const Duration _indicatorLandDuration = Duration(milliseconds: 260);
  static const Duration _trashDuration = Duration(milliseconds: 400);
  static const Duration _trashReverseDuration = Duration(milliseconds: 320);

  var _expanded = false;
  var _searching = false;
  var _reduceMotion = false;
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  late final AnimationController _createMenuController;
  late final AnimationController _trashMorphController;
  late final AnimationController _indicatorPositionController;
  late final AnimationController _indicatorLiftController;
  PlainNote? _morphingDraggedNote;

  /// The indicator travels on the same spring model as the reference liquid
  /// glass tab bar, while a separate lift envelope grows it for the journey.
  double _indicatorFrom = 0;
  int _indicatorTarget = 0;
  int _indicatorAnimationGeneration = 0;

  @override
  void initState() {
    super.initState();
    _indicatorTarget = _slotForBucket(ref.read(noteBucketProvider));
    _indicatorFrom = _indicatorTarget.toDouble();
    _indicatorPositionController = AnimationController.unbounded(
      vsync: this,
      value: _indicatorFrom,
    );
    _indicatorLiftController = AnimationController(
      vsync: this,
      duration: _indicatorLiftDuration,
      reverseDuration: _indicatorLandDuration,
    );
    _createMenuController = AnimationController(
      vsync: this,
      duration: _usesIosNativeControls ? _iosCreateDuration : _createDuration,
      reverseDuration: _usesIosNativeControls
          ? _iosCreateReverseDuration
          : _createReverseDuration,
    );
    final draggedNote = ref.read(_draggedNoteProvider);
    _morphingDraggedNote = draggedNote;
    _trashMorphController = AnimationController(
      vsync: this,
      duration: _trashDuration,
      reverseDuration: _trashReverseDuration,
      value: draggedNote != null && draggedNote.state != 'trashed' ? 1 : 0,
    );
    ref.listenManual<PlainNote?>(_draggedNoteProvider, (previous, next) {
      final draggingToTrash = next != null && next.state != 'trashed';
      if (draggingToTrash) {
        if (_expanded) {
          _expanded = false;
          _createMenuController.reverse();
        }
        _morphingDraggedNote = next;
        _trashMorphController.forward();
      } else {
        unawaited(_reverseTrashMorph());
      }
    });
    ref.listenManual<String>(noteBucketProvider, (previous, next) {
      unawaited(_animateIndicatorTo(_slotForBucket(next)));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    _createMenuController.duration = reduceMotion
        ? Duration.zero
        : _usesIosNativeControls
            ? _iosCreateDuration
            : _createDuration;
    _createMenuController.reverseDuration = reduceMotion
        ? Duration.zero
        : _usesIosNativeControls
            ? _iosCreateReverseDuration
            : _createReverseDuration;
    _trashMorphController.duration =
        reduceMotion ? Duration.zero : _trashDuration;
    _trashMorphController.reverseDuration =
        reduceMotion ? Duration.zero : _trashReverseDuration;
    _indicatorLiftController.duration =
        reduceMotion ? Duration.zero : _indicatorLiftDuration;
    _indicatorLiftController.reverseDuration =
        reduceMotion ? Duration.zero : _indicatorLandDuration;
    if (reduceMotion) {
      _indicatorAnimationGeneration++;
      _indicatorPositionController.stop();
      _indicatorPositionController.value = _indicatorTarget.toDouble();
      _indicatorLiftController.value = 0;
      _createMenuController.value = _expanded ? 1 : 0;
      final draggedNote = ref.read(_draggedNoteProvider);
      _trashMorphController.value =
          draggedNote != null && draggedNote.state != 'trashed' ? 1 : 0;
    }
  }

  Future<void> _reverseTrashMorph() async {
    await _trashMorphController.reverse();
    if (!mounted) return;
    final draggedNote = ref.read(_draggedNoteProvider);
    if (draggedNote != null && draggedNote.state != 'trashed') return;
    setState(() => _morphingDraggedNote = null);
  }

  static int _slotForBucket(String bucket) => switch (bucket) {
        'reminders' => 1,
        'trashed' => 2,
        _ => 0,
      };

  Future<void> _animateIndicatorTo(int next) async {
    if (next == _indicatorTarget) return;

    final generation = ++_indicatorAnimationGeneration;
    final from = _indicatorPositionController.value;
    setState(() {
      _indicatorFrom = from;
      _indicatorTarget = next;
    });

    if (_reduceMotion) {
      _indicatorPositionController.stop();
      _indicatorPositionController.value = next.toDouble();
      _indicatorLiftController.value = 0;
      return;
    }

    unawaited(
      _indicatorLiftController.animateTo(
        1,
        duration: _indicatorLiftDuration,
        curve: Curves.easeOutBack,
      ),
    );

    try {
      await _indicatorPositionController
          .animateWith(
            SpringSimulation(
              const SpringDescription(
                mass: 1,
                stiffness: 280,
                damping: 31.4,
              ),
              from,
              next.toDouble(),
              _indicatorPositionController.velocity,
            ),
          )
          .orCancel;
    } on TickerCanceled {
      return;
    }

    if (!mounted || generation != _indicatorAnimationGeneration) return;
    _indicatorPositionController.value = next.toDouble();
    await _indicatorLiftController.animateBack(
      0,
      duration: _indicatorLandDuration,
      curve: Curves.easeOutCubic,
    );
  }

  void _selectBucket(String bucket) {
    final next = _slotForBucket(bucket);
    unawaited(_animateIndicatorTo(next));
    _collapse();
    _closeSearch();
    ref.read(noteBucketProvider.notifier).state = bucket;
  }

  void _toggleCreate() {
    _setCreateMenuExpanded(!_expanded);
  }

  void _collapse() {
    _setCreateMenuExpanded(false);
  }

  void _setCreateMenuExpanded(bool expanded) {
    if (_expanded == expanded) return;
    setState(() => _expanded = expanded);
    if (expanded) {
      _createMenuController.forward();
    } else {
      _createMenuController.reverse();
    }
  }

  void _openSearch() {
    if (_searching) return;
    setState(() {
      _expanded = false;
      _searching = true;
    });
    _createMenuController.reverse();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    if (!_searching && _searchController.text.isEmpty) return;
    _searchFocusNode.unfocus();
    _searchController.clear();
    ref.read(noteSearchProvider.notifier).state = '';
    if (_searching) setState(() => _searching = false);
  }

  @override
  void dispose() {
    _indicatorPositionController.dispose();
    _indicatorLiftController.dispose();
    _createMenuController.dispose();
    _trashMorphController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _runCreateAction(_MobileCreateAction action) async {
    if (_expanded) setState(() => _expanded = false);
    await _createMenuController.reverse();
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
    final draggedNote = ref.watch(_draggedNoteProvider);
    final selectionActive = ref.watch(_selectedNoteIdsProvider).isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final draggingToTrash =
        draggedNote != null && draggedNote.state != 'trashed';
    final targetRadius = _barRadius;
    final navItemSize = _usesIosNativeControls ? _iosItemSize : _itemSize;
    final navGap = _usesIosNativeControls ? _iosGap : _gap;
    final availableMobileWidth =
        math.max(0.0, MediaQuery.sizeOf(context).width - 32);
    final compactNavWidth = navItemSize * 5 + navGap * 4 + _inset * 2;
    final iosNavWidth = math.min(_iosDockWidth, availableMobileWidth);
    final searchNavWidth = math.min(420.0, availableMobileWidth);
    final collapsedNavSurfaceHeight =
        _usesIosNativeControls ? _iosNativeBarHeight : _itemSize + _inset * 2;
    final expandedNavSurfaceHeight = _usesIosNativeControls
        ? _iosExpandedBarHeight
        : collapsedNavSurfaceHeight +
            _createMenuSpacing +
            _createMenuContentHeight;
    final popoutHeight = _usesIosNativeControls
        ? draggingToTrash
            ? _trashDropSize
            : _expanded && !selectionActive && !_searching
                ? expandedNavSurfaceHeight
                : selectionActive
                    ? _iosNativeBarHeight
                    : _searching
                        ? _iosSearchHeight
                        : _iosNativeBarHeight
        : draggingToTrash
            ? _trashDropSize
            : expandedNavSurfaceHeight;
    final createTransitionActive = _expanded || _createMenuController.value > 0;
    final createDuration =
        _usesIosNativeControls ? _iosCreateDuration : _createDuration;
    final createReverseDuration = _usesIosNativeControls
        ? _iosCreateReverseDuration
        : _createReverseDuration;
    final geometryDuration = draggingToTrash
        ? _trashDuration
        : createTransitionActive
            ? _expanded
                ? createDuration
                : createReverseDuration
            : _modeDuration;
    return AnimatedBuilder(
      animation: _trashMorphController,
      builder: (context, _) {
        final trashMorph = Curves.easeInOutCubic.transform(
          _trashMorphController.value,
        );
        final collapsedViewportHeight =
            _usesIosNativeControls ? _iosNativeBarHeight : _itemSize;
        final navViewportHeight = lerpDouble(
          collapsedViewportHeight,
          _trashDropSize - _inset * 2,
          trashMorph,
        )!;
        return SafeArea(
          top: false,
          minimum: const EdgeInsets.fromLTRB(16, 0, 16, 14),
          child: Transform.translate(
            key: const ValueKey('mobile-nav-trash-lift'),
            offset: Offset(0, -12 * trashMorph),
            child: Center(
              heightFactor: 1,
              child: AnimatedContainer(
                duration: AppMotion.duration(context, geometryDuration),
                curve: Curves.easeOutCubic,
                height: popoutHeight,
                width: draggingToTrash
                    ? _trashDropSize
                    : selectionActive && _usesIosNativeControls
                        ? searchNavWidth
                        : _searching
                            ? searchNavWidth
                            : _usesIosNativeControls
                                ? iosNavWidth
                                : compactNavWidth,
                child: KeyedSubtree(
                  key: const ValueKey('mobile-create-popout-layout'),
                  child: RepaintBoundary(
                    child: _usesIosNativeControls
                        ? _IosLiquidBottomBar(
                            bucket: bucket,
                            expanded: _expanded && !selectionActive,
                            searching: _searching && !selectionActive,
                            selectionActive: selectionActive,
                            foreground: scheme.onSurface,
                            indicatorFrom: _indicatorFrom,
                            indicatorTarget: _indicatorTarget,
                            indicatorPosition: _indicatorPositionController,
                            indicatorLift: _indicatorLiftController,
                            createAnimation: _createMenuController,
                            draggedNote: draggedNote ?? _morphingDraggedNote,
                            trashMorphProgress: trashMorph,
                            searchController: _searchController,
                            searchFocusNode: _searchFocusNode,
                            searchHint: l10n.t('searchNotes'),
                            noteLabel: l10n.t('newNote'),
                            reminderLabel: l10n.t('reminder'),
                            listLabel: l10n.t('newChecklist'),
                            onNotes: () => _selectBucket('active'),
                            onReminders: () => _selectBucket('reminders'),
                            onTrash: () => _selectBucket('trashed'),
                            onSearch: _openSearch,
                            onSearchChanged: (value) => ref
                                .read(noteSearchProvider.notifier)
                                .state = value,
                            onSearchClose: _closeSearch,
                            onCreate: _toggleCreate,
                            onCreateNote: () => unawaited(
                              _runCreateAction(_MobileCreateAction.note),
                            ),
                            onCreateReminder: () => unawaited(
                              _runCreateAction(_MobileCreateAction.reminder),
                            ),
                            onCreateList: () => unawaited(
                              _runCreateAction(_MobileCreateAction.list),
                            ),
                          )
                        : Stack(
                            clipBehavior: Clip.none,
                            children: [
                              if (!_usesIosNativeControls ||
                                  _expanded ||
                                  draggingToTrash ||
                                  trashMorph > 0)
                                _MobileNavDrawerSurface(
                                  animation: _createMenuController,
                                  morphProgress: trashMorph,
                                  collapsedHeight: collapsedNavSurfaceHeight,
                                  expandedHeight: expandedNavSurfaceHeight,
                                  trashHeight: _trashDropSize,
                                  collapsedRadius: targetRadius,
                                  trashRadius: _trashDropSize / 2,
                                ),
                              if (!draggingToTrash)
                                Positioned(
                                  top: 0,
                                  left: _createMenuInset,
                                  right: _createMenuInset,
                                  height: _createMenuContentHeight,
                                  child: ClipRect(
                                    key: const ValueKey(
                                      'mobile-create-actions-clip',
                                    ),
                                    child: IgnorePointer(
                                      ignoring: !_expanded,
                                      child: _usesIosNativeControls
                                          ? _IosNativeCreateActions(
                                              animation: _createMenuController,
                                              noteLabel: l10n.t('newNote'),
                                              reminderLabel: l10n.t('reminder'),
                                              listLabel: l10n.t('newChecklist'),
                                              onNote: () => unawaited(
                                                _runCreateAction(
                                                    _MobileCreateAction.note),
                                              ),
                                              onReminder: () => unawaited(
                                                _runCreateAction(
                                                  _MobileCreateAction.reminder,
                                                ),
                                              ),
                                              onList: () => unawaited(
                                                _runCreateAction(
                                                    _MobileCreateAction.list),
                                              ),
                                            )
                                          : Padding(
                                              padding: const EdgeInsets.only(
                                                top: _createMenuInset,
                                              ),
                                              child: _CreateActionsReveal(
                                                animation:
                                                    _createMenuController,
                                                children: [
                                                  _MobileCreateDrawerAction(
                                                    key: const ValueKey(
                                                      'mobile-create-note-action',
                                                    ),
                                                    icon: AppIcons.filePlus2,
                                                    label: l10n.t('newNote'),
                                                    semanticLabel:
                                                        l10n.t('newNote'),
                                                    onTap: () => unawaited(
                                                      _runCreateAction(
                                                        _MobileCreateAction
                                                            .note,
                                                      ),
                                                    ),
                                                  ),
                                                  _MobileCreateDrawerAction(
                                                    key: const ValueKey(
                                                      'mobile-create-reminder-action',
                                                    ),
                                                    icon: AppIcons.bellPlus,
                                                    label: l10n.t('reminder'),
                                                    semanticLabel:
                                                        l10n.t('setReminder'),
                                                    onTap: () => unawaited(
                                                      _runCreateAction(
                                                        _MobileCreateAction
                                                            .reminder,
                                                      ),
                                                    ),
                                                  ),
                                                  _MobileCreateDrawerAction(
                                                    key: const ValueKey(
                                                      'mobile-create-list-action',
                                                    ),
                                                    icon: AppIcons.listChecks,
                                                    label:
                                                        l10n.t('newChecklist'),
                                                    semanticLabel:
                                                        l10n.t('newChecklist'),
                                                    onTap: () => unawaited(
                                                      _runCreateAction(
                                                        _MobileCreateAction
                                                            .list,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 0,
                                child: _MobileNavGlassSurface(
                                  child: SizedBox(
                                    key: const ValueKey(
                                      'mobile-nav-morphing-viewport',
                                    ),
                                    height: navViewportHeight,
                                    child: AnimatedSwitcher(
                                      duration: AppMotion.duration(
                                        context,
                                        const Duration(milliseconds: 220),
                                      ),
                                      reverseDuration: AppMotion.duration(
                                        context,
                                        const Duration(milliseconds: 240),
                                      ),
                                      switchInCurve: Curves.easeOutCubic,
                                      switchOutCurve: Curves.easeInCubic,
                                      transitionBuilder: (child, animation) =>
                                          FadeTransition(
                                        opacity: animation,
                                        child: ScaleTransition(
                                          scale:
                                              Tween<double>(begin: 0.96, end: 1)
                                                  .animate(animation),
                                          child: child,
                                        ),
                                      ),
                                      child: _searching && !draggingToTrash
                                          ? KeyedSubtree(
                                              key: const ValueKey(
                                                'mobile-nav-search-mode',
                                              ),
                                              child: _MobileNavSearchField(
                                                controller: _searchController,
                                                focusNode: _searchFocusNode,
                                                hintText: l10n.t('searchNotes'),
                                                onChanged: (value) => ref
                                                    .read(noteSearchProvider
                                                        .notifier)
                                                    .state = value,
                                                onClose: _closeSearch,
                                              ),
                                            )
                                          : KeyedSubtree(
                                              key: const ValueKey(
                                                'mobile-nav-icons-mode',
                                              ),
                                              child: _usesIosNativeControls &&
                                                      !draggingToTrash &&
                                                      trashMorph == 0
                                                  ? _expanded
                                                      ? _IosNativeNavButtonGroup(
                                                          bucket: bucket,
                                                          expanded: _expanded,
                                                          foreground:
                                                              scheme.onSurface,
                                                          indicatorFrom:
                                                              _indicatorFrom,
                                                          indicatorTarget:
                                                              _indicatorTarget,
                                                          indicatorPosition:
                                                              _indicatorPositionController,
                                                          indicatorLift:
                                                              _indicatorLiftController,
                                                          onNotes: () =>
                                                              _selectBucket(
                                                                  'active'),
                                                          onReminders: () =>
                                                              _selectBucket(
                                                                  'reminders'),
                                                          onTrash: () =>
                                                              _selectBucket(
                                                                  'trashed'),
                                                          onSearch: _openSearch,
                                                          onCreate:
                                                              _toggleCreate,
                                                        )
                                                      : _IosNativeTabBar(
                                                          bucket: bucket,
                                                          foreground:
                                                              scheme.onSurface,
                                                          indicatorFrom:
                                                              _indicatorFrom,
                                                          indicatorTarget:
                                                              _indicatorTarget,
                                                          onNotes: () =>
                                                              _selectBucket(
                                                                  'active'),
                                                          onReminders: () =>
                                                              _selectBucket(
                                                                  'reminders'),
                                                          onTrash: () =>
                                                              _selectBucket(
                                                                  'trashed'),
                                                          onSearch: _openSearch,
                                                          onCreate:
                                                              _toggleCreate,
                                                        )
                                                  : _MobileNavMorphingIconGroup(
                                                      bucket: bucket,
                                                      draggedNote: draggedNote ??
                                                          _morphingDraggedNote,
                                                      morphProgress: trashMorph,
                                                      dark: dark,
                                                      indicatorFrom:
                                                          _indicatorFrom,
                                                      indicatorTarget:
                                                          _indicatorTarget,
                                                      notesTooltip:
                                                          l10n.t('notes'),
                                                      remindersTooltip:
                                                          l10n.t('reminders'),
                                                      trashTooltip:
                                                          l10n.t('trash'),
                                                      searchTooltip:
                                                          l10n.t('searchNotes'),
                                                      createExpanded: _expanded,
                                                      onNotes: () =>
                                                          _selectBucket(
                                                              'active'),
                                                      onReminders: () =>
                                                          _selectBucket(
                                                              'reminders'),
                                                      onTrash: () =>
                                                          _selectBucket(
                                                              'trashed'),
                                                      onSearch: _openSearch,
                                                      onCreate: _toggleCreate,
                                                    ),
                                            ),
                                    ),
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
        );
      },
    );
  }
}

/// A single, persistent native glass host for every iOS bottom-bar state.
///
/// Keeping this platform view mounted is important: replacing the dock with
/// unrelated glass widgets makes SwiftUI restart its optical sampling and the
/// transition reads as a cross-fade. Here the same glass sheet changes bounds
/// while the navigation, create drawer, search, drop target, and selection
/// controls move inside it.
class _IosLiquidBottomBar extends StatelessWidget {
  const _IosLiquidBottomBar({
    required this.bucket,
    required this.expanded,
    required this.searching,
    required this.selectionActive,
    required this.foreground,
    required this.indicatorFrom,
    required this.indicatorTarget,
    required this.indicatorPosition,
    required this.indicatorLift,
    required this.createAnimation,
    required this.draggedNote,
    required this.trashMorphProgress,
    required this.searchController,
    required this.searchFocusNode,
    required this.searchHint,
    required this.noteLabel,
    required this.reminderLabel,
    required this.listLabel,
    required this.onNotes,
    required this.onReminders,
    required this.onTrash,
    required this.onSearch,
    required this.onSearchChanged,
    required this.onSearchClose,
    required this.onCreate,
    required this.onCreateNote,
    required this.onCreateReminder,
    required this.onCreateList,
  });

  final String bucket;
  final bool expanded;
  final bool searching;
  final bool selectionActive;
  final Color foreground;
  final double indicatorFrom;
  final int indicatorTarget;
  final AnimationController indicatorPosition;
  final AnimationController indicatorLift;
  final Animation<double> createAnimation;
  final PlainNote? draggedNote;
  final double trashMorphProgress;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final String searchHint;
  final String noteLabel;
  final String reminderLabel;
  final String listLabel;
  final VoidCallback onNotes;
  final VoidCallback onReminders;
  final VoidCallback onTrash;
  final VoidCallback onSearch;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchClose;
  final VoidCallback onCreate;
  final VoidCallback onCreateNote;
  final VoidCallback onCreateReminder;
  final VoidCallback onCreateList;

  static const _contentDuration = Duration(milliseconds: 320);

  @override
  Widget build(BuildContext context) {
    final trashVisible = draggedNote != null || trashMorphProgress > 0;
    final normalVisible =
        !searching && !selectionActive && trashMorphProgress < 0.01;
    final shellRadius = trashVisible
        ? _MobileBottomNavState._trashDropSize / 2
        : searching
            ? _MobileBottomNavState._iosSearchHeight / 2
            : _MobileBottomNavState._barRadius;
    final content = SizedBox.expand(
      key: const ValueKey('ios-native-bottom-navigation'),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 0,
            left: _MobileBottomNavState._createMenuInset,
            right: _MobileBottomNavState._createMenuInset,
            height: _MobileBottomNavState._createMenuContentHeight,
            child: IgnorePointer(
              ignoring: !expanded,
              child: _IosNativeCreateActions(
                animation: createAnimation,
                noteLabel: noteLabel,
                reminderLabel: reminderLabel,
                listLabel: listLabel,
                onNote: onCreateNote,
                onReminder: onCreateReminder,
                onList: onCreateList,
              ),
            ),
          ),
          Positioned(
            right: _MobileBottomNavState._iosBarHorizontalInset,
            bottom: 5,
            width: _MobileBottomNavState._iosNavContentWidth,
            height: _MobileBottomNavState._iosItemSize,
            child: IgnorePointer(
              ignoring: !normalVisible,
              child: AnimatedOpacity(
                key: const ValueKey('ios-native-nav-content-opacity'),
                opacity: normalVisible ? 1 : 0,
                duration: AppMotion.duration(context, _contentDuration),
                curve: Curves.easeOutCubic,
                child: AnimatedScale(
                  scale: normalVisible ? 1 : 0.88,
                  duration: AppMotion.duration(context, _contentDuration),
                  curve: Curves.easeOutCubic,
                  child: Center(
                    child: _IosNativeNavButtonGroup(
                      bucket: bucket,
                      expanded: expanded,
                      foreground: foreground,
                      indicatorFrom: indicatorFrom,
                      indicatorTarget: indicatorTarget,
                      indicatorPosition: indicatorPosition,
                      indicatorLift: indicatorLift,
                      onNotes: onNotes,
                      onReminders: onReminders,
                      onTrash: onTrash,
                      onSearch: onSearch,
                      onCreate: onCreate,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: _MobileBottomNavState._iosSearchHeight,
            child: IgnorePointer(
              ignoring: !searching,
              child: AnimatedOpacity(
                key: const ValueKey('ios-native-search-content-opacity'),
                opacity: searching ? 1 : 0,
                duration: AppMotion.duration(context, _contentDuration),
                curve: Curves.easeOutCubic,
                child: AnimatedSlide(
                  offset: searching ? Offset.zero : const Offset(0.08, 0),
                  duration: AppMotion.duration(context, _contentDuration),
                  curve: Curves.easeOutCubic,
                  child: _MobileNavSearchField(
                    controller: searchController,
                    focusNode: searchFocusNode,
                    hintText: searchHint,
                    onChanged: onSearchChanged,
                    onClose: onSearchClose,
                    useNativeSurface: false,
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !selectionActive,
              child: AnimatedOpacity(
                key: const ValueKey('ios-native-selection-content-opacity'),
                opacity: selectionActive ? 1 : 0,
                duration: AppMotion.duration(context, _contentDuration),
                curve: Curves.easeOutCubic,
                child: AnimatedScale(
                  scale: selectionActive ? 1 : 0.90,
                  duration: AppMotion.duration(context, _contentDuration),
                  curve: Curves.easeOutCubic,
                  child: const Center(
                    child: _MultiSelectionToolbar(
                      compact: true,
                      embeddedInNativeGlass: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (trashVisible)
            Positioned.fill(
              child: Center(
                child: AnimatedOpacity(
                  key: const ValueKey('ios-native-trash-content-opacity'),
                  opacity: trashMorphProgress.clamp(0.0, 1.0),
                  duration: Duration.zero,
                  child: draggedNote == null
                      ? const SizedBox.shrink()
                      : _MobileNavTrashDropButton(
                          key: const ValueKey(
                            'mobile-nav-trash-drop-target',
                          ),
                          note: draggedNote!,
                          morphProgress: trashMorphProgress,
                        ),
                ),
              ),
            ),
        ],
      ),
    );
    return Stack(
      clipBehavior: Clip.none,
      fit: StackFit.expand,
      children: [
        LiquidGlassContainer(
          key: const ValueKey('ios-native-bottom-bar-glass'),
          config: LiquidGlassConfig(
            effect: CNGlassEffect.regular,
            shape: CNGlassEffectShape.rect,
            cornerRadius: shellRadius,
            interactive: false,
          ),
          child: const SizedBox.expand(),
        ),
        content,
      ],
    );
  }
}

class _MobileNavMorphingIconGroup extends StatelessWidget {
  const _MobileNavMorphingIconGroup({
    required this.bucket,
    required this.draggedNote,
    required this.morphProgress,
    required this.dark,
    required this.indicatorFrom,
    required this.indicatorTarget,
    required this.notesTooltip,
    required this.remindersTooltip,
    required this.trashTooltip,
    required this.searchTooltip,
    required this.createExpanded,
    required this.onNotes,
    required this.onReminders,
    required this.onTrash,
    required this.onSearch,
    required this.onCreate,
  });

  final String bucket;
  final PlainNote? draggedNote;
  final double morphProgress;
  final bool dark;
  final double indicatorFrom;
  final int indicatorTarget;
  final String notesTooltip;
  final String remindersTooltip;
  final String trashTooltip;
  final String searchTooltip;
  final bool createExpanded;
  final VoidCallback onNotes;
  final VoidCallback onReminders;
  final VoidCallback onTrash;
  final VoidCallback onSearch;
  final VoidCallback onCreate;

  static const _slots = [-2.0, -1.0, 0.0, 1.0, 2.0];

  @override
  Widget build(BuildContext context) {
    final width =
        _MobileBottomNavState._itemSize * 5 + _MobileBottomNavState._gap * 4;
    final morph = morphProgress.clamp(0.0, 1.0);
    final sideMorph = Curves.easeOutCubic.transform(
      (morph / 0.55).clamp(0.0, 1.0),
    );
    final sideFade = Curves.easeOutCubic.transform(
      (morph / 0.20).clamp(0.0, 1.0),
    );
    final sideIconOpacity = 1 - sideFade;
    final backedMorph = Curves.easeInOutCubic.transform(
      (morph / 0.58).clamp(0.0, 1.0),
    );
    final backedFade = Curves.easeOutCubic.transform(
      (morph / 0.24).clamp(0.0, 1.0),
    );
    final backedOpacity = 1 - backedFade;
    final sideIconScale = 1 - sideMorph * 0.12;
    final backedIconScale = 1 - backedMorph * 0.5;
    final notesBacked = indicatorTarget == 0;
    final remindersBacked = indicatorTarget == 1;
    return OverflowBox(
      alignment: Alignment.center,
      minWidth: width,
      maxWidth: width,
      child: SizedBox(
        width: width,
        height: _MobileBottomNavState._itemSize,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            _NavSelectionIndicator(
              dark: dark,
              indicatorFrom: indicatorFrom,
              indicatorTarget: indicatorTarget,
              groupWidth: width,
              morphProgress: backedMorph,
              opacity: backedOpacity,
            ),
            _MorphingNavSlot(
              key: const ValueKey('mobile-nav-notes-morph-slot'),
              slot: _slots[0],
              morph: notesBacked ? backedMorph : sideMorph,
              opacity: notesBacked ? backedOpacity : sideIconOpacity,
              scale: notesBacked ? backedIconScale : sideIconScale,
              scaleKey: const ValueKey('mobile-nav-notes-morph-scale'),
              child: _MobileNavIcon(
                key: const ValueKey('mobile-nav-notes'),
                icon: AppIcons.notebookText,
                tooltip: notesTooltip,
                size: _MobileBottomNavState._itemSize,
                selected: bucket == 'active' || bucket == 'archived',
                onPressed: onNotes,
              ),
            ),
            _MorphingNavSlot(
              key: const ValueKey('mobile-nav-reminders-morph-slot'),
              slot: _slots[1],
              morph: remindersBacked ? backedMorph : sideMorph,
              opacity: remindersBacked ? backedOpacity : sideIconOpacity,
              scale: remindersBacked ? backedIconScale : sideIconScale,
              scaleKey: const ValueKey('mobile-nav-reminders-morph-scale'),
              child: _MobileNavIcon(
                key: const ValueKey('mobile-nav-reminders'),
                icon: AppIcons.bell,
                tooltip: remindersTooltip,
                size: _MobileBottomNavState._itemSize,
                selected: bucket == 'reminders',
                onPressed: onReminders,
              ),
            ),
            _MorphingNavSlot(
              key: const ValueKey('mobile-nav-search-morph-slot'),
              slot: _slots[3],
              morph: sideMorph,
              opacity: sideIconOpacity,
              scale: sideIconScale,
              scaleKey: const ValueKey('mobile-nav-search-morph-scale'),
              child: _MobileNavIcon(
                key: const ValueKey('mobile-nav-search'),
                icon: AppIcons.search,
                tooltip: searchTooltip,
                size: _MobileBottomNavState._itemSize,
                selected: false,
                onPressed: onSearch,
              ),
            ),
            _MorphingNavSlot(
              key: const ValueKey('mobile-nav-create-morph-slot'),
              slot: _slots[4],
              morph: backedMorph,
              opacity: backedOpacity,
              scale: backedIconScale,
              scaleKey: const ValueKey('mobile-nav-create-morph-scale'),
              child: _MobileCreateToggleButton(
                expanded: createExpanded,
                dark: dark,
                size: _MobileBottomNavState._itemSize,
                onPressed: onCreate,
              ),
            ),
            _MorphingNavSlot(
              key: const ValueKey('mobile-nav-trash-morph-slot'),
              slot: _slots[2],
              morph: morph,
              child: draggedNote == null
                  ? _MobileNavIcon(
                      key: const ValueKey('mobile-nav-trash'),
                      icon: AppIcons.trash2,
                      tooltip: trashTooltip,
                      size: _MobileBottomNavState._itemSize,
                      selected: bucket == 'trashed',
                      onPressed: onTrash,
                    )
                  : _MobileNavTrashDropButton(
                      key: const ValueKey('mobile-nav-trash-drop-target'),
                      note: draggedNote!,
                      morphProgress: morph,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MorphingNavSlot extends StatelessWidget {
  const _MorphingNavSlot({
    super.key,
    required this.slot,
    required this.morph,
    required this.child,
    this.opacity = 1,
    this.scale = 1,
    this.scaleKey,
  });

  final double slot;
  final double morph;
  final Widget child;
  final double opacity;
  final double scale;
  final Key? scaleKey;

  @override
  Widget build(BuildContext context) {
    final slotExtent =
        _MobileBottomNavState._itemSize + _MobileBottomNavState._gap;
    final x = slot * slotExtent * (1 - morph);
    final y = 10 * morph * slot.abs();
    final easedOpacity = opacity.clamp(0.0, 1.0);
    return Transform.translate(
      offset: Offset(x, y),
      child: IgnorePointer(
        ignoring: easedOpacity < 0.01,
        child: Opacity(
          opacity: easedOpacity,
          child: Transform.scale(
            key: scaleKey,
            scale: scale,
            child: RepaintBoundary(child: child),
          ),
        ),
      ),
    );
  }
}

class _NavSelectionIndicator extends StatelessWidget {
  const _NavSelectionIndicator({
    required this.dark,
    required this.indicatorFrom,
    required this.indicatorTarget,
    required this.groupWidth,
    required this.morphProgress,
    required this.opacity,
  });

  final bool dark;
  final double indicatorFrom;
  final int indicatorTarget;
  final double groupWidth;
  final double morphProgress;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(end: indicatorTarget.toDouble()),
      duration: AppMotion.duration(
        context,
        const Duration(milliseconds: 480),
      ),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final span = (indicatorTarget - indicatorFrom).abs();
        final progress = span == 0
            ? 1.0
            : ((value - indicatorFrom).abs() / span).clamp(0.0, 1.0);
        final bell = math.sin(math.pi * progress);
        final stretch = 1 + bell * 0.42;
        final squash = 1 - bell * 0.13;
        final morph = morphProgress.clamp(0.0, 1.0);
        final morphScale = 1 - morph * 0.5;
        final width = _MobileBottomNavState._itemSize * stretch * morphScale;
        final height = _MobileBottomNavState._itemSize * squash * morphScale;
        final slotExtent =
            _MobileBottomNavState._itemSize + _MobileBottomNavState._gap;
        final slotCenter =
            value * slotExtent + _MobileBottomNavState._itemSize / 2;
        final centerX = lerpDouble(slotCenter, groupWidth / 2, morph)!;
        final distanceFromCenter = (value - 2).abs();
        final centerY = _MobileBottomNavState._itemSize / 2 +
            10 * morph * distanceFromCenter;
        return Positioned(
          left: 0,
          top: 0,
          width: _MobileBottomNavState._itemSize,
          height: _MobileBottomNavState._itemSize,
          child: Transform.translate(
            key: const ValueKey('mobile-nav-selection-morph'),
            offset: Offset(
              centerX - _MobileBottomNavState._itemSize / 2,
              centerY - _MobileBottomNavState._itemSize / 2,
            ),
            child: Transform.scale(
              scaleX: width / _MobileBottomNavState._itemSize,
              scaleY: height / _MobileBottomNavState._itemSize,
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: RepaintBoundary(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: dark
                          ? _MobileBottomNavState._darkSelectionOverlay
                          : _MobileBottomNavState._lightSelectionOverlay,
                      borderRadius: BorderRadius.circular(
                        _MobileBottomNavState._itemSize / 2,
                      ),
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

class _IosNativeTabBar extends StatelessWidget {
  const _IosNativeTabBar({
    required this.bucket,
    required this.foreground,
    required this.indicatorFrom,
    required this.indicatorTarget,
    required this.onNotes,
    required this.onReminders,
    required this.onTrash,
    required this.onSearch,
    required this.onCreate,
  });

  final String bucket;
  final Color foreground;
  final double indicatorFrom;
  final int indicatorTarget;
  final VoidCallback onNotes;
  final VoidCallback onReminders;
  final VoidCallback onTrash;
  final VoidCallback onSearch;
  final VoidCallback onCreate;

  Widget _tabButton({
    required String symbol,
    required String effectId,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    return SizedBox.square(
      key: ValueKey(effectId),
      dimension: _MobileBottomNavState._iosItemSize,
      child: AnimatedScale(
        scale: selected ? 1.06 : 1,
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutBack,
        child: CNButton.icon(
          icon: CNSymbol(
            symbol,
            size: _MobileBottomNavState._iosNavIconSize,
            mode: CNSymbolRenderingMode.monochrome,
          ),
          onPressed: onPressed,
          tint: foreground,
          config: const CNButtonConfig(
            width: _MobileBottomNavState._iosItemSize,
            minHeight: _MobileBottomNavState._iosItemSize,
            padding: EdgeInsets.all(18),
            style: CNButtonStyle.plain,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final selectedSlot = _MobileBottomNavState._slotForBucket(bucket);
    const itemSize = _MobileBottomNavState._iosItemSize;
    const inset = _MobileBottomNavState._iosTabBarInset;
    const selectionSize = _MobileBottomNavState._iosCreateButtonSize;
    return SizedBox(
      key: const ValueKey('ios-native-bottom-navigation'),
      width: _MobileBottomNavState._iosDockWidth,
      height: _MobileBottomNavState._iosNativeBarHeight,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            key: const ValueKey('ios-native-tab-bar'),
            width: _MobileBottomNavState._iosTabBarWidth,
            height: _MobileBottomNavState._iosNativeBarHeight,
            child: LiquidGlassContainer(
              key: const ValueKey('ios-native-tab-bar-glass'),
              config: LiquidGlassConfig(
                effect: CNGlassEffect.regular,
                shape: CNGlassEffectShape.capsule,
                tint: dark
                    ? Colors.white.withValues(alpha: 0.025)
                    : Colors.white.withValues(alpha: 0.10),
                interactive: true,
              ),
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(
                      begin: indicatorFrom,
                      end: indicatorTarget.toDouble(),
                    ),
                    duration: const Duration(milliseconds: 460),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, child) => Positioned(
                      left: inset +
                          value * itemSize +
                          (itemSize - selectionSize) / 2,
                      width: selectionSize,
                      height: selectionSize,
                      child: child!,
                    ),
                    child: DecoratedBox(
                      key: const ValueKey('ios-native-nav-selection'),
                      decoration: BoxDecoration(
                        color: dark
                            ? Colors.white.withValues(alpha: 0.14)
                            : Colors.black.withValues(alpha: 0.075),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: inset),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _tabButton(
                          symbol: 'note.text',
                          effectId: 'ios-native-nav-notes',
                          selected: selectedSlot == 0,
                          onPressed: onNotes,
                        ),
                        _tabButton(
                          symbol: 'bell',
                          effectId: 'ios-native-nav-reminders',
                          selected: selectedSlot == 1,
                          onPressed: onReminders,
                        ),
                        _tabButton(
                          symbol: 'trash',
                          effectId: 'ios-native-nav-trash',
                          selected: selectedSlot == 2,
                          onPressed: onTrash,
                        ),
                        _tabButton(
                          symbol: 'magnifyingglass',
                          effectId: 'ios-native-nav-search',
                          selected: false,
                          onPressed: onSearch,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: _MobileBottomNavState._iosGap),
          SizedBox.square(
            dimension: _MobileBottomNavState._iosNativeBarHeight,
            child: Center(
              child: CNButton.icon(
                key: const ValueKey('ios-native-nav-create'),
                icon: const CNSymbol(
                  'plus',
                  size: _MobileBottomNavState._iosNavIconSize,
                ),
                onPressed: onCreate,
                tint: foreground,
                config: const CNButtonConfig(
                  width: _MobileBottomNavState._iosCreateButtonSize,
                  minHeight: _MobileBottomNavState._iosCreateButtonSize,
                  padding: EdgeInsets.all(15),
                  style: CNButtonStyle.prominentGlass,
                  glassEffectInteractive: true,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _IosNativeNavButtonGroup extends StatelessWidget {
  const _IosNativeNavButtonGroup({
    required this.bucket,
    required this.expanded,
    required this.foreground,
    required this.indicatorFrom,
    required this.indicatorTarget,
    required this.indicatorPosition,
    required this.indicatorLift,
    required this.onNotes,
    required this.onReminders,
    required this.onTrash,
    required this.onSearch,
    required this.onCreate,
  });

  final String bucket;
  final bool expanded;
  final Color foreground;
  final double indicatorFrom;
  final int indicatorTarget;
  final AnimationController indicatorPosition;
  final AnimationController indicatorLift;
  final VoidCallback onNotes;
  final VoidCallback onReminders;
  final VoidCallback onTrash;
  final VoidCallback onSearch;
  final VoidCallback onCreate;

  Widget _button({
    required BuildContext context,
    required String symbol,
    required String effectId,
    required VoidCallback onPressed,
    bool selected = false,
    bool prominent = false,
    double rotationTurns = 0,
    Color? prominentFill,
    Color? prominentForeground,
  }) {
    return SizedBox.square(
      key: ValueKey(effectId),
      dimension: _MobileBottomNavState._iosItemSize,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (prominent)
            IgnorePointer(
              child: LiquidGlassContainer(
                key: ValueKey('$effectId-glass'),
                config: LiquidGlassConfig(
                  effect: CNGlassEffect.regular,
                  shape: CNGlassEffectShape.circle,
                  tint: prominentFill,
                  interactive: true,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          AnimatedRotation(
            key: prominent
                ? const ValueKey('ios-native-create-symbol-rotation')
                : null,
            turns: rotationTurns,
            duration: AppMotion.duration(
              context,
              const Duration(milliseconds: 280),
            ),
            curve: Curves.easeInOutBack,
            child: AnimatedScale(
              scale: selected ? 1.04 : 1,
              duration: const Duration(milliseconds: 360),
              curve: Curves.easeOutBack,
              child: CNButton.icon(
                icon: CNSymbol(
                  symbol,
                  size: _MobileBottomNavState._iosNavIconSize,
                  mode: CNSymbolRenderingMode.monochrome,
                ),
                onPressed: onPressed,
                // Keep every tab symbol neutral. Selection is communicated by
                // the moving native refractive lens.
                tint: prominent ? prominentForeground : foreground,
                config: const CNButtonConfig(
                  width: _MobileBottomNavState._iosItemSize,
                  minHeight: _MobileBottomNavState._iosItemSize,
                  padding: EdgeInsets.all(18),
                  style: CNButtonStyle.plain,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final itemSize = _MobileBottomNavState._iosItemSize;
    final gap = _MobileBottomNavState._iosGap;
    final slotExtent = itemSize + gap;
    final selectedSlot = _MobileBottomNavState._slotForBucket(bucket);
    const selectionSize = _MobileBottomNavState._iosIndicatorRestSize;
    return SizedBox(
      key: const ValueKey('ios-native-nav-button-group'),
      height: itemSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _IosLiquidSelectionIndicator(
            dark: dark,
            from: indicatorFrom,
            target: indicatorTarget,
            position: indicatorPosition,
            lift: indicatorLift,
            itemSize: itemSize,
            slotExtent: slotExtent,
            restSize: selectionSize,
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _button(
                context: context,
                symbol: 'doc.text',
                effectId: 'ios-native-nav-notes',
                selected: selectedSlot == 0,
                onPressed: onNotes,
              ),
              SizedBox(width: gap),
              _button(
                context: context,
                symbol: 'bell',
                effectId: 'ios-native-nav-reminders',
                selected: selectedSlot == 1,
                onPressed: onReminders,
              ),
              SizedBox(width: gap),
              _button(
                context: context,
                symbol: 'trash',
                effectId: 'ios-native-nav-trash',
                selected: selectedSlot == 2,
                onPressed: onTrash,
              ),
              SizedBox(width: gap),
              _button(
                context: context,
                symbol: 'magnifyingglass',
                effectId: 'ios-native-nav-search',
                onPressed: onSearch,
              ),
              SizedBox(width: gap),
              _button(
                context: context,
                symbol: 'plus',
                effectId: 'ios-native-nav-create',
                prominent: true,
                rotationTurns: expanded ? 0.125 : 0,
                prominentFill: dark ? Colors.white : const Color(0xff17201f),
                prominentForeground:
                    dark ? const Color(0xff17201f) : Colors.white,
                onPressed: onCreate,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _IosLiquidSelectionIndicator extends StatelessWidget {
  const _IosLiquidSelectionIndicator({
    required this.dark,
    required this.from,
    required this.target,
    required this.position,
    required this.lift,
    required this.itemSize,
    required this.slotExtent,
    required this.restSize,
  });

  final bool dark;
  final double from;
  final int target;
  final AnimationController position;
  final AnimationController lift;
  final double itemSize;
  final double slotExtent;
  final double restSize;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([position, lift]),
      builder: (context, _) {
        final value = position.value;
        final lifted = lift.value.clamp(0.0, 1.0);

        // The glass first rises out of its resting circle, stays lifted for
        // the spring travel, then lands. The spring's current acceleration is
        // converted to the same opposing-axis deformation used by the
        // reference package (capped at 12% for tab-scale motion).
        final envelope =
            restSize + _MobileBottomNavState._iosIndicatorGrowSize * lifted;
        final acceleration =
            (-280 * (value - target) - 31.4 * position.velocity) * slotExtent;
        final force = (acceleration.abs() * 0.00007).clamp(0.0, 0.12) * lifted;
        final direction = (target - from).sign;
        final deformation = -direction * force;
        final width = envelope * (1 + deformation);
        final height = envelope * (1 - deformation);
        final atTarget =
            (value - target).abs() < 0.001 && position.velocity.abs() < 0.01;
        final settledTintOpacity =
            atTarget ? math.pow(1 - lifted, 2).toDouble().clamp(0.0, 1.0) : 0.0;
        final settledOverlay = dark
            ? Colors.white.withValues(alpha: 0.065)
            : Colors.black.withValues(alpha: 0.08);

        return Positioned(
          left: value * slotExtent + (itemSize - width) / 2,
          top: (itemSize - height) / 2,
          width: width,
          height: height,
          child: LiquidGlassContainer(
            key: const ValueKey('ios-native-nav-selection'),
            config: LiquidGlassConfig(
              effect: CNGlassEffect.regular,
              shape: CNGlassEffectShape.circle,
            ),
            // Keep the native glass itself untinted at all times. Updating a
            // native tint animates inside SwiftUI and can trail the moving
            // lens; this Flutter overlay is therefore exactly zero in flight
            // and fades in only while the lens lands at its destination.
            child: Opacity(
              key: const ValueKey('ios-native-nav-selection-settled-tint'),
              opacity: settledTintOpacity,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: settledOverlay,
                  shape: BoxShape.circle,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MobileNavTrashDropButton extends ConsumerStatefulWidget {
  const _MobileNavTrashDropButton({
    super.key,
    required this.note,
    required this.morphProgress,
  });

  final PlainNote note;
  final double morphProgress;

  @override
  ConsumerState<_MobileNavTrashDropButton> createState() =>
      _MobileNavTrashDropButtonState();
}

class _MobileNavTrashDropButtonState
    extends ConsumerState<_MobileNavTrashDropButton> {
  var _hovered = false;

  void _setHovered(bool hovered) {
    if (_hovered == hovered) return;
    setState(() => _hovered = hovered);
    ref.read(_dragTrashHoverProvider.notifier).state = hovered;
  }

  void _accept(PlainNote note) {
    ref.read(_draggedNoteProvider.notifier).state = null;
    ref.read(_dragTrashHoverProvider.notifier).state = false;
    _changeNoteStateWithFeedback(
      context: context,
      ref: ref,
      note: note,
      nextState: 'trashed',
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = ref.watch(l10nProvider);
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final navForeground = dark
        ? Colors.white.withValues(alpha: 0.7)
        : const Color(0xff171c19).withValues(alpha: 0.72);
    final morphForeground = Color.lerp(
      navForeground,
      scheme.onSurface,
      widget.morphProgress,
    )!;
    return DragTarget<PlainNote>(
      onWillAcceptWithDetails: (details) {
        _setHovered(true);
        return details.data.localId == widget.note.localId;
      },
      onLeave: (_) => _setHovered(false),
      onAcceptWithDetails: (details) {
        _setHovered(false);
        _accept(details.data);
      },
      builder: (context, candidateData, rejectedData) {
        final active = _hovered || candidateData.isNotEmpty;
        return Tooltip(
          message: l10n.t('moveToTrash'),
          child: Semantics(
            label: l10n.t('moveToTrash'),
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: active ? 1 : 0),
              duration: AppMotion.duration(
                context,
                const Duration(milliseconds: 240),
              ),
              curve: Curves.easeOutCubic,
              builder: (context, value, child) {
                final glow = Curves.easeOutCubic.transform(value);
                final settle = math.sin(glow * math.pi);
                return Transform.scale(
                  scaleX: 1 + glow * 0.012 + settle * 0.006,
                  scaleY: 1 + glow * 0.008 - settle * 0.004,
                  child: Transform.translate(
                    offset: Offset(0, -1 * glow),
                    child: SizedBox.square(
                      dimension: _MobileBottomNavState._trashDropSize -
                          _MobileBottomNavState._inset * 2,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color:
                                  scheme.error.withValues(alpha: 0.18 * glow),
                              blurRadius: 20 + 9 * glow,
                              spreadRadius: 1 + glow,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Transform.scale(
                            key: const ValueKey(
                              'mobile-nav-trash-icon-scale',
                            ),
                            scale: _usesIosNativeControls
                                ? 1
                                : 1 + widget.morphProgress * 0.65,
                            child: _usesIosNativeControls
                                ? CNButton.icon(
                                    key: const ValueKey(
                                      'ios-native-trash-drop-symbol',
                                    ),
                                    icon: CNSymbol(
                                      'trash',
                                      size: lerpDouble(
                                        AppSizes.iosCompactHeaderIcon,
                                        32,
                                        widget.morphProgress,
                                      )!,
                                      mode: CNSymbolRenderingMode.monochrome,
                                    ),
                                    tint: Color.lerp(
                                      morphForeground,
                                      scheme.error,
                                      glow,
                                    ),
                                    onPressed: () {},
                                    config: const CNButtonConfig(
                                      width: 76,
                                      minHeight: 76,
                                      padding: EdgeInsets.all(20),
                                      style: CNButtonStyle.plain,
                                      interaction: false,
                                      glassEffectInteractive: false,
                                    ),
                                  )
                                : Icon(
                                    AppIcons.trash2,
                                    key: const ValueKey(
                                      'mobile-nav-trash-icon-color',
                                    ),
                                    size: 20,
                                    color: Color.lerp(
                                      morphForeground,
                                      scheme.error,
                                      glow,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _IosNativeCreateActions extends StatelessWidget {
  const _IosNativeCreateActions({
    required this.animation,
    required this.noteLabel,
    required this.reminderLabel,
    required this.listLabel,
    required this.onNote,
    required this.onReminder,
    required this.onList,
  });

  final Animation<double> animation;
  final String noteLabel;
  final String reminderLabel;
  final String listLabel;
  final VoidCallback onNote;
  final VoidCallback onReminder;
  final VoidCallback onList;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onSurface;
    return Padding(
      padding:
          const EdgeInsets.only(top: _MobileBottomNavState._createMenuInset),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth - 12) / 3;
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              final value = animation.value;
              // Keep the native glass views mounted even while invisible so
              // iOS has their material and shadow ready before the pop begins.
              // Lift them by the shell's missing height so they stay above
              // the navbar while its shared surface grows upward. Their
              // native shadows can then fade freely without a clipping edge.
              final surfaceProgress =
                  animation.status == AnimationStatus.reverse
                      ? Curves.easeInCubic.transform(value)
                      : Curves.easeOutCubic.transform(value);
              final surfaceHeight = lerpDouble(
                _MobileBottomNavState._iosNativeBarHeight,
                _MobileBottomNavState._iosExpandedBarHeight,
                surfaceProgress,
              )!;
              final drawerLift =
                  _MobileBottomNavState._iosExpandedBarHeight - surfaceHeight;
              final actions = <({
                String label,
                String symbol,
                String effectId,
                VoidCallback onPressed,
              })>[
                (
                  label: noteLabel,
                  symbol: 'doc.badge.plus',
                  effectId: 'notes-create-note',
                  onPressed: onNote,
                ),
                (
                  label: reminderLabel,
                  symbol: 'bell.badge',
                  effectId: 'notes-create-reminder',
                  onPressed: onReminder,
                ),
                (
                  label: listLabel,
                  symbol: 'checklist',
                  effectId: 'notes-create-list',
                  onPressed: onList,
                ),
              ];
              return Row(
                key: const ValueKey('ios-native-create-actions'),
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < actions.length; index++) ...[
                    if (index > 0) const SizedBox(width: 6),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final start = 0.08 + index * 0.08;
                          final linearProgress =
                              ((value - start) / (1 - start)).clamp(0.0, 1.0);
                          final fadeProgress = Curves.easeOutCubic.transform(
                            linearProgress,
                          );
                          final popProgress = Curves.easeOutBack.transform(
                            linearProgress,
                          );
                          final closing =
                              animation.status == AnimationStatus.reverse;
                          final exitDelay = (actions.length - 1 - index) * 0.03;
                          final exitProgress =
                              ((1 - value - exitDelay) / 0.48).clamp(0.0, 1.0);
                          final exitCurve =
                              Curves.easeOutCubic.transform(exitProgress);
                          // Stay one compositor alpha step below 1.0 so the
                          // native platform view keeps the same opacity layer
                          // at rest; otherwise its shadow changes when Flutter
                          // removes that layer on the final frame.
                          final actionOpacity = closing
                              ? math.min(1 - exitCurve, 0.996)
                              : math.min(fadeProgress, 0.996);
                          // Move the native glass view through layout instead
                          // of applying a paint transform. A transformed
                          // UiKitView receives a temporary composited shadow
                          // which iOS drops as soon as the transform becomes
                          // the identity matrix. The overshooting vertical
                          // offset retains the staggered pop without that
                          // final-frame shadow swap or changing text layout.
                          final actionOffset = closing
                              ? -drawerLift - 6 * exitCurve
                              : -drawerLift - 10 * (1 - popProgress);
                          return SizedBox(
                            height: 64,
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Positioned(
                                  key: ValueKey(
                                    'ios-native-${actions[index].effectId}-pop',
                                  ),
                                  top: actionOffset,
                                  left: 0,
                                  right: 0,
                                  height: 64,
                                  child: Opacity(
                                    key: ValueKey(
                                      'ios-native-${actions[index].effectId}-opacity',
                                    ),
                                    opacity: actionOpacity,
                                    child: LiquidGlassContainer(
                                      key: ValueKey(
                                        'ios-native-${actions[index].effectId}-surface',
                                      ),
                                      config: LiquidGlassConfig(
                                        effect: CNGlassEffect.regular,
                                        shape: CNGlassEffectShape.rect,
                                        cornerRadius: _MobileBottomNavState
                                            ._createActionRadius,
                                        // The plain CNButton remains fully
                                        // tappable. Interactive glass reacts
                                        // to motion with temporary elevation
                                        // and a shadow that disappears once
                                        // the card stops moving.
                                        interactive: false,
                                      ),
                                      child: CNButton(
                                        key: ValueKey(
                                          'ios-native-${actions[index].effectId}',
                                        ),
                                        label: actions[index].label,
                                        icon: CNSymbol(
                                          actions[index].symbol,
                                          size: 13,
                                          mode:
                                              CNSymbolRenderingMode.monochrome,
                                        ),
                                        tint: foreground,
                                        onPressed: actions[index].onPressed,
                                        config: CNButtonConfig(
                                          width: itemWidth,
                                          minHeight: 64,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 7,
                                            vertical: 8,
                                          ),
                                          borderRadius: _MobileBottomNavState
                                              ._createActionRadius,
                                          imagePadding: 4,
                                          imagePlacement: CNImagePlacement.top,
                                          style: CNButtonStyle.plain,
                                          maxLines: 1,
                                          labelFontSize: 11.5,
                                          labelFontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _MobileNavDrawerSurface extends StatelessWidget {
  const _MobileNavDrawerSurface({
    required this.animation,
    required this.morphProgress,
    required this.collapsedHeight,
    required this.expandedHeight,
    required this.trashHeight,
    required this.collapsedRadius,
    required this.trashRadius,
  });

  final Animation<double> animation;
  final double morphProgress;
  final double collapsedHeight;
  final double expandedHeight;
  final double trashHeight;
  final double collapsedRadius;
  final double trashRadius;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final constrainedRaster = _usesAndroidRasterBudget;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final animatedMorph = morphProgress.clamp(0.0, 1.0);
        final menuProgress = Curves.easeOutCubic.transform(animation.value);
        final menuHeight =
            lerpDouble(collapsedHeight, expandedHeight, menuProgress)!;
        final morphHeight =
            lerpDouble(collapsedHeight, trashHeight, animatedMorph)!;
        final height = lerpDouble(menuHeight, morphHeight, animatedMorph)!;
        final menuBorderRadius = BorderRadius.only(
          topLeft: const Radius.circular(
            _MobileBottomNavState._expandedDrawerTopRadius,
          ),
          topRight: const Radius.circular(
            _MobileBottomNavState._expandedDrawerTopRadius,
          ),
          bottomLeft: Radius.circular(collapsedRadius),
          bottomRight: Radius.circular(collapsedRadius),
        );
        final borderRadius = animatedMorph > 0
            ? BorderRadius.circular(
                lerpDouble(collapsedRadius, trashRadius, animatedMorph)!,
              )
            : BorderRadius.lerp(
                BorderRadius.circular(collapsedRadius),
                menuBorderRadius,
                menuProgress,
              )!;
        final shape = RoundedSuperellipseBorder(
          borderRadius: borderRadius,
        );
        final fill = _usesIosNativeControls
            ? Colors.transparent
            : AppChromeGlass.tint(brightness);
        final surface = Stack(
          fit: StackFit.expand,
          children: [
            DecoratedBox(
              key: const ValueKey('mobile-nav-drawer-fill'),
              decoration: ShapeDecoration(
                color: fill,
                shape: shape.copyWith(
                  side: BorderSide(
                    color: _usesIosNativeControls
                        ? Colors.transparent
                        : AppChromeGlass.outerStroke(brightness),
                    width: 1,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(0.75),
                child: DecoratedBox(
                  key: const ValueKey('mobile-nav-inner-highlight'),
                  decoration: ShapeDecoration(
                    shape: shape.copyWith(
                      side: BorderSide(
                        color: _usesIosNativeControls
                            ? Colors.transparent
                            : AppChromeGlass.innerStroke(brightness),
                        width: 0.55,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
        return Positioned(
          key: const ValueKey('mobile-nav-drawer-surface-position'),
          left: 0,
          right: 0,
          bottom: 0,
          height: height,
          child: RepaintBoundary(
            child: DecoratedBox(
              decoration: ShapeDecoration(
                shape: shape,
                shadows: _usesIosNativeControls
                    ? null
                    : constrainedRaster
                        ? [
                            BoxShadow(
                              color: AppChromeGlass.shadow(brightness),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : brightness == Brightness.dark
                            ? [
                                BoxShadow(
                                  color: AppChromeGlass.shadow(brightness),
                                  blurRadius: 18,
                                  offset: const Offset(0, 9),
                                ),
                              ]
                            : [
                                BoxShadow(
                                  color: AppChromeGlass.shadow(brightness),
                                  blurRadius: 16,
                                  spreadRadius: -1,
                                  offset: const Offset(0, 6),
                                ),
                                BoxShadow(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  blurRadius: 7,
                                  spreadRadius: -2,
                                  offset: const Offset(0, -1),
                                ),
                              ],
              ),
              child: ClipPath(
                clipper: ShapeBorderClipper(shape: shape),
                child: _usesIosNativeControls
                    ? LiquidGlassContainer(
                        key: const ValueKey('ios-native-create-drawer-glass'),
                        config: LiquidGlassConfig(
                          effect: CNGlassEffect.regular,
                          shape: CNGlassEffectShape.rect,
                          cornerRadius:
                              _MobileBottomNavState._expandedDrawerTopRadius,
                          tint: brightness == Brightness.dark
                              ? Colors.black.withValues(alpha: 0.12)
                              : canvasBaseLight.withValues(alpha: 0.025),
                        ),
                        child: surface,
                      )
                    : BackdropFilter(
                        key: const ValueKey('mobile-bottom-nav-backdrop'),
                        filter: _NotesChromeGlass.filter(brightness),
                        child: surface,
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

abstract final class _NotesChromeGlass {
  static final ImageFilter _lightFull = ImageFilter.blur(
    sigmaX: AppChromeGlass.lightBlur,
    sigmaY: AppChromeGlass.lightBlur,
  );
  static final ImageFilter _darkFull = ImageFilter.blur(
    sigmaX: AppChromeGlass.darkBlur,
    sigmaY: AppChromeGlass.darkBlur,
  );
  static final ImageFilter _lightWeb = ImageFilter.blur(
    sigmaX: AppChromeGlass.lightWebBlur,
    sigmaY: AppChromeGlass.lightWebBlur,
  );
  static final ImageFilter _darkWeb = ImageFilter.blur(
    sigmaX: AppChromeGlass.darkWebBlur,
    sigmaY: AppChromeGlass.darkWebBlur,
  );
  static final ImageFilter _lightConstrained = ImageFilter.blur(
    sigmaX: AppChromeGlass.lightConstrainedBlur,
    sigmaY: AppChromeGlass.lightConstrainedBlur,
  );
  static final ImageFilter _darkConstrained = ImageFilter.blur(
    sigmaX: AppChromeGlass.darkConstrainedBlur,
    sigmaY: AppChromeGlass.darkConstrainedBlur,
  );

  static ImageFilter filter(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    if (_usesAndroidRasterBudget) {
      return dark ? _darkConstrained : _lightConstrained;
    }
    if (kIsWeb) return dark ? _darkWeb : _lightWeb;
    return dark ? _darkFull : _lightFull;
  }
}

class _MobileNavGlassSurface extends StatelessWidget {
  const _MobileNavGlassSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const ValueKey('mobile-bottom-nav-pill'),
      child: _usesIosNativeControls
          ? child
          : Padding(
              padding: const EdgeInsets.all(_MobileBottomNavState._inset),
              child: child,
            ),
    );
  }
}

class _MobileNavSearchField extends StatelessWidget {
  const _MobileNavSearchField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.onChanged,
    required this.onClose,
    this.useNativeSurface = true,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final bool useNativeSurface;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nativeSearchControls = _usesIosNativeControls;
    final searchIcon = nativeSearchControls
        ? Padding(
            padding: const EdgeInsets.only(left: 10, right: 2),
            child: CNButton.icon(
              key: const ValueKey('ios-native-search-leading-symbol'),
              icon: const CNSymbol(
                'magnifyingglass',
                size: AppSizes.iosCompactHeaderIcon,
                mode: CNSymbolRenderingMode.monochrome,
              ),
              tint: scheme.onSurfaceVariant,
              onPressed: focusNode.requestFocus,
              config: const CNButtonConfig(
                width: 44,
                minHeight: 44,
                padding: EdgeInsets.all(13.5),
                style: CNButtonStyle.plain,
                glassEffectInteractive: false,
              ),
            ),
          )
        : Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15),
            child: Icon(
              AppIcons.search,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          );
    final closeButton = nativeSearchControls
        ? Padding(
            padding: const EdgeInsets.only(left: 2, right: 10),
            child: CNButton.icon(
              key: const ValueKey('mobile-nav-search-close'),
              icon: const CNSymbol(
                'xmark',
                size: AppSizes.iosCompactHeaderIcon,
                mode: CNSymbolRenderingMode.monochrome,
              ),
              tint: scheme.onSurface,
              onPressed: onClose,
              config: const CNButtonConfig(
                width: 44,
                minHeight: 44,
                padding: EdgeInsets.all(13.5),
                style: CNButtonStyle.plain,
                glassEffectInteractive: false,
              ),
            ),
          )
        : IconButton(
            key: const ValueKey('mobile-nav-search-close'),
            tooltip: AppL10n(Localizations.localeOf(context).languageCode).t(
              'close',
            ),
            onPressed: onClose,
            icon: const Icon(AppIcons.x, size: 17),
          );
    final content = Row(
      key: const ValueKey('mobile-nav-search-field'),
      children: [
        searchIcon,
        Expanded(
          child: TextField(
            key: const ValueKey('mobile-nav-search-input'),
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            textInputAction: TextInputAction.search,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              filled: false,
              fillColor: Colors.transparent,
              hintText: hintText,
              hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurface.withValues(alpha: 0.45),
                  ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        closeButton,
        if (!nativeSearchControls) const SizedBox(width: 3),
      ],
    );
    if (_usesIosNativeControls && useNativeSurface) {
      return LiquidGlassContainer(
        key: const ValueKey('ios-native-nav-search-surface'),
        config: LiquidGlassConfig(
          effect: CNGlassEffect.regular,
          shape: CNGlassEffectShape.capsule,
          tint: scheme.surface.withValues(alpha: 0.08),
          interactive: true,
        ),
        child: SizedBox(
          height: _MobileBottomNavState._iosSearchHeight,
          child: content,
        ),
      );
    }
    return content;
  }
}

class _MobileCreateDrawerAction extends StatefulWidget {
  const _MobileCreateDrawerAction({
    super.key,
    required this.icon,
    required this.label,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  State<_MobileCreateDrawerAction> createState() =>
      _MobileCreateDrawerActionState();
}

class _MobileCreateDrawerActionState extends State<_MobileCreateDrawerAction> {
  var _pressed = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Concentric geometry: inner radius = outer top radius - its inset.
    const shape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.all(
        Radius.circular(_MobileBottomNavState._createActionRadius),
      ),
    );
    final restingFill = dark
        ? _MobileBottomNavState._darkSelectionOverlay
        : _MobileBottomNavState._lightSelectionOverlay;
    final pressedFill = dark
        ? Colors.white.withValues(alpha: 0.15)
        : Colors.white.withValues(alpha: 0.90);
    final iconColor = scheme.onSurface.withValues(alpha: 0.92);
    return Tooltip(
      message: widget.semanticLabel,
      child: Semantics(
        button: true,
        label: widget.semanticLabel,
        child: Material(
          color: _pressed ? pressedFill : restingFill,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            customBorder: shape,
            onHighlightChanged: (highlighted) {
              if (_pressed != highlighted) {
                setState(() => _pressed = highlighted);
              }
            },
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: _pressed ? 0.94 : 1,
              duration: AppMotion.duration(
                context,
                const Duration(milliseconds: 130),
              ),
              curve: Curves.easeOutCubic,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox.square(
                      dimension: 22,
                      child: Center(
                        child: Icon(
                          widget.icon,
                          size: 18,
                          color: iconColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.label,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            height: 1.05,
                            fontSize: 12,
                            color: scheme.onSurface,
                            fontWeight: FontWeight.w700,
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

class _CreateActionsReveal extends StatelessWidget {
  const _CreateActionsReveal({
    required this.animation,
    required this.children,
  });

  final Animation<double> animation;
  final List<Widget> children;

  double _bubbleProgress(double progress, int index) {
    final start = index * 0.08;
    return ((progress - start) / (1 - start)).clamp(0.0, 1.0);
  }

  double _closingBubbleProgress(double progress, int index) {
    final fadeFloor = 0.52 + index * 0.02;
    return ((progress - fadeFloor) / (1 - fadeFloor)).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 68,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final progress = animation.value;
          if (progress <= 0) return const SizedBox.shrink();
          final closing = animation.status == AnimationStatus.reverse;
          final movementProgress =
              closing ? 1.0 : Curves.easeOutCubic.transform(progress);
          return Transform.translate(
            key: const ValueKey('mobile-create-actions-progress'),
            offset: Offset(0, 75 * (1 - movementProgress)),
            child: RepaintBoundary(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < children.length; index++) ...[
                    if (index > 0) const SizedBox(width: 7),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final local = closing
                              ? _closingBubbleProgress(progress, index)
                              : _bubbleProgress(progress, index);
                          final eased = Curves.easeInOutCubic.transform(local);
                          final overshoot = math.sin(math.pi * local) * 0.07;
                          return Opacity(
                            opacity: Curves.easeOutQuad.transform(local),
                            child: Transform.translate(
                              offset: Offset(0, 9 * (1 - eased)),
                              child: Transform.scale(
                                key: ValueKey(
                                  'mobile-create-action-bubble-$index',
                                ),
                                scale: 0.52 + eased * 0.48 + overshoot,
                                alignment: Alignment.center,
                                child: children[index],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _MobileCreateToggleButton extends StatefulWidget {
  const _MobileCreateToggleButton({
    required this.expanded,
    required this.dark,
    required this.onPressed,
    this.size = 52,
  });

  final bool expanded;
  final bool dark;
  final double size;
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
          },
          onTapCancel: () {
            _release();
          },
          onTapUp: (_) {
            _release();
            widget.onPressed();
          },
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _pressed ? 1 : 0),
            duration: AppMotion.duration(
              context,
              const Duration(milliseconds: 150),
            ),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Transform.scale(
              scaleX: 1 + value * 0.08,
              scaleY: 1 - value * 0.07,
              child: child,
            ),
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.dark ? Colors.white : const Color(0xff17201f),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: AnimatedRotation(
                    turns: widget.expanded ? 0.125 : 0,
                    duration: AppMotion.duration(
                      context,
                      const Duration(milliseconds: 260),
                    ),
                    curve: Curves.easeOutBack,
                    child: Icon(
                      AppIcons.plus,
                      size: 21,
                      color:
                          widget.dark ? const Color(0xff111514) : Colors.white,
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

class _MobileNavIcon extends StatefulWidget {
  const _MobileNavIcon({
    super.key,
    this.size = 52,
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
  });

  final double size;
  final IconData icon;
  final String tooltip;
  final bool selected;
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
    final lightIconColor = const Color(0xff171c19).withValues(alpha: 0.72);
    // The shared liquid indicator paints the selected background.
    const background = Colors.transparent;
    final foreground =
        dark ? Colors.white.withValues(alpha: 0.7) : lightIconColor;
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
          },
          onTapCancel: () {
            _release();
          },
          onTapUp: (_) {
            _release();
            widget.onPressed();
          },
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: _pressed ? 1 : 0),
            duration: AppMotion.duration(
              context,
              const Duration(milliseconds: 150),
            ),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Transform.scale(
              scaleX: 1 + value * 0.07,
              scaleY: 1 - value * 0.06,
              child: child,
            ),
            child: SizedBox(
              width: widget.size,
              height: widget.size,
              child: DecoratedBox(
                decoration: const BoxDecoration(
                  color: background,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(end: widget.selected ? 1 : 0),
                    duration: AppMotion.duration(
                      context,
                      const Duration(milliseconds: 320),
                    ),
                    curve: Curves.easeOutBack,
                    builder: (context, value, _) => Transform.scale(
                      scale: 1 + value * 0.22,
                      child: Icon(
                        widget.icon,
                        size: 20,
                        color: Color.lerp(
                          foreground,
                          Theme.of(context).colorScheme.onSurface,
                          value,
                        ),
                      ),
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

class _SearchField extends ConsumerWidget {
  const _SearchField();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = ref.watch(l10nProvider);
    final scheme = Theme.of(context).colorScheme;
    final design = context.safernotesTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            boxShadow: [
              BoxShadow(
                color: design.glassShadow,
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadii.pill),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: TextField(
                onChanged: (value) =>
                    ref.read(noteSearchProvider.notifier).state = value,
                style: Theme.of(context).textTheme.bodyLarge,
                decoration: InputDecoration(
                  hintText: l10n.t('searchNotes'),
                  hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.45),
                      ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 18),
                    child: Icon(
                      AppIcons.search,
                      size: 19,
                      color: scheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 48),
                  filled: true,
                  fillColor: dark
                      ? const Color(0xff232e2c).withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.94),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadii.pill),
                    borderSide: BorderSide(
                      color: scheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 17),
                ),
              ),
            ),
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
    return Material(
      key: const ValueKey('email-verification-banner'),
      color: scheme.surfaceContainer,
      borderRadius: BorderRadius.circular(AppRadii.xl),
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
          borderRadius: BorderRadius.circular(AppRadii.hero),
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
                        borderRadius: BorderRadius.circular(AppRadii.xl),
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
                      borderRadius: BorderRadius.circular(AppRadii.xl),
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
    required this.selected,
    required this.selectionActive,
    required this.onToggleSelection,
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
  final bool selected;
  final bool selectionActive;
  final VoidCallback onToggleSelection;
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
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 700;
    final desktop = width >= 900;
    final constrainedRaster = compact && _usesAndroidRasterBudget;
    final cardCornerRadius =
        compact ? AppRadii.noteCardCompact : AppRadii.noteCard;
    final cardShape = RoundedSuperellipseBorder(
      borderRadius: BorderRadius.circular(cardCornerRadius),
    );
    final showHoverActions = !compact;
    final displayTitle =
        note.title.trim() == 'Untitled note' ? '' : note.title.trim();
    final showSyncedStatus = note.dirty && !compact;
    final hasMetadata = note.checklist.isNotEmpty ||
        note.conflicted ||
        showSyncedStatus ||
        note.reminderAt != null ||
        note.shared;
    final showFooter = hasMetadata || showHoverActions;
    return MouseRegion(
      onEnter: (_) {
        if (mounted) setState(() => _hovered = true);
      },
      onExit: (_) {
        if (mounted) setState(() => _hovered = false);
      },
      child: AnimatedScale(
        scale: _hovered ? 1.008 : 1,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              key: ValueKey('note-card-selection-${note.localId}'),
              decoration: ShapeDecoration(
                shape: cardShape,
                shadows: [
                  BoxShadow(
                    color: design.glassShadow,
                    blurRadius: _hovered
                        ? 30
                        : constrainedRaster
                            ? 8
                            : compact
                                ? 14
                                : 22,
                    offset: Offset(
                      0,
                      _hovered
                          ? 14
                          : constrainedRaster
                              ? 4
                              : compact
                                  ? 7
                                  : 11,
                    ),
                  ),
                ],
              ),
              child: DecoratedBox(
                key: ValueKey('note-card-selection-outline-${note.localId}'),
                position: DecorationPosition.foreground,
                decoration: ShapeDecoration(
                  shape: RoundedSuperellipseBorder(
                    borderRadius: BorderRadius.circular(cardCornerRadius),
                    side: BorderSide(
                      color: widget.selected
                          ? scheme.primary.withValues(alpha: 0.78)
                          : Colors.transparent,
                      width: widget.selected ? 2 : 0,
                    ),
                  ),
                ),
                child: _DesktopNoteBackdrop(
                  noteId: note.localId,
                  enabled: desktop,
                  shape: cardShape,
                  child: Material(
                    color: bg,
                    elevation: 0,
                    shape: cardShape,
                    clipBehavior: Clip.antiAlias,
                    child: Ink(
                      decoration: ShapeDecoration(
                        gradient: brandNoteGradient(context, note.color),
                        shape: cardShape,
                      ),
                      child: InkWell(
                        onTap: widget.onTap,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: compact ? 136 : 168,
                          ),
                          child: Padding(
                            key: ValueKey('note-card-content-${note.localId}'),
                            padding: EdgeInsets.fromLTRB(
                              compact ? 14 : 20,
                              compact ? 12 : 18,
                              compact ? 14 : 20,
                              compact ? 14 : 20,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: displayTitle.isEmpty
                                          ? const SizedBox.shrink()
                                          : Padding(
                                              padding: EdgeInsets.only(
                                                top: compact ? 3 : 6,
                                                right: compact ? 6 : 8,
                                              ),
                                              child: Text(
                                                displayTitle,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleLarge
                                                    ?.copyWith(height: 1.15),
                                              ),
                                            ),
                                    ),
                                    IgnorePointer(
                                      ignoring: widget.selectionActive,
                                      child: _NoteFavoriteButton(
                                        noteId: note.localId,
                                        tooltip: note.pinned
                                            ? l10n.t('unpin')
                                            : l10n.t('pin'),
                                        icon: note.pinned
                                            ? AppIcons.heartFill
                                            : AppIcons.heart,
                                        selected: note.pinned,
                                        size: compact
                                            ? AppSizes.favoriteButtonCompact
                                            : AppSizes.favoriteButton,
                                        iconSize: compact ? 17 : 19,
                                        enableBlur: !compact,
                                        onPressed: widget.onTogglePin,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: compact ? 8 : 12),
                                if (note.labels.isNotEmpty) ...[
                                  _NoteLabelChips(labels: note.labels),
                                  SizedBox(height: compact ? 8 : 12),
                                ],
                                note.checklist.isNotEmpty &&
                                        note.body.trim().isEmpty
                                    ? _ChecklistPreview(items: note.checklist)
                                    : _FormattedPreview(
                                        text: note.body,
                                        delta: note.richTextDelta,
                                      ),
                                if (showFooter) ...[
                                  SizedBox(height: compact ? 10 : 16),
                                  SizedBox(
                                    height: compact ? 30 : 36,
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
                                        if (showSyncedStatus)
                                          _MetaPill(
                                            icon: AppIcons.cloudUpload,
                                            label: l10n.t('synced'),
                                            color: scheme.tertiary,
                                          ),
                                        if (note.reminderAt != null)
                                          _MetaPill(
                                            icon: AppIcons.bell,
                                            label: _formatReminder(
                                                note.reminderAt!, l10n),
                                            color: scheme.primary,
                                          ),
                                        if (note.shared)
                                          _MetaPill(
                                            icon: AppIcons.users,
                                            label: l10n.t('shared'),
                                            color: scheme.primary,
                                          ),
                                        const Spacer(),
                                        if (showHoverActions)
                                          Visibility(
                                            visible: _hovered &&
                                                !widget.selectionActive,
                                            maintainAnimation: true,
                                            maintainState: true,
                                            maintainSize: true,
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
                                                    tooltip:
                                                        l10n.t('archiveAction'),
                                                    icon: AppIcons.archive,
                                                    onPressed: widget.onArchive,
                                                  ),
                                                if (note.state == 'active' &&
                                                    note.reminderAt == null)
                                                  AppIconButton(
                                                    tooltip: l10n.t(
                                                        'collaboratorInvite'),
                                                    icon: note.shared
                                                        ? AppIcons.users
                                                        : AppIcons.userPlus,
                                                    onPressed: widget.onInvite,
                                                  ),
                                                if (note.state != 'trashed')
                                                  AppIconButton(
                                                    tooltip: l10n.t('reminder'),
                                                    icon: AppIcons.bell,
                                                    onPressed:
                                                        widget.onReminder,
                                                  ),
                                                if (note.state != 'trashed')
                                                  AppIconButton(
                                                    tooltip: l10n.t('trash'),
                                                    icon: AppIcons.trash,
                                                    onPressed: widget.onTrash,
                                                  )
                                                else
                                                  AppIconButton(
                                                    tooltip:
                                                        l10n.t('deleteForever'),
                                                    icon: AppIcons.trash2,
                                                    onPressed:
                                                        widget.onDeleteForever,
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
              ),
            ),
            if (showHoverActions)
              Positioned(
                left: -8,
                top: -8,
                child: _NoteSelectionControl(
                  noteId: note.localId,
                  visible: _hovered || widget.selected,
                  selected: widget.selected,
                  showCheck: _hovered,
                  size: 34,
                  iconSize: 19,
                  onPressed: widget.onToggleSelection,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DesktopNoteBackdrop extends StatelessWidget {
  const _DesktopNoteBackdrop({
    required this.noteId,
    required this.enabled,
    required this.shape,
    required this.child,
  });

  final String noteId;
  final bool enabled;
  final ShapeBorder shape;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return ClipPath(
      clipper: ShapeBorderClipper(
        shape: shape,
        textDirection: Directionality.of(context),
      ),
      child: BackdropFilter(
        key: ValueKey('desktop-note-backdrop-$noteId'),
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: child,
      ),
    );
  }
}

class _NoteSelectionControl extends StatelessWidget {
  const _NoteSelectionControl({
    required this.noteId,
    required this.visible,
    required this.selected,
    required this.onPressed,
    this.size = 26,
    this.iconSize = 16,
    this.showCheck = false,
  });

  final String noteId;
  final bool visible;
  final bool selected;
  final VoidCallback onPressed;
  final double size;
  final double iconSize;
  final bool showCheck;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        key: ValueKey('note-selection-control-$noteId'),
        opacity: visible ? 1 : 0,
        duration: AppMotion.duration(
          context,
          const Duration(milliseconds: 120),
        ),
        child: Tooltip(
          message: selected
              ? AppL10n(Localizations.localeOf(context).languageCode)
                  .t('clearSelection')
              : AppL10n(Localizations.localeOf(context).languageCode)
                  .t('selectNote'),
          child: Material(
            color: scheme.surface.withValues(alpha: selected ? 1 : 0.94),
            elevation: selected ? 3 : 1,
            shadowColor: Colors.black.withValues(alpha: 0.22),
            shape: CircleBorder(
              side: BorderSide(
                color: selected
                    ? scheme.surface
                    : scheme.outlineVariant.withValues(alpha: 0.9),
              ),
            ),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onPressed,
              child: SizedBox.square(
                dimension: size,
                child: AnimatedOpacity(
                  opacity: selected || showCheck ? 1 : 0,
                  duration: AppMotion.duration(
                    context,
                    const Duration(milliseconds: 100),
                  ),
                  child: Icon(
                    AppIcons.check,
                    size: iconSize,
                    color: selected
                        ? scheme.onSurface
                        : scheme.onSurfaceVariant.withValues(alpha: 0.72),
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

class _NoteFavoriteButton extends StatelessWidget {
  const _NoteFavoriteButton({
    required this.noteId,
    required this.tooltip,
    required this.icon,
    required this.selected,
    required this.size,
    required this.iconSize,
    required this.enableBlur,
    required this.onPressed,
  });

  final String noteId;
  final String tooltip;
  final IconData icon;
  final bool selected;
  final double size;
  final double iconSize;
  final bool enableBlur;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    if (_usesIosNativeControls) {
      final scheme = Theme.of(context).colorScheme;
      return Tooltip(
        message: tooltip,
        child: SizedBox.square(
          key: ValueKey('ios-note-favorite-$noteId'),
          dimension: size,
          child: CNButton.icon(
            icon: CNSymbol(
              selected ? 'heart.fill' : 'heart',
              size: iconSize,
            ),
            onPressed: onPressed,
            tint: selected ? brandLavender : scheme.onSurface,
            config: CNButtonConfig(
              style:
                  selected ? CNButtonStyle.prominentGlass : CNButtonStyle.glass,
              width: size,
              minHeight: size,
              padding: EdgeInsets.zero,
              glassEffectId: 'note-favorite-$noteId',
              glassEffectInteractive: true,
            ),
          ),
        ),
      );
    }
    return GlassCircleButton(
      tooltip: tooltip,
      icon: icon,
      selected: selected,
      size: size,
      iconSize: iconSize,
      enableBlur: enableBlur,
      onPressed: onPressed,
    );
  }
}

class _MeasuredNoteDraggable extends StatefulWidget {
  const _MeasuredNoteDraggable({
    super.key,
    required this.note,
    required this.trashHovering,
    required this.onDragStarted,
    this.onDragUpdate,
    required this.onDragEnded,
    required this.dragEnabled,
    required this.onLongPressSelect,
    required this.childWhenDragging,
    required this.child,
  });

  final PlainNote note;
  final ValueListenable<bool> trashHovering;
  final VoidCallback onDragStarted;
  final ValueChanged<Offset>? onDragUpdate;
  final VoidCallback onDragEnded;
  final bool dragEnabled;
  final VoidCallback onLongPressSelect;
  final Widget childWhenDragging;
  final Widget child;

  @override
  State<_MeasuredNoteDraggable> createState() => _MeasuredNoteDraggableState();
}

class _MeasuredNoteDraggableState extends State<_MeasuredNoteDraggable> {
  static const _dragActivationDistance = 10.0;
  // Keep-style interaction: respect the platform long-press timeout and only
  // then reveal selection. The active pointer may still become a drag later.
  static const _stationarySelectionDelay = Duration(milliseconds: 150);

  final _cardKey = GlobalKey();
  final _dragActive = ValueNotifier(false);
  Timer? _stationarySelectionTimer;
  Size? _dragFeedbackSize;
  Offset? _dragPointerPosition;
  Offset? _longPressOrigin;
  bool _pendingLongPress = false;
  bool _selectionCommitted = false;
  bool _dragStarted = false;

  Size? get _cardSize {
    final renderObject = _cardKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    return renderObject.size;
  }

  @override
  void dispose() {
    _stationarySelectionTimer?.cancel();
    _dragActive.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (event) => _dragPointerPosition = event.position,
      onPointerMove: (event) => _handlePointerMove(event.position),
      child: LongPressDraggable<PlainNote>(
        data: widget.note,
        maxSimultaneousDrags: widget.dragEnabled ? 1 : 0,
        delay: kLongPressTimeout,
        dragAnchorStrategy: pointerDragAnchorStrategy,
        feedback: _NoteDragFeedback(
          key: ValueKey('note-drag-feedback-${widget.note.localId}'),
          noteId: widget.note.localId,
          trashHovering: widget.trashHovering,
          dragActive: _dragActive,
          sizeReader: () => _dragFeedbackSize ?? _cardSize,
          child: widget.child,
        ),
        onDragStarted: _handleDragStarted,
        onDraggableCanceled: (_, __) => _handleDragEnded(),
        onDragEnd: (_) => _handleDragEnded(),
        onDragCompleted: _handleDragEnded,
        childWhenDragging:
            _dragStarted ? widget.childWhenDragging : widget.child,
        child: KeyedSubtree(
          key: _cardKey,
          child: widget.child,
        ),
      ),
    );
  }

  void _handlePointerMove(Offset position) {
    _dragPointerPosition = position;
    final origin = _longPressOrigin;
    if (origin == null) return;
    final distance = (position - origin).distance;
    if (!_dragStarted && distance >= _dragActivationDistance) {
      _stationarySelectionTimer?.cancel();
      if (_selectionCommitted) {
        _selectionCommitted = false;
        widget.onLongPressSelect();
      }
      _dragStarted = true;
      _dragActive.value = true;
      if (mounted) setState(() {});
      widget.onDragStarted();
    }
    if (_dragStarted) widget.onDragUpdate?.call(position);
  }

  void _handleDragStarted() {
    _stationarySelectionTimer?.cancel();
    _dragFeedbackSize = _cardSize;
    _longPressOrigin = _dragPointerPosition;
    _dragActive.value = false;
    _pendingLongPress = true;
    _selectionCommitted = false;
    _dragStarted = false;
    _stationarySelectionTimer = Timer(_stationarySelectionDelay, () {
      if (!mounted || !_pendingLongPress || _dragStarted) return;
      _pendingLongPress = false;
      _selectionCommitted = true;
      widget.onLongPressSelect();
    });
  }

  void _handleDragEnded() {
    _stationarySelectionTimer?.cancel();
    _stationarySelectionTimer = null;
    final select = _pendingLongPress && !_dragStarted;
    final endDrag = _dragStarted;
    _dragFeedbackSize = null;
    _dragPointerPosition = null;
    _longPressOrigin = null;
    _dragActive.value = false;
    _pendingLongPress = false;
    _selectionCommitted = false;
    _dragStarted = false;
    if (endDrag) widget.onDragEnded();
    if (select) widget.onLongPressSelect();
  }
}

class _NoteDragFeedback extends ConsumerWidget {
  const _NoteDragFeedback({
    super.key,
    required this.noteId,
    required this.trashHovering,
    required this.dragActive,
    required this.sizeReader,
    required this.child,
  });

  final String noteId;
  final ValueListenable<bool> trashHovering;
  final ValueListenable<bool> dragActive;
  final Size? Function() sizeReader;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final size = sizeReader() ?? const Size(260, 170);
    final navTrashHovering = ref.watch(_dragTrashHoverProvider);
    return ValueListenableBuilder<bool>(
      valueListenable: dragActive,
      builder: (context, active, _) => Opacity(
        opacity: active ? 1 : 0,
        child: Transform.translate(
          offset: Offset(-size.width / 2, -size.height / 2),
          child: Material(
            type: MaterialType.transparency,
            child: ValueListenableBuilder<bool>(
              valueListenable: trashHovering,
              builder: (context, hovering, _) => AnimatedOpacity(
                key: ValueKey('note-drag-trash-opacity-$noteId'),
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                opacity: hovering || navTrashHovering ? 0.24 : 1,
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NoteLabelChips extends StatelessWidget {
  const _NoteLabelChips({required this.labels});

  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final visible = labels.take(3).toList();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final label in visible)
          DecoratedBox(
            decoration: BoxDecoration(
              color: brandLavender.withValues(alpha: dark ? 0.20 : 0.16),
              borderRadius: BorderRadius.circular(AppRadii.pill),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: dark ? brandLavender : const Color(0xff53407f),
                    ),
              ),
            ),
          ),
        if (labels.length > visible.length)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '+${labels.length - visible.length}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
      ],
    );
  }
}

class _ChecklistPreview extends StatelessWidget {
  const _ChecklistPreview({required this.items});

  final List<ChecklistItem> items;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;
    final visible = items.take(compact ? 4 : 5).toList();
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in visible)
          Padding(
            padding: EdgeInsets.only(
              left: item.indent * 12.0,
              bottom: compact ? 5 : 8,
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: item.done
                    ? (dark
                        ? Colors.black.withValues(alpha: 0.26)
                        : Colors.black.withValues(alpha: 0.05))
                    : (dark
                        ? Colors.white.withValues(alpha: 0.07)
                        : Colors.black.withValues(alpha: 0.035)),
                borderRadius: BorderRadius.circular(AppRadii.pill),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  compact ? 7 : 8,
                  compact ? 5 : 7,
                  compact ? 10 : 14,
                  compact ? 5 : 7,
                ),
                child: Row(
                  children: [
                    Container(
                      width: compact ? 18 : 20,
                      height: compact ? 18 : 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: item.done ? brandLavender : Colors.transparent,
                        border: Border.all(
                          color: item.done
                              ? brandLavender
                              : scheme.onSurface.withValues(alpha: 0.38),
                          width: 1.4,
                        ),
                      ),
                      child: item.done
                          ? Icon(
                              AppIcons.check,
                              size: 12,
                              color:
                                  dark ? const Color(0xff231a38) : Colors.white,
                            )
                          : null,
                    ),
                    SizedBox(width: compact ? 8 : 10),
                    Expanded(
                      child: Text(
                        item.text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w500,
                              color: item.done
                                  ? scheme.onSurface.withValues(alpha: 0.6)
                                  : scheme.onSurface.withValues(alpha: 0.92),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (items.length > visible.length)
          Padding(
            padding: const EdgeInsets.only(left: 10, top: 2),
            child: Text(
              '+${items.length - visible.length}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
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
    final maxLines = MediaQuery.sizeOf(context).width < 700 ? 5 : 7;
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
      if (visibleLines.length == maxLines) break;
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
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
    );
  }

  Widget _buildDeltaPreview(BuildContext context, TextStyle? base) {
    final maxLines = MediaQuery.sizeOf(context).width < 700 ? 5 : 7;
    final lines = <TextSpan>[];
    var current = <InlineSpan>[];
    var orderedIndex = 1;

    void finishLine(Map<String, dynamic> blockAttributes) {
      if (lines.length >= maxLines) return;
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
      if (lines.length >= maxLines) break;
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
        if (lines.length >= maxLines) break;
      }
    }
    if (current.isNotEmpty && lines.length < maxLines) {
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
      maxLines: maxLines,
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final iosIconTint = dark ? const Color(0xfff8fbf9) : scheme.onSurface;
    final tooltip = email.isEmpty ? l10n.t('profile') : email;
    void openAccount() => _showAccountSideSheet(context, ref, email);
    if (compact && _usesIosNativeControls) {
      return Tooltip(
        message: tooltip,
        child: SizedBox.square(
          dimension: _MobileBottomNavState._iosItemSize,
          child: CNButton.icon(
            icon: const CNSymbol(
              'person',
              size: AppSizes.iosCompactHeaderIcon,
              mode: CNSymbolRenderingMode.monochrome,
            ),
            onPressed: openAccount,
            tint: iosIconTint,
            config: const CNButtonConfig(
              style: CNButtonStyle.glass,
              width: _MobileBottomNavState._iosItemSize,
              minHeight: _MobileBottomNavState._iosItemSize,
              padding: EdgeInsets.all(18),
              glassEffectId: 'notes-account-button',
              glassEffectInteractive: true,
            ),
          ),
        ),
      );
    }
    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: compact ? 0 : 8),
        child: compact
            ? _MobileHeaderGlassButtonSurface(
                onTap: openAccount,
                child: Icon(
                  AppIcons.user,
                  size: 20,
                  color: scheme.onSurface,
                ),
              )
            : GestureDetector(
                onTap: openAccount,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutBack,
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    AppIcons.user,
                    size: 18,
                    color: scheme.onSurface,
                  ),
                ),
              ),
      ),
    );
  }
}

void _openSettings(
  BuildContext context,
  WidgetRef ref, {
  bool openPlan = false,
}) {
  final reset = ref.read(_noteOverviewResetProvider.notifier);
  final route = Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(openPlan: openPlan),
    ),
  );
  unawaited(route.whenComplete(() {
    reset.state++;
  }));
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
      key: ValueKey('mobile-sidebar-bucket-$bucket'),
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
    super.key,
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
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(
                alpha: widget.selected
                    ? 0.18
                    : _hovered
                        ? 0.1
                        : 0,
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
    final session = ref.watch(authControllerProvider).valueOrNull;
    final usageCredentials = session == null ||
            session.accessToken.isEmpty ||
            session.defaultTenant.isEmpty
        ? null
        : (
            accessToken: session.accessToken,
            tenant: session.defaultTenant,
          );
    final accountUsage = usageCredentials == null
        ? null
        : ref.watch(_accountUsageProvider(usageCredentials));
    final localUsage = _localSubscriptionUsage(
      ref.watch(notesControllerProvider).valueOrNull ?? const [],
    );
    final initial = email.isEmpty ? '?' : email.substring(0, 1).toUpperCase();
    final scheme = Theme.of(context).colorScheme;
    final dark = scheme.brightness == Brightness.dark;
    final mobile = MediaQuery.sizeOf(context).width < 900;
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
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(0, 12, 0, 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (mobile) ...[
                                Column(
                                  key: const ValueKey(
                                    'mobile-sidebar-navigation',
                                  ),
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
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
                                  ],
                                ),
                                const SizedBox(height: 14),
                              ],
                              Container(
                                key: const ValueKey(
                                  'mobile-sidebar-sync-status',
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.surfaceContainerHighest
                                      .withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: const _SyncIndicator(showLabel: true),
                              ),
                              if (accountUsage != null) ...[
                                const SizedBox(height: 10),
                                _AccountQuotaPanel(
                                  usage: accountUsage,
                                  localUsage: localUsage,
                                  l10n: l10n,
                                  onRetry: () => ref.invalidate(
                                    _accountUsageProvider(usageCredentials!),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      _AccountActionTile(
                        key: const ValueKey('account-settings-action'),
                        icon: AppIcons.settings,
                        label: l10n.t('settings'),
                        onTap: () {
                          Navigator.of(context).pop();
                          _openSettings(context, ref);
                        },
                      ),
                      const SizedBox(height: 4),
                      _AccountActionTile(
                        key: const ValueKey('account-logout-action'),
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

class _AccountQuotaPanel extends StatelessWidget {
  const _AccountQuotaPanel({
    required this.usage,
    required this.localUsage,
    required this.l10n,
    required this.onRetry,
  });

  final AsyncValue<SubscriptionUsage> usage;
  final SubscriptionUsage localUsage;
  final AppL10n l10n;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('mobile-sidebar-quota-card'),
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.18),
        ),
      ),
      child: usage.when(
        loading: () => Row(
          children: [
            Icon(AppIcons.hardDrive, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                l10n.t('accountUsage'),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        error: (_, __) => _AccountQuotaContent(
          usage: localUsage,
          l10n: l10n,
          localEstimate: true,
          onRetry: onRetry,
        ),
        data: (value) => _AccountQuotaContent(
          usage: _mergeSubscriptionUsage(value, localUsage),
          l10n: l10n,
        ),
      ),
    );
  }
}

class _AccountQuotaContent extends StatelessWidget {
  const _AccountQuotaContent({
    required this.usage,
    required this.l10n,
    this.localEstimate = false,
    this.onRetry,
  });

  final SubscriptionUsage usage;
  final AppL10n l10n;
  final bool localEstimate;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final storageRatio = _quotaRatio(
      usage.storageBytesUsed,
      usage.storageBytesLimit,
    );
    final notesRatio = usage.maxNotes == null
        ? null
        : _quotaRatio(usage.notesCount, usage.maxNotes!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(AppIcons.hardDrive, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                l10n.t('accountUsage'),
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.surface.withValues(alpha: 0.48),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _planLabel(usage.plan),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
        if (localEstimate) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.t('localUsageEstimate'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ),
              SizedBox.square(
                dimension: 28,
                child: IconButton(
                  tooltip: l10n.t('retry'),
                  padding: EdgeInsets.zero,
                  onPressed: onRetry,
                  icon: const Icon(AppIcons.refreshCw, size: 15),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 14),
        _AccountQuotaMeter(
          key: const ValueKey('mobile-sidebar-storage-meter'),
          label: l10n.t('storage'),
          detail: l10n.t(
            'storageQuotaSummary',
            params: {
              'used': _formatBytes(usage.storageBytesUsed, l10n.languageCode),
              'limit': _formatBytes(usage.storageBytesLimit, l10n.languageCode),
            },
          ),
          value: storageRatio,
        ),
        const SizedBox(height: 12),
        _AccountQuotaMeter(
          key: const ValueKey('mobile-sidebar-notes-meter'),
          label: l10n.t('notes'),
          detail: usage.maxNotes == null
              ? l10n.t(
                  'unlimitedNotesQuota',
                  params: {
                    'used': _formatCount(
                      usage.notesCount,
                      l10n.languageCode,
                    ),
                  },
                )
              : l10n.t(
                  'notesQuotaSummary',
                  params: {
                    'used': _formatCount(
                      usage.notesCount,
                      l10n.languageCode,
                    ),
                    'limit': _formatCount(
                      usage.maxNotes!,
                      l10n.languageCode,
                    ),
                  },
                ),
          value: notesRatio,
        ),
      ],
    );
  }
}

class _AccountQuotaMeter extends StatelessWidget {
  const _AccountQuotaMeter({
    super.key,
    required this.label,
    required this.detail,
    required this.value,
  });

  final String label;
  final String detail;
  final double? value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progressColor = switch (value) {
      final amount? when amount >= 0.9 => scheme.error,
      final amount? when amount >= 0.75 => scheme.tertiary,
      _ => scheme.primary,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const Spacer(),
            Flexible(
              child: Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          ],
        ),
        if (value != null) ...[
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 6,
              value: value,
              backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
              color: progressColor,
            ),
          ),
        ],
      ],
    );
  }
}

double _quotaRatio(int used, int limit) {
  if (limit <= 0) return 0;
  return (used / limit).clamp(0.0, 1.0);
}

SubscriptionUsage _mergeSubscriptionUsage(
  SubscriptionUsage remote,
  SubscriptionUsage local,
) {
  if (remote.storageBytesUsed > 0 || local.storageBytesUsed == 0) return remote;
  return SubscriptionUsage(
    plan: remote.plan,
    storageBytesUsed: local.storageBytesUsed,
    storageBytesLimit: remote.storageBytesLimit > 0
        ? remote.storageBytesLimit
        : local.storageBytesLimit,
    notesCount: remote.notesCount > 0 ? remote.notesCount : local.notesCount,
    maxNotes: remote.maxNotes ?? local.maxNotes,
    notesBytesUsed: local.notesBytesUsed,
    attachmentsBytesUsed: remote.attachmentsBytesUsed,
  );
}

SubscriptionUsage _localSubscriptionUsage(List<PlainNote> notes) {
  final billable = notes.where((note) => note.state != 'deleted').toList();
  final noteBytes = billable.fold<int>(
    0,
    (total, note) => total + _estimatedEncryptedNoteBytes(note),
  );
  return SubscriptionUsage(
    plan: 'free',
    storageBytesUsed: noteBytes,
    storageBytesLimit: 500 * 1024 * 1024,
    notesCount: billable.length,
    maxNotes: 500,
    notesBytesUsed: noteBytes,
  );
}

int _estimatedEncryptedNoteBytes(PlainNote note) {
  final plaintextBytes =
      utf8.encode(jsonEncode(note.encryptedPayloadJson())).length;
  final ciphertextLength = ((plaintextBytes + 16) * 4 + 2) ~/ 3;
  final envelope = <String, dynamic>{
    'version': 1,
    'algorithm': 'AES_256_GCM',
    'nonce': '0' * 16,
    'ciphertext': '0' * ciphertextLength,
    'key_id': '0' * 36,
  };
  return utf8.encode(jsonEncode(envelope)).length + 32;
}

String _planLabel(String plan) => switch (plan.toLowerCase()) {
      'essential' => 'Essential',
      'pro' => 'Pro',
      'team' => 'Team',
      'enterprise' => 'Enterprise',
      _ => 'Free',
    };

String _formatBytes(int bytes, String languageCode) {
  const mib = 1024 * 1024;
  const gib = mib * 1024;
  if (bytes <= 0) return '0 MB';
  if (bytes >= gib) {
    return '${_formatDecimal(bytes / gib, languageCode)} GB';
  }
  final megabytes = math.max(bytes / mib, 0.01);
  return '${_formatDecimal(megabytes, languageCode)} MB';
}

String _formatDecimal(double value, String languageCode) {
  final digits = value >= 10 || value == value.roundToDouble()
      ? 0
      : value < 1
          ? 2
          : 1;
  final text = value.toStringAsFixed(digits);
  return languageCode == 'de' ? text.replaceFirst('.', ',') : text;
}

String _formatCount(int value, String languageCode) {
  final separator = languageCode == 'de' ? '.' : ',';
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var index = 0; index < digits.length; index++) {
    if (index > 0 && (digits.length - index) % 3 == 0) buffer.write(separator);
    buffer.write(digits[index]);
  }
  return buffer.toString();
}

class _AccountActionTile extends StatefulWidget {
  const _AccountActionTile({
    super.key,
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
                ? scheme.surfaceContainerHighest.withValues(alpha: 0.52)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.18),
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

Future<PlainNote?> _showReminderSheet(
    BuildContext context, WidgetRef ref, PlainNote note) async {
  var duplicateShared = false;
  if (note.shared && note.reminderAt == null) {
    duplicateShared = await _confirmDuplicateReminder(context) ?? false;
    if (!duplicateShared) return null;
  }
  if (!context.mounted) return null;
  final saved = await showModalBottomSheet<PlainNote>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReminderSheet(
      note: note,
      duplicateShared: duplicateShared,
    ),
  );
  if (saved?.reminderAt != null && context.mounted) {
    unawaited(_requestReminderPermissionAfterSave(context, ref));
  }
  return saved;
}

Future<void> _requestReminderPermissionAfterSave(
    BuildContext context, WidgetRef ref) async {
  final granted = await requestReminderPermission();
  if (!granted && context.mounted) {
    _showReminderPermissionRequired(context, ref);
  }
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
  final choice = await showModalBottomSheet<_ReminderNoteChoice>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReminderNotePicker(notes: candidates),
  );
  if (choice == null || !context.mounted) return;
  if (!choice.createNew) {
    await _showReminderSheet(context, ref, choice.note!);
    return;
  }
  final note = ref.read(notesControllerProvider.notifier).createEmptyNote();
  final saved = await _showReminderSheet(context, ref, note);
  if (saved != null && context.mounted) {
    _openEditor(context, ref, saved);
  }
}

class _ReminderNoteChoice {
  const _ReminderNoteChoice.existing(this.note) : createNew = false;
  const _ReminderNoteChoice.createNew()
      : note = null,
        createNew = true;

  final PlainNote? note;
  final bool createNew;
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
                        OutlinedButton.icon(
                          key: const ValueKey('reminder-create-new'),
                          onPressed: () => Navigator.of(context).pop(
                            const _ReminderNoteChoice.createNew(),
                          ),
                          icon: const Icon(AppIcons.filePlus2),
                          label: Text(l10n.t('createNewReminder')),
                        ),
                        const SizedBox(height: 10),
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
                                      onTap: () => Navigator.of(context).pop(
                                        _ReminderNoteChoice.existing(note),
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
    final messenger = ScaffoldMessenger.of(context);
    try {
      late final PlainNote saved;
      if (widget.duplicateShared && reminderAt != null) {
        saved = await ref
            .read(notesControllerProvider.notifier)
            .duplicateAsReminder(
              source: widget.note,
              reminderAt: reminderAt.toUtc(),
            );
      } else {
        final normalized = reminderAt?.toUtc();
        await ref.read(notesControllerProvider.notifier).setReminder(
              widget.note,
              normalized,
            );
        saved = widget.note.copyWith(
          reminderAt: normalized,
          clearReminder: normalized == null,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(saved);
      _showReminderFeedback(
        context,
        ref,
        reminderAt != null,
        duplicated: widget.duplicateShared && reminderAt != null,
        messenger: messenger,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppInfoBar(
        context,
        messenger: messenger,
        message: ref.read(l10nProvider).t('reminderSaveFailed'),
        avoidMobileNavigation: true,
      );
    }
  }
}

void _showReminderPermissionRequired(
  BuildContext context,
  WidgetRef ref, {
  ScaffoldMessengerState? messenger,
}) {
  final l10n = ref.read(l10nProvider);
  showAppInfoBar(
    context,
    messenger: messenger,
    message: l10n.t('reminderPermissionRequired'),
    actionLabel: l10n.t('settings'),
    onAction: openReminderNotificationSettings,
    avoidMobileNavigation: true,
  );
}

void _showReminderFeedback(BuildContext context, WidgetRef ref, bool added,
    {bool duplicated = false, ScaffoldMessengerState? messenger}) {
  final l10n = ref.read(l10nProvider);
  showAppInfoBar(
    context,
    messenger: messenger,
    message: l10n.t(
      added
          ? duplicated
              ? 'reminderDuplicateAdded'
              : 'reminderAdded'
          : 'reminderRemoved',
    ),
    actionLabel: added ? l10n.t('view') : null,
    onAction: added
        ? () {
            ref.read(noteBucketProvider.notifier).state = 'reminders';
          }
        : null,
    avoidMobileNavigation: true,
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
  final reset = ref.read(_noteOverviewResetProvider.notifier);
  late final Future<void> route;
  if (wide) {
    route = showDialog<void>(
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
    ).then((_) {});
  } else {
    route = Navigator.of(context)
        .push(
          MaterialPageRoute<void>(builder: (_) => NoteEditorScreen(note: note)),
        )
        .then((_) {});
  }
  unawaited(route.whenComplete(() {
    reset.state++;
  }));
}

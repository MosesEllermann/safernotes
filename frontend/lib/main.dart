import 'dart:async';

import 'package:cupertino_native_better/cupertino_native_better.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/auth/auth_screen.dart';
import 'package:safernotes_app/features/notes/notes_screen.dart';
import 'package:safernotes_app/shared/app/app_preferences.dart';
import 'package:safernotes_app/shared/app/incoming_links.dart';
import 'package:safernotes_app/shared/theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: SafernotesApp()));
}

class SafernotesApp extends ConsumerStatefulWidget {
  const SafernotesApp({super.key, this.initialUri});

  final Uri? initialUri;

  @override
  ConsumerState<SafernotesApp> createState() => _SafernotesAppState();
}

class _SafernotesAppState extends ConsumerState<SafernotesApp> {
  StreamSubscription<Uri>? _linkSubscription;
  String? _invitationId;
  var _invitationRevision = 0;

  @override
  void initState() {
    super.initState();
    final initialUri = widget.initialUri ?? (kIsWeb ? Uri.base : null);
    _recordIncomingUri(initialUri, notify: false);

    final links = ref.read(incomingLinksProvider);
    _linkSubscription = links.stream.listen(_recordIncomingUri);
    if (widget.initialUri == null && !kIsWeb) {
      unawaited(_loadInitialNativeUri(links));
    }
  }

  Future<void> _loadInitialNativeUri(IncomingLinks links) async {
    final uri = await links.initialUri();
    if (mounted) _recordIncomingUri(uri);
  }

  void _recordIncomingUri(Uri? uri, {bool notify = true}) {
    if (uri == null) return;
    final invitationId = invitationIdFromUri(uri);
    if (invitationId == null) return;

    void update() {
      _invitationId = invitationId;
      _invitationRevision += 1;
    }

    if (notify && mounted) {
      setState(update);
    } else {
      update();
    }
  }

  @override
  void dispose() {
    unawaited(_linkSubscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(authControllerProvider);
    final preferences = ref.watch(appPreferencesProvider).valueOrNull;
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) {
        final platform = defaultTargetPlatform;
        return MaterialApp(
          title: 'Safernotes',
          debugShowCheckedModeBanner: false,
          navigatorObservers: [CNTabBarRouteObserver()],
          theme: buildAppTheme(
            Brightness.light,
            dynamicSeed: lightDynamic?.primary,
            useSystemFont: preferences?.useSystemFont ?? false,
            platform: platform,
          ),
          darkTheme: buildAppTheme(
            Brightness.dark,
            dynamicSeed: darkDynamic?.primary,
            useSystemFont: preferences?.useSystemFont ?? false,
            platform: platform,
          ),
          themeMode: preferences?.themeMode ?? ThemeMode.system,
          locale: Locale(preferences?.languageCode ?? 'en'),
          supportedLocales: const [Locale('en'), Locale('de')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            FlutterQuillLocalizations.delegate,
          ],
          home: session.when(
            data: (value) => value == null
                ? const AuthScreen()
                : NotesScreen(
                    invitationId: _invitationId,
                    invitationRevision: _invitationRevision,
                  ),
            loading: () => const _BootScreen(),
            error: (_, __) => const AuthScreen(),
          ),
        );
      },
    );
  }
}

String? invitationIdFromUri(Uri uri) {
  final isNativeAppLink = uri.scheme == 'safernotes' && uri.host == 'invite';
  final isCurrentWebLink =
      kIsWeb && (uri.scheme == 'https' || uri.scheme == 'http');
  final isWebRelativeLink = kIsWeb && uri.host.isEmpty;
  if (!isNativeAppLink && !isCurrentWebLink && !isWebRelativeLink) return null;
  final value = uri.queryParameters['invitation']?.trim();
  if (value == null || value.isEmpty) return null;
  final uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );
  return uuid.hasMatch(value) ? value.toLowerCase() : null;
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

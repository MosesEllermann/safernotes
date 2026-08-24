import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/features/auth/auth_screen.dart';
import 'package:safernotes_app/features/notes/notes_screen.dart';
import 'package:safernotes_app/shared/app/app_preferences.dart';
import 'package:safernotes_app/shared/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: SafernotesApp()));
}

class SafernotesApp extends ConsumerWidget {
  const SafernotesApp({super.key, this.initialUri});

  final Uri? initialUri;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider);
    final preferences = ref.watch(appPreferencesProvider).valueOrNull;
    final invitationId = invitationIdFromUri(initialUri ?? Uri.base);
    return MaterialApp(
      title: 'Safernotes',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: preferences?.themeMode ?? ThemeMode.system,
      locale: Locale(preferences?.languageCode ?? 'en'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        FlutterQuillLocalizations.delegate,
      ],
      home: session.when(
        data: (value) => value == null
            ? const AuthScreen()
            : NotesScreen(invitationId: invitationId),
        loading: () => const _BootScreen(),
        error: (_, __) => const AuthScreen(),
      ),
    );
  }
}

String? invitationIdFromUri(Uri uri) {
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

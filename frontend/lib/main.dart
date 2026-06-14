import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zknotes_app/features/auth/auth_controller.dart';
import 'package:zknotes_app/features/auth/auth_screen.dart';
import 'package:zknotes_app/features/notes/notes_screen.dart';
import 'package:zknotes_app/shared/app/app_preferences.dart';
import 'package:zknotes_app/shared/theme/app_theme.dart';

void main() {
  runApp(const ProviderScope(child: ZkNotesApp()));
}

class ZkNotesApp extends ConsumerWidget {
  const ZkNotesApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider);
    final preferences = ref.watch(appPreferencesProvider).valueOrNull;
    return MaterialApp(
      title: 'ZK Notes',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: preferences?.themeMode ?? ThemeMode.system,
      locale: Locale(preferences?.languageCode ?? 'en'),
      home: session.when(
        data: (value) =>
            value == null ? const AuthScreen() : const NotesScreen(),
        loading: () => const _BootScreen(),
        error: (_, __) => const AuthScreen(),
      ),
    );
  }
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

import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:safernotes_app/features/auth/auth_controller.dart';
import 'package:safernotes_app/shared/providers.dart';

final appPreferencesProvider =
    AsyncNotifierProvider<AppPreferencesController, AppPreferences>(
  AppPreferencesController.new,
);

enum NoteOverviewLayout { cards, list }

class AppPreferences {
  const AppPreferences({
    required this.languageCode,
    required this.themeMode,
    this.noteOverviewLayout = NoteOverviewLayout.cards,
    this.useSystemFont = false,
  });

  final String languageCode;
  final ThemeMode themeMode;
  final NoteOverviewLayout noteOverviewLayout;
  final bool useSystemFont;

  AppPreferences copyWith({
    String? languageCode,
    ThemeMode? themeMode,
    NoteOverviewLayout? noteOverviewLayout,
    bool? useSystemFont,
  }) {
    return AppPreferences(
      languageCode: languageCode ?? this.languageCode,
      themeMode: themeMode ?? this.themeMode,
      noteOverviewLayout: noteOverviewLayout ?? this.noteOverviewLayout,
      useSystemFont: useSystemFont ?? this.useSystemFont,
    );
  }
}

class AppPreferencesController extends AsyncNotifier<AppPreferences> {
  static const _languageKey = 'zk.pref.language';
  static const _themeKey = 'zk.pref.theme';
  static const _systemFontKey = 'zk.pref.system_font';
  static const _noteOverviewLayoutKey = 'zk.pref.note_overview_layout';

  @override
  Future<AppPreferences> build() async {
    final prefs = await SharedPreferences.getInstance();
    final language = prefs.getString(_languageKey) ?? _detectLanguage();
    final theme = prefs.getString(_themeKey) ?? 'system';
    final noteOverviewLayout =
        prefs.getString(_noteOverviewLayoutKey) ?? 'cards';
    return AppPreferences(
      languageCode: language,
      themeMode: _themeFromString(theme),
      useSystemFont: prefs.getBool(_systemFontKey) ?? false,
      noteOverviewLayout: noteOverviewLayout == 'list'
          ? NoteOverviewLayout.list
          : NoteOverviewLayout.cards,
    );
  }

  Future<void> setLanguage(String languageCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_languageKey, languageCode);
    state = AsyncData((state.valueOrNull ?? await build())
        .copyWith(languageCode: languageCode));
    unawaited(_syncLanguage(languageCode));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, _themeToString(mode));
    state = AsyncData(
        (state.valueOrNull ?? await build()).copyWith(themeMode: mode));
  }

  Future<void> setUseSystemFont(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_systemFontKey, enabled);
    state = AsyncData(
      (state.valueOrNull ?? await build()).copyWith(useSystemFont: enabled),
    );
  }

  Future<void> setNoteOverviewLayout(NoteOverviewLayout layout) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_noteOverviewLayoutKey, layout.name);
    state = AsyncData(
      (state.valueOrNull ?? await build()).copyWith(
        noteOverviewLayout: layout,
      ),
    );
  }

  String _detectLanguage() {
    final code = PlatformDispatcher.instance.locale.languageCode.toLowerCase();
    return code == 'de' ? 'de' : 'en';
  }

  ThemeMode _themeFromString(String value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  String _themeToString(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }

  Future<void> _syncLanguage(String languageCode) async {
    final session = ref.read(authControllerProvider).valueOrNull;
    if (session == null || session.isOfflineOnly) return;
    try {
      await ref.read(apiClientProvider).updatePreferences(
            accessToken: session.accessToken,
            locale: languageCode,
          );
    } catch (_) {
      // Local preferences should keep working while the app is offline.
    }
  }
}

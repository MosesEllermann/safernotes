import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zknotes_app/shared/app/app_preferences.dart';

final l10nProvider = Provider<AppL10n>((ref) {
  final prefs = ref.watch(appPreferencesProvider).valueOrNull;
  return AppL10n(prefs?.languageCode ?? 'en');
});

class AppL10n {
  const AppL10n(this.languageCode);

  final String languageCode;

  static AppL10n of(BuildContext context, WidgetRef ref) =>
      ref.watch(l10nProvider);

  String t(String key) {
    return (_strings[languageCode] ?? _strings['en']!)[key] ??
        _strings['en']![key] ??
        key;
  }
}

const _strings = {
  'en': {
    'appName': 'ZK Notes',
    'welcomeBack': 'Welcome back',
    'createVault': 'Create your vault',
    'login': 'Login',
    'register': 'Register',
    'email': 'Email',
    'password': 'Password',
    'workspace': 'Workspace name',
    'createAccount': 'Create account',
    'showPassword': 'Show password',
    'hidePassword': 'Hide password',
    'invalidEmail': 'Enter a valid email',
    'passwordMin': 'Use at least 8 characters',
    'enterPassword': 'Enter your password',
    'nameWorkspace': 'Name your workspace',
    'serverUnreachable': 'The server is not reachable.',
    'badCredentials': 'Email or password is incorrect.',
    'newNote': 'New note',
    'editNote': 'Edit note',
    'notes': 'Notes',
    'noNotes': 'No notes yet',
    'createNote': 'Create note',
    'title': 'Title',
    'writeNote': 'Write your note',
    'saved': 'Saved',
    'saving': 'Saving',
    'syncing': 'Syncing',
    'offline': 'Offline',
    'conflict': 'Conflict',
    'settings': 'Settings',
    'appearance': 'Appearance',
    'language': 'Language',
    'system': 'System',
    'light': 'Light',
    'dark': 'Dark',
    'english': 'English',
    'german': 'German',
    'logout': 'Logout',
    'share': 'Share',
    'invite': 'Invite',
    'recipientId': 'Recipient user ID',
    'role': 'Role',
    'owner': 'Owner',
    'editor': 'Editor',
    'viewer': 'Viewer',
    'presence': 'Presence',
    'checklist': 'Checklist',
    'addTask': 'Add task',
    'task': 'Task',
    'pin': 'Pin',
    'unpin': 'Unpin',
    'close': 'Close',
    'clearFormatting': 'Clear formatting',
    'link': 'Link',
  },
  'de': {
    'appName': 'ZK Notizen',
    'welcomeBack': 'Willkommen zurueck',
    'createVault': 'Tresor erstellen',
    'login': 'Anmelden',
    'register': 'Registrieren',
    'email': 'E-Mail',
    'password': 'Passwort',
    'workspace': 'Arbeitsbereich',
    'createAccount': 'Konto erstellen',
    'showPassword': 'Passwort anzeigen',
    'hidePassword': 'Passwort verbergen',
    'invalidEmail': 'Gib eine gueltige E-Mail ein',
    'passwordMin': 'Mindestens 8 Zeichen verwenden',
    'enterPassword': 'Gib dein Passwort ein',
    'nameWorkspace': 'Benenne deinen Arbeitsbereich',
    'serverUnreachable': 'Der Server ist nicht erreichbar.',
    'badCredentials': 'E-Mail oder Passwort ist falsch.',
    'newNote': 'Neue Notiz',
    'editNote': 'Notiz bearbeiten',
    'notes': 'Notizen',
    'noNotes': 'Noch keine Notizen',
    'createNote': 'Notiz erstellen',
    'title': 'Titel',
    'writeNote': 'Schreibe deine Notiz',
    'saved': 'Gespeichert',
    'saving': 'Speichert',
    'syncing': 'Synchronisiert',
    'offline': 'Offline',
    'conflict': 'Konflikt',
    'settings': 'Einstellungen',
    'appearance': 'Darstellung',
    'language': 'Sprache',
    'system': 'System',
    'light': 'Hell',
    'dark': 'Dunkel',
    'english': 'Englisch',
    'german': 'Deutsch',
    'logout': 'Abmelden',
    'share': 'Teilen',
    'invite': 'Einladen',
    'recipientId': 'Empfaenger-ID',
    'role': 'Rolle',
    'owner': 'Owner',
    'editor': 'Editor',
    'viewer': 'Viewer',
    'presence': 'Praesenz',
    'checklist': 'Checkliste',
    'addTask': 'Aufgabe hinzufuegen',
    'task': 'Aufgabe',
    'pin': 'Anheften',
    'unpin': 'Loesen',
    'close': 'Schliessen',
    'clearFormatting': 'Formatierung loeschen',
    'link': 'Link',
  },
};

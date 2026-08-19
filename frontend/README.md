# Safernotes prototype app

This is the first user-facing Flutter app for web, Android, and iOS.

## What is included

- Register and login screens.
- Client-side key wrapper for account creation and login unlock.
- Local encrypted note cache for offline use.
- Responsive master-detail notes workspace for desktop and modal/mobile editing.
- Create and edit encrypted notes with autosave.
- Automatic sync through the backend batch endpoint with saved/syncing/offline/conflict state.
- Background polling for near-real-time updates and presence refresh.
- Sharing UI for owner-created editor/viewer invitations.
- English and German UI strings with persisted language preference.
- Light, dark, and system appearance modes.
- Markdown-style rich text toolbar and keyboard shortcuts.
- Reorderable nested checklist items stored inside encrypted note payloads.

## Run locally

Install Flutter first, then run:

```sh
cd frontend
flutter create --project-name safernotes_app --platforms=web,android,ios .
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

For Android emulator:

```sh
flutter run -d android --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

For iOS simulator:

```sh
flutter run -d ios --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

The backend must be running on the matching API URL before registering or logging in.

This workspace also includes helper scripts that use the writable Flutter SDK copy
prepared at `/Users/moses/Documents/Codex/flutter-sdk`:

```sh
cd /Users/moses/Documents/Codex/2026-06-09/files-mentioned-by-the-user-eingef-2/frontend
./tool/run_web.sh
```

Then open `http://localhost:3000`.

In a second terminal, start the backend:

```sh
cd /Users/moses/Documents/Codex/2026-06-09/files-mentioned-by-the-user-eingef-2/backend
../.venv/bin/python manage.py runserver 127.0.0.1:8000 --noreload
```

## Crypto note

The crypto wrapper uses AES-256-GCM and client-held key material. New password
key wrapping uses Argon2id; older PBKDF2-SHA256 wrapped test accounts can still
be unlocked for compatibility.

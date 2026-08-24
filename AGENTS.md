# Agent Context

This repository is a zero-knowledge encrypted notes product with a Django backend and a Flutter client.

## Product Shape

- Backend: `backend/`, Django REST API, encrypted payload boundary.
- Frontend: `frontend/`, Flutter app for web, Android, and iOS.
- Local docs and phase summaries: `outputs/`.
- Infrastructure starters: `docker-compose.yml`, `infra/`.

## Current Frontend Direction

The UI is a modern sticky-note app inspired by Google Keep and Animate UI/Lucide-style motion:

- Small animated icon controls live in `frontend/lib/shared/widgets/animated_icon_button.dart`.
- Main notes surface lives in `frontend/lib/features/notes/notes_screen.dart`.
- Editor lives in `frontend/lib/features/notes/note_editor_screen.dart`.
- Notes support active/archive/trash/deleted buckets.
- Notes can be text notes or checklist notes; checklist mode replaces the body editor.
- Formatting is Markdown-style with inline preview in editor and card previews.

## Security Boundary

Do not send plaintext note title/body/checklist data to backend note fields. The backend accepts encrypted envelopes for user content. Client-side note data is encrypted in `CryptoService` before sync.

## Commands

Start from `docs/START_HERE.md` when entering this repo without prior thread context.

Backend checks:

```sh
cd backend
../.venv/bin/python manage.py check
../.venv/bin/python manage.py makemigrations --check --dry-run
../.venv/bin/python -m pytest -q
```

Frontend checks:

```sh
cd frontend
./tool/flutterw analyze
./tool/flutterw build web --dart-define=API_BASE_URL=https://api.safernotes.com --no-wasm-dry-run
./tool/build_android_release.sh
```

Flutter widget tests may fail inside restricted sandboxes because Flutter opens a temporary localhost socket.

## Important Caveats

- Default app builds must use the online API `https://api.safernotes.com`. Local API URLs are only for deliberate debugging and must not be used for release APKs.
- New password-derived key wrapping uses Argon2id. The client keeps PBKDF2-SHA256 unlock support for older test accounts.
- Near-real-time collaboration is currently autosave plus polling/presence refresh. The backend has encrypted WebSocket collaboration primitives, but the Flutter client does not yet use a CRDT/WebSocket editor.
- Share invitations require recipient user IDs in the current UI.

# Start Here

This is the project root:

```sh
/Users/moses/Documents/Codex/2026-06-09/files-mentioned-by-the-user-eingef-2
```

Open this exact folder as the workspace in Codex, GitHub Desktop, VS Code, or a terminal.

## What This Project Is

Safernotes is a zero-knowledge encrypted notes prototype:

- `backend/`: Django REST API.
- `frontend/`: Flutter app for web, Android, and iOS.
- `docs/`: development notes and project context.
- `AGENTS.md`: compact context for future Codex sessions.

The backend must not receive plaintext note content. The Flutter client encrypts user-facing note data before syncing.

## Start The App

Terminal 1:

```sh
cd /Users/moses/Documents/Codex/2026-06-09/files-mentioned-by-the-user-eingef-2/backend
../.venv/bin/python manage.py migrate
../.venv/bin/python manage.py runserver 127.0.0.1:8000 --noreload
```

Terminal 2:

```sh
cd /Users/moses/Documents/Codex/2026-06-09/files-mentioned-by-the-user-eingef-2/frontend
./tool/run_web.sh
```

Open:

```sh
http://localhost:3000
```

By default, the Flutter app uses the online API:

```sh
https://api.safernotes.com
```

Use `API_BASE_URL=http://127.0.0.1:8000 ./tool/run_web.sh` only when intentionally testing a local backend.

The Flutter wrapper prefers `/Users/moses/Dev/flutter/bin/flutter` when it exists.

## Full Access In A New Codex Session

If Codex cannot start local servers or write outside the current folder, start a new Codex session and choose this project folder as the workspace:

```sh
/Users/moses/Documents/Codex/2026-06-09/files-mentioned-by-the-user-eingef-2
```

Then grant the broader/local permissions requested by Codex. The current project is already arranged as a normal repo, so no nested folder is needed.

## Quality Checks

Backend:

```sh
cd backend
../.venv/bin/python manage.py check
../.venv/bin/python manage.py makemigrations --check --dry-run
../.venv/bin/python -m pytest -q
```

Frontend:

```sh
cd frontend
./tool/flutterw analyze
./tool/flutterw build web --dart-define=API_BASE_URL=https://api.safernotes.com --no-wasm-dry-run
./tool/build_android_release.sh
```

The Android helper produces the Play Store bundle at
`frontend/build/app/outputs/bundle/release/app-release.aab` once upload signing
is configured in `frontend/android/key.properties`.

## GitHub Desktop

In GitHub Desktop, use:

```sh
File > Add Local Repository
```

Select the project root shown at the top of this file. Do not select `frontend/` or `backend/` separately.

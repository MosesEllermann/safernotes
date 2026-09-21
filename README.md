# Safernotes

Safernotes is a zero-knowledge encrypted notes app with a Flutter client for web, Android, and iOS. It can run as a completely local offline vault or synchronize through a self-hosted Django server.

The backend stores encrypted envelopes for user-facing content. The frontend owns encryption, local offline storage, note editing, checklist mode, autosync, archive/trash views, language/theme settings, and the current sticky-note UI.

## Repository Layout

- `backend/`: Django REST API.
- `frontend/`: Flutter app.
- `docs/`: development notes, project context, roadmap.
- `infra/`: Kubernetes/Helm starter manifests.
- `.github/workflows/`: CI workflows.
- `AGENTS.md`: compact context for future Codex/AI work.

## Choose a mode

### Offline-only

Run the Flutter app and choose **Use offline only**. No account is created and the app does not contact an API. Notes remain encrypted in local device storage.

### Self-host with Docker

```sh
cp .env.selfhost.example .env
docker compose up --build -d
```

Open `http://localhost:8080`. See [the self-hosting guide](docs/SELF_HOSTING.md) before exposing the stack publicly.

## Run for development

Terminal 1:

```sh
cd backend
../.venv/bin/python manage.py migrate
../.venv/bin/python manage.py runserver 127.0.0.1:8000 --noreload
```

Terminal 2:

```sh
cd frontend
./tool/run_web.sh
```

Open `http://localhost:3000`.

The helper uses `http://127.0.0.1:8000` by default. Docker web builds use a same-origin API proxy and contain no vendor-hosted API address.

## Checks

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
./tool/flutterw build web --dart-define=API_BASE_URL=http://127.0.0.1:8000 --no-wasm-dry-run
./tool/build_android_release.sh
```

`frontend/tool/build_android_release.sh` builds the Play Store Android App
Bundle at `frontend/build/app/outputs/bundle/release/app-release.aab` and
requires `frontend/android/key.properties` for upload signing. Native users can
enter their own self-hosted URL on the sign-in screen or under Settings. Set
`API_BASE_URL=https://notes.example.com` only if a distributor wants to prefill
a default; without it, the app has no default sync service.
Run `frontend/tool/generate_android_upload_key.sh` once to create the local
upload key and signing properties.

## Security Boundary

Do not submit plaintext note titles, bodies, checklist items, labels, attachment metadata, or notification payloads to backend note fields. User-facing note content must be encrypted locally and submitted as versioned encrypted envelopes.

## More Context

- [Start here](docs/START_HERE.md)
- [Project context](docs/PROJECT_CONTEXT.md)
- [Development guide](docs/DEVELOPMENT.md)
- [Self-hosting guide](docs/SELF_HOSTING.md)
- [Roadmap](docs/ROADMAP.md)

## Repository Note

This project folder is prepared for GitHub Desktop and can be published as one repository.

## Open-source license

Safernotes is free and open-source software licensed under
[AGPL-3.0-or-later](LICENSE). You may use, inspect, modify, and self-host it;
redistributed versions and modified versions offered over a network must make
their corresponding source available under the same license.

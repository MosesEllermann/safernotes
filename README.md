# Safernotes

Safernotes is a zero-knowledge encrypted notes prototype with a Django backend and a Flutter client for web, Android, and iOS.

The backend stores encrypted envelopes for user-facing content. The frontend owns encryption, local offline storage, note editing, checklist mode, autosync, archive/trash views, language/theme settings, and the current sticky-note UI.

## Repository Layout

- `backend/`: Django REST API.
- `frontend/`: Flutter app.
- `docs/`: development notes, project context, roadmap.
- `outputs/`: phase-by-phase implementation summaries.
- `infra/`: Kubernetes/Helm starter manifests.
- `.github/workflows/`: CI workflows.
- `AGENTS.md`: compact context for future Codex/AI work.

## Run Locally

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
```

## Security Boundary

Do not submit plaintext note titles, bodies, checklist items, labels, attachment metadata, or notification payloads to backend note fields. User-facing note content must be encrypted locally and submitted as versioned encrypted envelopes.

## More Context

- [Start here](docs/START_HERE.md)
- [Project context](docs/PROJECT_CONTEXT.md)
- [Development guide](docs/DEVELOPMENT.md)
- [Deployment guide](docs/DEPLOYMENT.md)
- [Roadmap](docs/ROADMAP.md)

## Repository Note

This project folder is prepared for GitHub Desktop and can be published as one repository.

# Development

## Backend

Create/install the Python environment, then:

```sh
cd backend
../.venv/bin/python manage.py migrate
../.venv/bin/python manage.py runserver 127.0.0.1:8000 --noreload
```

Checks:

```sh
cd backend
../.venv/bin/python manage.py check
../.venv/bin/python manage.py makemigrations --check --dry-run
../.venv/bin/python -m pytest -q
```

## Frontend

Install Flutter, then:

```sh
cd frontend
flutter pub get
flutter run -d web-server --web-hostname=localhost --web-port=3000 --dart-define=API_BASE_URL=https://api.safernotes.com
```

This repo also has a helper:

```sh
cd frontend
./tool/run_web.sh
```

The helper defaults to `https://api.safernotes.com`. Use `API_BASE_URL=http://127.0.0.1:8000 ./tool/run_web.sh` only when intentionally testing a local backend.

Checks:

```sh
cd frontend
./tool/flutterw analyze
./tool/flutterw build web --dart-define=API_BASE_URL=https://api.safernotes.com --no-wasm-dry-run
./tool/build_android_release.sh
```

The Android release helper builds
`build/app/outputs/bundle/release/app-release.aab` for Google Play. It requires
an untracked `android/key.properties` file based on
`android/key.properties.example`. Run `./tool/generate_android_upload_key.sh`
once to create the local upload key interactively.

## GitHub Push

From the repository root:

```sh
git init
git add .
git commit -m "Initial Safernotes prototype"
git branch -M main
git remote add origin git@github.com:YOUR_USER/YOUR_REPO.git
git push -u origin main
```

Use HTTPS instead of SSH if you prefer:

```sh
git remote add origin https://github.com/YOUR_USER/YOUR_REPO.git
```

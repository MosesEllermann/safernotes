# Development

## Backend

Create the Python environment from the repository root:

```sh
python3 -m venv .venv
.venv/bin/pip install -e './backend[dev]'
```

Start the backend:

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
flutter run -d web-server --web-hostname=localhost --web-port=3000 --dart-define=API_BASE_URL=http://127.0.0.1:8000
```

This repo also has a helper:

```sh
cd frontend
./tool/run_web.sh
```

The helper defaults to the local Django server at `http://127.0.0.1:8000`.

Checks:

```sh
cd frontend
./tool/flutterw analyze
./tool/flutterw build web --dart-define=API_BASE_URL=same-origin --no-wasm-dry-run
./tool/build_android_release.sh
```

The Android release helper builds
`build/app/outputs/bundle/release/app-release.aab` for Google Play. It requires
your own signing properties based on `android/key.properties.example`.
Run `./tool/generate_android_upload_key.sh` once to create the upload key
interactively outside the checkout, then set `SAFERNOTES_SIGNING_PROPERTIES`
to the generated properties path.

Alternatively, keep signing material outside the checkout and set
`SAFERNOTES_SIGNING_PROPERTIES` to an absolute path to `key.properties`.
Its `storeFile` path is relative to that file.

Development settings generate a temporary signing secret if `SECRET_KEY` is
unset. Set your own persistent secret for sessions that must survive restarts.

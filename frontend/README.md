# Safernotes client

Flutter client for Android, iOS and web. Supports encrypted offline storage,
optional self-hosted sync, text notes, checklists, reminders and sharing.

## Development

Install Flutter and add it to `PATH`, or set `FLUTTER_SDK` to your SDK directory.
From this directory:

```sh
./tool/flutterw pub get
./tool/run_web.sh
```

The web development helper connects to `http://127.0.0.1:8000`.
See [the development guide](../docs/DEVELOPMENT.md) for the backend setup.
The Android emulator can use `http://10.0.2.2:8000` for a local development
server. Native release builds have no default server; enter your installation's
HTTPS URL in the app, or select **Use offline only**.

## Checks and builds

```sh
./tool/flutterw analyze
./tool/flutterw test
./tool/flutterw build web --dart-define=API_BASE_URL=same-origin --no-wasm-dry-run
./tool/flutterw build apk --debug
```

For an Android release, supply your own signing configuration using
`SAFERNOTES_SIGNING_PROPERTIES=/absolute/path/to/key.properties` and run
`./tool/build_android_release.sh`. The `storeFile` entry is resolved relative
to the configuration file. Keep signing material outside the source checkout.

The existing application ID is retained for compatibility with installed apps.
Use your own application ID and signing key when distributing an independent fork.

## Storage and encryption

User content is encrypted on the client before synchronization. Offline vaults
are device-local and currently do not support automatic migration to a server
vault. Never include device storage, account credentials or note exports in
source distributions.

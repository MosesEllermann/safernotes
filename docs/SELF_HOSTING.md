# Self-hosting Safernotes

Safernotes supports two independent modes:

- **Offline-only** stores the encrypted vault on one device and never contacts an API.
- **Self-hosted sync** uses the Flutter web client with the Django API, PostgreSQL, Redis, and MinIO from this repository.

## Local Docker deployment

Requirements: Python 3, Docker Engine with Docker Compose v2.

The bundled MinIO server and bucket initializer use digest-pinned images from
`quay.io/minio`, not the unavailable Docker Hub repositories. No registry login
is required. These are legacy images from the archived MinIO community project;
the registry change fixes installation, not upstream maintenance. Keep storage
internal and plan a maintained storage replacement for long-term operation.

```sh
python3 tools/init_selfhost.py
docker compose up --build -d
```

Open `http://localhost:8080`. The web container serves the Flutter app and proxies `/api` and `/ws` to Django, so the client does not contain a hosted Safernotes API address. Database migrations and the encrypted attachment bucket are created automatically.

When upgrading an older prototype database, migration `tenants.0003` removes
the legacy tenant plan column and permanently drops the old billing and
subscription tables. Back up the database first if those historical records
must be retained outside Safernotes.

Useful endpoints:

- App: `http://localhost:8080`
- API health: `http://localhost:8080/api/v1/health/live`

## Before public access

For a new installation, provide just one public URL:

```sh
python3 tools/init_selfhost.py --url https://notes.example.com
docker compose up --build -d
```

The initializer saves `PUBLIC_URL` and three independent, random internal secrets
in a private `.env` (mode 0600). It never overwrites an existing file. No external
API account or manually invented password is needed. Preserve this file across
updates and include it in a private backup.

Point your domain to your server and configure your HTTPS reverse proxy to forward
to the web service on port 8080 (or `SAFERNOTES_WEB_PORT`). If the proxy runs on the
same host, you can bind the web port to loopback with
`SAFERNOTES_WEB_PORT=127.0.0.1:8080`. Forward the original Host and set
`X-Forwarded-Proto: https`; do not allow untrusted direct access around the proxy.
Only the web service publishes a port. The API, PostgreSQL, Redis, MinIO S3 endpoint
and MinIO console are internal. No separate storage domain, port or certificate is needed.

The backend derives allowed hosts, browser origins and email link addresses from
`PUBLIC_URL`. Attachments use short-lived, permission-checked links under the same
URL; the backend transfers encrypted bytes to/from MinIO. MinIO uses the included
`minio_data` Docker volume, not an external cloud account. A transfer is limited to
100 MiB; configure the outer proxy to allow that request size and sufficient time.
Treat signed attachment links as credentials: do not log their query strings in
your outer proxy. The bundled web server omits queries from access logs.

Back up PostgreSQL, MinIO and `.env`. Configure `EMAIL_*` in `.env` only if verification
and recovery emails should leave the server; by default email is written to private
container logs. SMTP is not required to start the stack.

### Upgrading an existing installation

Keep your existing `.env` and all three secrets. Add
`PUBLIC_URL=https://notes.example.com`, and for the included MinIO change the old
`ATTACHMENT_ENDPOINT_URL` to `http://minio:9000`. Old `ALLOWED_HOSTS`,
`CORS_ALLOWED_ORIGINS`, `APP_BASE_URL`, `WEBSITE_BASE_URL` and `SAFERNOTES_API_PORT`
entries are no longer needed by Compose. Run `docker compose up --build -d`.
Existing bucket names, volumes, encrypted data and credentials remain unchanged.
Previously issued attachment links should be requested again after the update.

For an existing database, set `POSTGRES_PASSWORD` to its current password first.
Changing this environment variable does not rotate a password stored in an
existing PostgreSQL volume. Back up data and rotate the database role password
deliberately; do not delete volumes to make an update start.

### Optional: external S3 storage

The default needs no storage configuration. Advanced installations may set
`ATTACHMENT_ENDPOINT_URL` to their server-reachable S3 HTTPS endpoint,
`ATTACHMENT_BUCKET` to an existing private bucket, `ATTACHMENT_REGION`,
`ATTACHMENT_ACCESS_KEY_ID` and `ATTACHMENT_SECRET_ACCESS_KEY`. Use bucket-scoped
credentials permitting object reads and writes, not an administrator account.
The external bucket must be provisioned separately; the bundled initializer only
creates the local MinIO bucket. Clients still use `PUBLIC_URL`, so the external
endpoint does not require browser CORS rules or direct client access. Changing
storage endpoints does not migrate existing objects; copy and verify them first.

The backend stores encrypted note envelopes. Plaintext note titles, bodies, checklist items, labels, and attachment contents remain client-side.

## Offline-only mode

Choose **Use offline only** on the first screen. This creates a random local vault key, stores the encrypted session material in platform secure storage, disables sync timers and all API calls, and hides server-only sharing and account-security controls.

Native Android and iOS builds have no default server. Enter your installation URL on the sign-in screen, for example `https://notes.example.com`. The URL is stored locally on that device and can be changed later under **Settings → Sync server**. Web builds served by Docker always use their own origin.

Offline-only data is tied to the current browser profile or device. Clearing app/browser storage or uninstalling the app can permanently remove it. Export/import and migration from offline-only to a server vault are separate roadmap items and should be completed before calling offline-only mode backup-safe.

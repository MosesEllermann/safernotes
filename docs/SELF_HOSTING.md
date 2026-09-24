# Self-hosting Safernotes

Safernotes supports two independent modes:

- **Offline-only** stores the encrypted vault on one device and never contacts an API.
- **Self-hosted sync** uses the Flutter web client with the Django API, PostgreSQL and Redis. Encrypted attachments live in a private Docker volume on your server.

## Local Docker deployment

Requirements: Python 3, Docker Engine with Docker Compose v2.

No separate storage service, storage account, access key or storage URL is needed.
Docker creates the persistent `attachment_data` volume automatically and mounts
it only into the API at `/var/lib/safernotes/attachments`.

```sh
python3 tools/init_selfhost.py
docker compose up --build -d
```

Open `http://localhost:8080`. The web container serves the Flutter app and proxies `/api` and `/ws` to Django, so the client does not contain a hosted Safernotes API address. Database migrations run automatically. On Linux, prefix Docker commands with `sudo` if your account cannot access the Docker socket; run the Python initializer as your regular user.

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

The initializer saves `PUBLIC_URL` and two independent, random internal secrets
in a private `.env` (mode 0600). It never overwrites an existing file. No external
API account or manually invented password is needed. Preserve this file across
updates and include it in a private backup.

Point your domain to your server and configure your HTTPS reverse proxy to forward
to the web service on port 8080 (or `SAFERNOTES_WEB_PORT`). If the proxy runs on the
same host, you can bind the web port to loopback with
`SAFERNOTES_WEB_PORT=127.0.0.1:8080`. Forward the original Host and set
`X-Forwarded-Proto: https`; do not allow untrusted direct access around the proxy.
Only the web service publishes a port. The API, PostgreSQL and Redis are internal.
No separate storage domain, port or certificate is needed.

The backend derives allowed hosts, browser origins and email link addresses from
`PUBLIC_URL`. Attachments use short-lived, permission-checked links under the same
URL; the backend reads and writes ciphertext in the `attachment_data` volume.
Files are not served publicly as static or media files. A transfer is limited to
100 MiB; configure the outer proxy to allow that request size and sufficient time.
Treat signed attachment links as credentials: do not log their query strings in
your outer proxy. The bundled web server omits queries from access logs.

Back up PostgreSQL, `attachment_data` and `.env` together. Stop the API while taking
the database and attachment backups so they describe the same state. Restore both
volumes and the original secrets together, preserving file permissions, and test
restores separately. Never use `docker compose down -v` to perform an update:
it deletes persistent data. Configure `EMAIL_*` in `.env` only if verification
and recovery emails should leave the server; by default email is written to private
container logs. SMTP is not required to start the stack.

### Upgrading an existing installation

Keep your existing `.env`, `SECRET_KEY` and `POSTGRES_PASSWORD`. Set
`PUBLIC_URL=https://notes.example.com`. Old `ALLOWED_HOSTS`,
`CORS_ALLOWED_ORIGINS`, `APP_BASE_URL`, `WEBSITE_BASE_URL` and `SAFERNOTES_API_PORT`
entries are no longer needed by Compose. Run `docker compose up --build -d`.
Database and attachment volumes survive container rebuilds. Obsolete storage
credentials in an existing `.env` are ignored and are no longer generated or passed
to containers. There is no external object-storage integration.
Previously issued attachment links should be requested again after the update.

**Older installations with attachments:** the former MinIO/S3 storage is no longer
used. Existing objects are **not automatically migrated**. Back up and export the
actual ciphertext objects with their original logical keys before changing the
old deployment; do not mount its raw data directory as `attachment_data`. Import
each exported object's bytes through `apps.attachments.storage.write_ciphertext`
using the unchanged `Attachment.object_key`, and verify length and SHA-256 against
the database. Retain the original database, credentials and storage until downloads
have been verified. If installation previously failed before any uploads, there
are no attachments to migrate and no reset is needed.

For an existing database, set `POSTGRES_PASSWORD` to its current password first.
Changing this environment variable does not rotate a password stored in an
existing PostgreSQL volume. Back up data and rotate the database role password
deliberately; do not delete volumes to make an update start.

The backend stores encrypted note envelopes. Plaintext note titles, bodies, checklist items, labels, and attachment contents remain client-side.

## Offline-only mode

Choose **Use offline only** on the first screen. This creates a random local vault key, stores the encrypted session material in platform secure storage, disables sync timers and all API calls, and hides server-only sharing and account-security controls.

Native Android and iOS builds have no default server. Enter your installation URL on the sign-in screen, for example `https://notes.example.com`. The URL is stored locally on that device and can be changed later under **Settings → Sync server**. Web builds served by Docker always use their own origin.

Offline-only data is tied to the current browser profile or device. Clearing app/browser storage or uninstalling the app can permanently remove it. Export/import and migration from offline-only to a server vault are separate roadmap items and should be completed before calling offline-only mode backup-safe.

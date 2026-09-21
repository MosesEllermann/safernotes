# Self-hosting Safernotes

Safernotes supports two independent modes:

- **Offline-only** stores the encrypted vault on one device and never contacts an API.
- **Self-hosted sync** uses the Flutter web client with the Django API, PostgreSQL, Redis, and MinIO from this repository.

## Local Docker deployment

Requirements: Docker Engine with Docker Compose v2.

```sh
cp .env.selfhost.example .env
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
- MinIO S3 endpoint: `http://localhost:9000`
- MinIO console: `http://localhost:9001`

## Before public access

At minimum:

1. Replace `SECRET_KEY` and `MINIO_ROOT_PASSWORD` in `.env`.
2. Set `ALLOWED_HOSTS`, `CORS_ALLOWED_ORIGINS`, `APP_BASE_URL`, and `WEBSITE_BASE_URL` to your domain.
3. Set `ATTACHMENT_ENDPOINT_URL` to the browser-reachable HTTPS MinIO/S3 endpoint.
4. Put the web service and object storage behind a TLS reverse proxy.
5. Back up the PostgreSQL and MinIO volumes.
6. Configure the `EMAIL_*` values in `.env` if registration verification and recovery email should leave the server. The default writes email to container logs.

The backend stores encrypted note envelopes. Plaintext note titles, bodies, checklist items, labels, and attachment contents remain client-side.

## Offline-only mode

Choose **Use offline only** on the first screen. This creates a random local vault key, stores the encrypted session material in platform secure storage, disables sync timers and all API calls, and hides server-only sharing and account-security controls.

Native Android and iOS builds have no default server. Enter your installation URL on the sign-in screen, for example `https://notes.example.com`. The URL is stored locally on that device and can be changed later under **Settings → Sync server**. Web builds served by Docker always use their own origin.

Offline-only data is tied to the current browser profile or device. Clearing app/browser storage or uninstalling the app can permanently remove it. Export/import and migration from offline-only to a server vault are separate roadmap items and should be completed before calling offline-only mode backup-safe.

# Production launch runbook

## 1. Paddle sandbox

Create these Paddle catalog entries:

- Essential yearly: 18 EUR per year
- Pro yearly: 60 EUR per year
- Team yearly: 150 EUR per year per workspace

Required backend environment:

```env
BILLING_PROVIDER=paddle
BILLING_API_KEY=pdl_sdbx_apikey_...
BILLING_API_BASE_URL=https://sandbox-api.paddle.com
BILLING_PRICE_IDS={"essential":"pri_...","pro":"pri_...","team":"pri_..."}
BILLING_WEBHOOK_SECRET=...
```

Configure Paddle webhook destination:

```text
https://api.example.com/api/v1/billing/webhook
```

Subscribe at least to:

- `subscription.created`
- `subscription.activated`
- `subscription.updated`
- `subscription.canceled`
- `subscription.paused`

Sandbox acceptance test:

1. Create a test user.
2. Start Essential checkout from the app.
3. Complete the Paddle sandbox payment.
4. Confirm the tenant plan changes from `free` to `essential`.
5. Cancel the sandbox subscription in Paddle.
6. Confirm the tenant plan returns to `free`.

## 2. Hosting

Minimum production components:

- Django API
- Postgres
- Redis
- HTTPS domain
- daily database backups
- health checks at `/api/v1/health/live` and `/api/v1/health/ready`

Required backend environment:

```env
DEBUG=false
SECRET_KEY=...
ALLOWED_HOSTS=api.example.com
DATABASE_URL=postgres://...
REDIS_URL=redis://...
CORS_ALLOWED_ORIGINS=https://app.example.com
```

## 3. Email

Use a transactional email provider and configure:

- SPF
- DKIM
- DMARC
- verified sender domain

Required backend environment:

```env
EMAIL_BACKEND=django.core.mail.backends.smtp.EmailBackend
EMAIL_HOST=smtp.protonmail.ch
EMAIL_PORT=587
EMAIL_HOST_USER=noreply@safernotes.com
EMAIL_HOST_PASSWORD=<proton-smtp-token>
EMAIL_USE_TLS=True
EMAIL_USE_SSL=False
DEFAULT_FROM_EMAIL=Safernotes <noreply@safernotes.com>
```

## 4. Legal and GDPR

Before live payments:

- Impressum
- privacy policy
- terms of service
- processor list
- data processing agreements for hosting, email, and Paddle
- support contact

Privacy policy must state that note content is encrypted client-side and not sent to Paddle.

## 5. Release gate

Run before production deploy:

```sh
cd backend
../.venv/bin/python manage.py check
../.venv/bin/python manage.py check --deploy
../.venv/bin/python manage.py makemigrations --check --dry-run
../.venv/bin/python -m pytest -q

cd ../frontend
./tool/flutterw analyze
./tool/flutterw build web --dart-define=API_BASE_URL=https://api.safernotes.com --no-wasm-dry-run
./tool/build_android_release.sh
```

Upload `frontend/build/app/outputs/bundle/release/app-release.aab` to Google
Play. The bundle must be signed with the upload key configured in the untracked
`frontend/android/key.properties` file. Generate it once with
`frontend/tool/generate_android_upload_key.sh`, then back up the keystore and
passwords securely.

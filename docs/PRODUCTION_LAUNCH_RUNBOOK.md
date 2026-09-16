# Production launch runbook

## 1. Creem Test Mode

Create these recurring SaaS products in the Creem Test Mode catalog:

- Essential yearly: 18 EUR per year
- Pro yearly: 60 EUR per year

Required backend environment:

```env
BILLING_PROVIDER=creem
BILLING_API_KEY=creem_test_...
BILLING_API_BASE_URL=https://test-api.creem.io/v1
BILLING_PRODUCT_IDS={"essential":"prod_...","pro":"prod_..."}
BILLING_SUCCESS_URL=https://app.safernotes.com/?billing=success
BILLING_WEBHOOK_SECRET=...
```

Configure the Creem Test Mode webhook destination:

```text
https://api.example.com/api/v1/billing/webhook
```

Subscribe at least to:

- `checkout.completed`
- `subscription.active`
- `subscription.paid`
- `subscription.update`
- `subscription.scheduled_cancel`
- `subscription.past_due`
- `subscription.unpaid`
- `subscription.canceled`
- `subscription.expired`
- `subscription.paused`
- `subscription.trialing`
- `refund.created`
- `dispute.created`

Test Mode acceptance test:

1. Create a test user.
2. Start Essential checkout from the app.
3. Complete the Creem Test Mode payment with a Creem test card.
4. Confirm the tenant plan changes from `free` to `essential`.
5. Confirm the Creem receipt email contains customer invoice and portal access.
6. Open the portal from the API and confirm subscription management works.
7. Schedule cancellation and confirm access remains active through the paid period.
8. Send an expiry event and confirm access remains active during Creem's payment-retry window.
9. Send a terminal cancellation event and confirm the tenant returns to `free`.
10. Resend a webhook and confirm it is handled idempotently.
11. Confirm invalid signatures are rejected and valid events receive HTTP 200.

Production cutover:

1. Complete the Creem account review and payout verification.
2. Confirm that the Creem dashboard explicitly shows that live payments are enabled.
3. Rotate the live API key that was used during setup and store the replacement only in the `BILLING_API_KEY` GitHub secret.
4. Keep the production webhook enabled at `https://api.safernotes.com/api/v1/billing/webhook` and store its signing secret only in the `BILLING_WEBHOOK_SECRET` GitHub secret.
5. Disable the Test Mode webhook before resetting the test purchaser, so a delayed Test Mode event cannot reactivate the test subscription.
6. In `/owner-admin/`, find `moses.ellermann@pm.me`, open its subscription, and change it to plan `free` with status `canceled`. This preserves the billing event audit trail while allowing a live checkout.
7. Update the repository variables together:

   ```env
   BILLING_API_BASE_URL=https://api.creem.io/v1
   BILLING_PRODUCT_IDS={"essential":"prod_4DMoWRADZ9EkXAvu11zjaq","pro":"prod_7iezv7p8fUHQat7UYZUnix"}
   BILLING_TESTER_EMAILS=
   ```

8. Deploy once. The deployment rejects mixed Test Mode/live API keys and endpoints before touching the server configuration.
9. Run the `billing-smoke` GitHub Actions workflow and confirm both live products are reachable and active.
10. Sign in as `moses.ellermann@pm.me`, buy Essential as a real transaction, and confirm that the live webhook changes the plan to Essential.
11. Verify the customer invoice, customer portal, reverse invoice, EUR balance, refund behavior, and payout records before opening checkout to customers.

Live catalog already prepared:

- Essential yearly: `prod_4DMoWRADZ9EkXAvu11zjaq` (18 EUR/year, tax inclusive)
- Pro yearly: `prod_7iezv7p8fUHQat7UYZUnix` (60 EUR/year, tax inclusive)

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
- data processing agreements for hosting, email, and Creem
- support contact

Privacy policy must state that note content is encrypted client-side and not sent to Creem.

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

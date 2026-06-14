# Phase 9 Subscriptions and Billing Summary

Date: 2026-06-10

## Implemented

- Central plan policy definitions for free, pro, team, and enterprise.
- Plan limits for storage, max notes, max attachment size, collaborators, version history, team features, SSO readiness, audit controls, and data residency.
- Attachment quota logic now uses subscription plan policy.
- Tenant usage reporting endpoint.
- Subscription serializer includes plan policy.
- Checkout request validation with tenant-owner checks.
- Billing portal request validation with tenant-owner checks.
- Billing provider abstraction for future Stripe/Paddle/etc. integration.
- Billing webhook HMAC verification scaffold.
- Idempotent billing event storage.
- Billing event processing status.
- Subscription created/updated/deleted event processing.
- Tenant plan synchronization from billing events.
- Tests for plan policy behavior and webhook signature verification.

## Key API Updates

- `GET /api/v1/subscription/?tenant={tenant_id}`
- `GET /api/v1/subscription/usage?tenant={tenant_id}`
- `POST /api/v1/subscription/checkout`
- `POST /api/v1/subscription/portal`
- `POST /api/v1/billing/webhook`

## Billing Webhook Contract

The webhook expects:

- Header `X-Billing-Provider`
- Header `X-Billing-Signature`
- JSON body with `id`, `type`, `tenant_id`, and provider subscription fields when applicable

Supported event types:

- `subscription.created`
- `subscription.updated`
- `subscription.deleted`
- `subscription.canceled`

The HMAC uses `BILLING_WEBHOOK_SECRET`. Real provider adapters can map Stripe, Paddle, or another provider into this internal event shape.

## Privacy Notes

- Billing state tracks tenant, plan, provider ids, and usage counts only.
- Usage reports expose ciphertext byte counts, attachment counts, and note counts.
- Billing never receives note titles, note bodies, labels, attachment filenames, decrypted metadata, plaintext search data, or encryption keys.

## Verified

Python syntax compilation passed:

```bash
PYTHONPYCACHEPREFIX=work/pycache python3 -m compileall -q backend
```

## Not Yet Executed

Django and project dependencies are still not installed in the current local Python environment, so migrations and tests were not executed. After installing dependencies:

```bash
cd backend
python manage.py makemigrations
python manage.py migrate
pytest
```

## Next Phase

Phase 10 should focus on security hardening:

- Security headers and CSP middleware refinement.
- Rate limits by user, IP, route, and tenant.
- Audit event coverage for auth, billing, sharing, and admin actions.
- Admin-safe redaction policies.
- Dependency scanning configuration.
- Secrets management hardening.
- Abuse controls that do not inspect plaintext content.


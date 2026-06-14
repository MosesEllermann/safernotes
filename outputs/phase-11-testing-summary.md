# Phase 11 Testing Summary

Date: 2026-06-10

## Implemented

- Shared pytest fixtures in `backend/conftest.py`.
- Test factories for encrypted envelopes, users, tenants, notes, and request stubs.
- Permission tests for owner, editor, and viewer note roles.
- Sync idempotency serializer and receipt tests.
- Audit redaction tests.
- Billing signature and subscription state transition tests.
- Subscription plan policy and usage report tests.
- Authentication API workflow tests for register/login token responses.
- Subscription API validation tests for usage and checkout.
- Plaintext rejection hardening now runs before normal serializer field validation.
- Backend test CI workflow with PostgreSQL and Redis services.
- CI migration dry-run check.
- CI migrate, pytest, and ruff steps.
- Pytest discovery expanded to include `tests.py`, `*_tests.py`, `*tests.py`, and `test_*.py`.

## Coverage Areas

The expanded suite targets:

- Zero-knowledge plaintext rejection.
- Token rotation behavior.
- Role-based sharing permissions.
- Sync operation idempotency.
- Conflict handling.
- Attachment checksum and expiry validation.
- Billing webhook signatures.
- Subscription policy behavior.
- Audit metadata redaction.
- API-level auth and subscription validation.

## CI Workflow

Added:

```text
.github/workflows/backend-tests.yml
```

The workflow provisions:

- Python 3.12.
- PostgreSQL 16.
- Redis 7.

Then runs:

```bash
python manage.py makemigrations --check --dry-run
python manage.py migrate --noinput
pytest
ruff check .
```

## Verified

Python syntax compilation passed:

```bash
PYTHONPYCACHEPREFIX=work/pycache python3 -m compileall -q backend
```

## Not Yet Executed

Django and project dependencies are still not installed in the current local Python environment, so the test suite itself was not executed locally. After installing dependencies:

```bash
cd backend
python manage.py makemigrations
python manage.py migrate
pytest
ruff check .
```

## Next Phase

Phase 12 should focus on documentation:

- Backend API reference.
- Security whitepaper draft.
- Crypto/key-management developer guide.
- Local development setup guide.
- Deployment guide.
- Operational runbooks.
- Incident response playbook.
- Privacy and telemetry policy notes.


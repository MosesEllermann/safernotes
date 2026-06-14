# Phase 6 Sharing Hardening Summary

Date: 2026-06-10

## Implemented

- Share invitation model with pending, accepted, declined, and revoked states.
- Invitation lifecycle API through `ShareInvitationViewSet`.
- Recipient-only accept/decline behavior.
- Sender-only invitation revocation.
- Owner-only invitation creation.
- Owner-only note-key grant management.
- Ownership transfer endpoint.
- Grant revocation reason metadata.
- Source invitation linkage on accepted note-key grants.
- Public encryption/signing key fingerprint fields.
- Public-key response now includes a key transparency leaf stub.
- Encrypted share invitation notification creation.
- Encrypted ownership transfer notification creation.
- Tests documenting plaintext rejection for share invitation and ownership transfer serializers.
- Test documenting that invitations cannot assign owner role; ownership transfer is the dedicated path.

## Key API Additions

- `GET /api/v1/notes/invitations/`
- `POST /api/v1/notes/invitations/`
- `POST /api/v1/notes/invitations/{id}/decide/`
- `DELETE /api/v1/notes/invitations/{id}/`
- `POST /api/v1/notes/{id}/transfer-owner/`

## Sharing Contract

Invitation creation stores:

- Sender id.
- Recipient id.
- Role.
- Encrypted note key envelope.
- Invitation signature.
- Optional encrypted notification payload.

The server never receives plaintext note keys. On accept, the encrypted note key is copied into a `NoteKeyGrant` for the recipient. On decline or revoke, no grant is created.

## Security Notes

- `owner` is not a valid invitation role. Ownership transfer has its own endpoint.
- Grant revocation is soft metadata revocation. Already-synced devices may still hold plaintext after local decrypt; this is inherent to E2EE sharing and must be explained in product UX.
- Public key fingerprints are stored and exposed for client verification.
- The key transparency leaf is a foundation for a future append-only transparency log, not a complete transparency system yet.
- Share and transfer notifications remain encrypted per recipient.

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

Phase 7 should deepen realtime collaboration:

- Authenticated websocket middleware.
- Role checks before joining note channels.
- Durable encrypted event replay.
- Event acknowledgement and retry handling.
- Presence metadata without plaintext activity content.
- Collaboration conflict tests.
- Redis-backed channel integration tests.


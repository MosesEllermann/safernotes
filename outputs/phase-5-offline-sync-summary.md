# Phase 5 Offline Sync Summary

Date: 2026-06-10

## Implemented

- Per-device sync checkpoint model.
- Sync operation receipt model for idempotent offline replay.
- `idempotency_key` requirement for every sync batch operation.
- Sync batch replay detection that returns stored operation results without applying the same mutation twice.
- Sync changes endpoint now uses a device checkpoint when no cursor is supplied.
- Sync changes and batch endpoints can update device checkpoints.
- Conflict resolution endpoint for marking encrypted conflict copies resolved.
- Encrypted notification fanout endpoint with per-recipient encrypted payloads.
- Fanout recipient limit to reduce abuse risk.
- Tests documenting idempotency-key requirements, minimal conflict resolution, and fanout plaintext rejection.

## Key API Updates

- `GET /api/v1/notes/sync/changes?device_id=&cursor=`
- `POST /api/v1/notes/sync/batch`
- `POST /api/v1/notes/{id}/conflicts/{conflict_id}/resolve/`
- `POST /api/v1/notifications/fanout/`

## Sync Contract

Each sync batch operation must include:

```json
{
  "idempotency_key": "client-generated-stable-key",
  "type": "upsert_note",
  "note_id": "optional-note-id",
  "payload": {
    "encrypted_payload": {
      "version": 1,
      "algorithm": "XCHACHA20_POLY1305",
      "nonce": "base64url",
      "ciphertext": "base64url"
    }
  }
}
```

If the same user submits the same `idempotency_key` again, the server returns the stored result and does not reapply the operation.

## Security Notes

- Sync receipts store operation metadata and result ids/versions, not plaintext note content.
- Checkpoints are per user/device and store only cursor timestamps.
- Conflict resolution does not merge content server-side. The client decrypts, resolves, re-encrypts, uploads a new encrypted payload, then marks the conflict resolved.
- Notification fanout requires encrypted payloads per recipient. The backend does not create plaintext notification bodies.

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

Phase 6 should deepen sharing:

- Invitation lifecycle for pending shares.
- Public key verification and key fingerprints.
- Grant revocation semantics for already-synced devices.
- Ownership transfer workflow.
- Share notification creation during grant upload.
- Role-specific API integration tests.
- Key transparency design stub for future hardening.


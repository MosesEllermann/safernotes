# Phase 4 Encrypted Note Engine Summary

Date: 2026-06-10

## Implemented

- Expected-version checks for encrypted note updates.
- `409 version_conflict` response path for stale encrypted note writes.
- Conflict-copy persistence via `NoteConflict` so offline edits are not silently discarded.
- Conflict listing endpoint on notes.
- Role helpers for owner/editor/viewer authorization.
- Viewer read-only enforcement for note updates, state changes, deletes, attachment uploads, and collaboration events.
- Owner-only note-key grant management.
- Sync changes endpoint for encrypted note envelopes.
- Sync batch endpoint for offline upsert/state-change replay.
- Collaboration event API for encrypted realtime deltas.
- Attachment access expanded to authorized collaborators while preserving write restrictions.
- Text-safe serialization for note hashes, grant signatures, attachment ciphertext checksums, and key material.
- Tests documenting plaintext rejection for notes, attachments, notifications, and collaboration events.
- Test documenting stale-write conflict behavior.

## Key API Additions

- `GET /api/v1/notes/sync/changes`
- `POST /api/v1/notes/sync/batch`
- `GET /api/v1/notes/{id}/conflicts/`
- `GET /api/v1/collaboration/events/`
- `POST /api/v1/collaboration/events/`

## Security Notes

- The server still receives only encrypted note payloads, encrypted deltas, encrypted labels, encrypted attachment metadata, encrypted notifications, hashes, signatures, ids, roles, and timestamps.
- Server-side content search remains absent by design.
- Version conflicts store the losing encrypted payload as a conflict copy; resolution remains a client-side decrypt/merge/re-encrypt workflow.
- Collaboration events are treated as opaque encrypted deltas. The backend relays and stores them without inspecting plaintext state.
- Role enforcement is metadata-based because the server can enforce who may write, but it still cannot decrypt note contents or note keys.

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

Phase 5 should implement deeper offline sync behavior:

- Idempotency keys for sync operations.
- Durable sync cursors.
- Per-device sync checkpoints.
- Conflict resolution endpoint for marking conflict copies resolved.
- Encrypted operation history compaction.
- Push notification fanout without plaintext notification bodies.
- API integration tests against PostgreSQL and Redis.


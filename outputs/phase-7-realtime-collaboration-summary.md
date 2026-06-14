# Phase 7 Realtime Collaboration Summary

Date: 2026-06-10

## Implemented

- Websocket bearer-token authentication using the same opaque access tokens as REST.
- Websocket note-channel read permission checks before accepting connections.
- Viewer write prevention for websocket publishes.
- Durable encrypted event persistence before websocket fanout.
- Encrypted event replay on connect via `since_event_id`.
- Durable event acknowledgement model.
- Websocket acknowledgement handling.
- REST acknowledgement endpoint.
- Privacy-safe collaboration presence model.
- Presence read endpoint.
- Online/offline presence updates on websocket connect/disconnect.
- Testable websocket encrypted-event envelope validator.

## Key API Updates

- `WS /ws/v1/notes/{note_id}/?token={access_token}&since_event_id={event_id}`
- `GET /api/v1/collaboration/events/`
- `POST /api/v1/collaboration/events/`
- `GET /api/v1/collaboration/acks/`
- `POST /api/v1/collaboration/acks/`
- `GET /api/v1/collaboration/presence/`

## Websocket Message Contract

Publish encrypted event:

```json
{
  "type": "encrypted.event",
  "note_version": 12,
  "encrypted_delta": {
    "version": 1,
    "algorithm": "XCHACHA20_POLY1305",
    "nonce": "base64url",
    "ciphertext": "base64url"
  },
  "event_signature": "base64url"
}
```

Acknowledge event:

```json
{
  "type": "ack",
  "event_id": "uuid"
}
```

On connect, the server sends:

- `presence` metadata for the current user.
- `replay` containing recent encrypted events after `since_event_id`.

## Security Notes

- Websocket auth rejects missing, expired, revoked, or device-revoked tokens.
- Users must have note read access before joining the channel.
- Users must have note write access before publishing encrypted events.
- Presence stores only note/user/device/status/timestamps. It does not store cursor position, selected text, typing text, or plaintext activity.
- Realtime payloads remain encrypted envelopes. The backend stores and relays ciphertext only.

## Verified

Python syntax compilation passed:

```bash
PYTHONPYCACHEPREFIX=work/pycache python3 -m compileall -q backend
```

## Not Yet Executed

Django, Channels, Redis, and project dependencies are still not installed in the current local Python environment, so migrations, unit tests, and websocket integration tests were not executed. After installing dependencies:

```bash
cd backend
python manage.py makemigrations
python manage.py migrate
pytest
```

## Next Phase

Phase 8 should implement encrypted attachments in depth:

- Presigned upload/download flow.
- Attachment ownership and collaborator permission checks.
- Encrypted attachment metadata validation.
- Object checksum confirmation.
- Attachment lifecycle cleanup.
- Quota accounting.
- Optional size-bucket padding strategy.


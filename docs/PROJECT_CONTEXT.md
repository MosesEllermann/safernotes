# Project Context

## Summary

Safernotes is a zero-knowledge encrypted note-taking application. The backend stores encrypted envelopes and rejects plaintext note content. The frontend is a Flutter app targeting web, Android, and iOS.

## Repository Layout

- `backend/`: Django backend, REST APIs, authentication, encrypted notes, sync, sharing, realtime primitives, billing/subscription placeholders.
- `frontend/`: Flutter client app.
- `infra/`: Kubernetes and Helm starter manifests.
- `.github/workflows/`: CI for backend/security checks.
- `outputs/`: phase summaries from architecture/backend implementation.
- `AGENTS.md`: compact context for future AI/coding agents.

## Core UX State

The frontend is currently a sticky-note style app:

- Top search next to the logo.
- Left desktop navigation for Notes, Archive, Trash.
- Quick composer on active notes only.
- Responsive card grid.
- Sticky-note modal/editor.
- Animated icon controls.
- Autosave and sync status.
- Text note and checklist note modes.

## Data Model

`PlainNote` is the local decrypted model. It includes:

- `localId`
- `remoteId`
- `title`
- `body`
- `checklist`
- `updatedAt`
- `pinned`
- `color`
- `dirty`
- `version`
- `state`: `active`, `archived`, `trashed`, or `deleted`
- `conflicted`

Encrypted payloads store rich content under schema version 2.

## Backend Contract

Important endpoints:

- `POST /api/v1/auth/register`
- `POST /api/v1/auth/login`
- `GET /api/v1/notes/`
- `POST /api/v1/notes/sync/batch`
- `GET /api/v1/collaboration/presence/`
- `POST /api/v1/notes/invitations/`

Sync batch operations currently used by the client:

- `upsert_note`
- `change_state`

## Verification Baseline

Last known good checks:

- Flutter analysis: passing.
- Flutter web build: passing.
- Django system check: passing.
- Django migrations check: clean.
- Backend tests: `38 passed`.


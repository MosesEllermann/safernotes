# Phase 1 Architecture Package: Zero-Knowledge SaaS Notes Platform

Date: 2026-06-09

## Executive Decision

Build the product as a Flutter client plus Django platform where all user note content is encrypted before it leaves the device. The backend is treated as untrusted storage and orchestration: it authenticates users, enforces permissions, stores encrypted envelopes, relays encrypted realtime messages, handles billing, and records privacy-safe operational metadata. It never receives plaintext note titles, note bodies, labels, checklist items, attachment bytes, search tokens, or note encryption keys.

This document covers the requested Phase 1 outputs:

1. Product architecture
2. Security architecture
3. Threat model
4. Cryptographic design
5. Key management design
6. Database schema
7. API specification
8. SaaS architecture
9. Infrastructure architecture
10. Cost estimation

## Product Architecture

### Product Principles

- Keep the first interaction as simple as Google Keep: quick capture, color, pin, archive, trash, checklist, and search.
- Match privacy expectations closer to Notesnook and Standard Notes: encrypted content, encrypted attachments, local search, and unrecoverable data when password and recovery material are lost.
- Support Notion-style sharing, roles, team spaces, and realtime collaboration without exposing content to the service.
- Preserve Obsidian-like offline confidence: local-first data model, encrypted local persistence, and deterministic sync after reconnect.

### Platform Shape

Frontend:

- Flutter single codebase for web, Android, and iOS.
- Material Design 3.
- Riverpod for state management and dependency injection.
- Local encrypted repository pattern for offline operation.
- Crypto boundary located in shared client services, not feature screens.

Backend:

- Django, Django REST Framework, Django Channels.
- PostgreSQL for authoritative encrypted records and metadata.
- Redis for channel fanout, rate limiting, sessions, idempotency, and sync queues.
- S3-compatible object storage for encrypted attachments.
- CDN only for encrypted static attachment blobs, never plaintext.

Core apps:

- `apps/users`
- `apps/authentication`
- `apps/devices`
- `apps/notes`
- `apps/attachments`
- `apps/sharing`
- `apps/collaboration`
- `apps/search`
- `apps/subscriptions`
- `apps/billing`
- `apps/audit`
- `apps/notifications`

### Client Feature Structure

```text
lib/
  features/auth/
  features/notes/
  features/archive/
  features/trash/
  features/sharing/
  features/search/
  features/settings/
  features/subscription/
  shared/crypto/
  shared/local_store/
  shared/models/
  shared/services/
  shared/sync/
  shared/theme/
  shared/widgets/
```

### Data Flow

1. User creates or edits a note locally.
2. Client validates and normalizes the note document.
3. Client encrypts title, content, checklist items, formatting, labels, color, and attachment metadata using the note key.
4. Client writes encrypted local state.
5. Client uploads encrypted envelope to backend with version metadata.
6. Backend stores ciphertext, version, owner, ACL metadata, timestamps, and sync cursors.
7. Other authorized devices receive encrypted sync events and decrypt locally if they possess the note key.

## Security Architecture

### Trust Boundaries

Trusted:

- User device after local unlock.
- Audited client cryptography implementation.
- User-controlled password and recovery material.

Partially trusted:

- Authentication layer for identity and session issuance.
- Billing provider for payment state.
- Object storage for availability only.

Untrusted:

- Backend application servers.
- Database.
- Redis.
- Object storage.
- Backups.
- Administrators.
- Network path.

### Backend Must Never Store

- Plaintext note title.
- Plaintext note body.
- Plaintext checklist items.
- Plaintext labels.
- Plaintext attachment bytes.
- Plaintext note keys.
- Passwords or recoverable password equivalents.
- Local search index tokens.

### Backend May Store

- User email for login and billing.
- Public encryption and signing keys.
- Encrypted private key blobs.
- Encrypted master key wrapper.
- Encrypted note envelopes.
- Encrypted note key grants for collaborators.
- Role and permission metadata.
- Quotas, billing status, storage bytes, rate-limit counters.
- Privacy-safe audit events such as `note_created`, not note content.

### Mandatory Controls

- TLS everywhere, HSTS, secure cookies, strict CORS.
- Argon2id password hashing server-side for authentication.
- Separate client-side Argon2id derivation for key unlocking.
- Per-device sessions with revocation.
- Refresh token rotation and reuse detection.
- CSRF protection for browser session flows.
- Rate limits by IP, account, device, and route.
- Signed audit events for administrative and billing actions.
- Dependency scanning, pinned lockfiles, SLSA-aware build pipeline.
- Security headers: CSP, COOP, COEP where viable, frame denial, no inline script on web.

## Cryptographic Design

### Algorithms

- Password derivation: Argon2id.
- Content encryption: XChaCha20-Poly1305 preferred.
- Acceptable fallback: AES-256-GCM only where XChaCha20-Poly1305 is unavailable.
- Asymmetric encryption: X25519 sealed-box style key agreement.
- Signing: Ed25519.
- Randomness: platform CSPRNG only.
- Hashing for identifiers: BLAKE3 or SHA-256 where library support and auditability are appropriate.

### Envelope Format

Every encrypted object uses an explicit versioned envelope:

```json
{
  "version": 1,
  "algorithm": "XCHACHA20_POLY1305",
  "key_id": "uuid",
  "nonce": "base64url",
  "aad": {
    "object_type": "note",
    "object_id": "uuid",
    "tenant_id": "uuid",
    "version": 42
  },
  "ciphertext": "base64url"
}
```

AAD binds ciphertext to object type, object id, tenant id, and version to reduce replay and mix-up risk. The server stores but cannot interpret the ciphertext.

### Local Search

Server-side content search is forbidden. The client maintains a local decrypted search index derived after unlock. The index is encrypted at rest with a local database key. Web search index data must use browser storage guarded by a key derived from the unlocked master key and cleared on logout unless the user explicitly allows persistent local storage.

### Attachments

- Attachment bytes are encrypted locally with a key derived from the note key and attachment id.
- Object storage stores ciphertext only.
- Attachment metadata visible to the server is limited to attachment id, byte size, content type class when necessary for delivery, checksum of ciphertext, and owner/tenant ids.
- Optional future improvement: pad attachment sizes into buckets to reduce metadata leakage.

## Key Management Design

### User Keys

Each account has:

- Master Key: symmetric root for wrapping local secrets.
- X25519 public/private encryption key pair.
- Ed25519 public/private signing key pair.
- Recovery Key or Recovery Phrase.

Private keys are generated client-side and encrypted locally before upload.

### Note Keys

Each note has a unique random Note Encryption Key. The note key encrypts:

- Title.
- Body.
- Formatting.
- Checklist items.
- Labels and categories.
- Color and user-facing display metadata.
- Attachment metadata and attachment keys.

### Registration

Client:

1. Generate master key.
2. Generate X25519 and Ed25519 key pairs.
3. Derive password key with Argon2id using a unique salt.
4. Encrypt master key with password key.
5. Encrypt private keys with master key.
6. Generate recovery material.
7. Encrypt recovery wrapper with recovery key.
8. Upload public keys and encrypted blobs.

Server:

- Stores email, password verifier/hash, public keys, salts, KDF parameters, encrypted key blobs, and billing profile.
- Never receives plaintext password, master key, private keys, or note keys.

### Login

1. Server authenticates user.
2. Client downloads encrypted key material and KDF parameters.
3. Client derives password key locally.
4. Client unlocks master key.
5. Client decrypts private keys locally.
6. Client syncs encrypted note envelopes and decrypts locally.

### Sharing

Owner or editor with share permission:

1. Decrypt note key locally.
2. Fetch recipient public encryption key.
3. Verify recipient key fingerprint when high assurance is required.
4. Encrypt note key to recipient public key.
5. Sign the grant using sender signing key.
6. Upload encrypted note key grant.

Recipient:

1. Downloads encrypted note key grant.
2. Verifies grant signature.
3. Decrypts note key locally.
4. Decrypts note content locally.

### Recovery

Recommended MVP: 128-bit random recovery key rendered as grouped words or base32 chunks. The recovery key wraps the master key. If password and recovery key are both lost, encrypted content is unrecoverable by design.

Tradeoff:

- Recovery key preserves zero-knowledge guarantees.
- It creates user responsibility and support friction.
- Social recovery can be added later, but only with explicit user-controlled encrypted shares.

## Database Schema

Use UUID primary keys, `created_at`, `updated_at`, soft delete where appropriate, and tenant-aware indexes.

### Core Tables

`users_user`

- `id uuid pk`
- `email citext unique`
- `email_verified_at timestamptz null`
- `password_hash text`
- `status text`
- `default_tenant_id uuid null`
- `created_at timestamptz`
- `updated_at timestamptz`

`users_profile`

- `id uuid pk`
- `user_id uuid fk`
- `display_name_ciphertext jsonb null`
- `avatar_attachment_id uuid null`
- `locale text`
- `timezone text`

`authentication_key_material`

- `id uuid pk`
- `user_id uuid fk unique`
- `kdf_algorithm text`
- `kdf_params jsonb`
- `password_salt bytea`
- `public_encryption_key bytea`
- `public_signing_key bytea`
- `encrypted_master_key jsonb`
- `encrypted_private_encryption_key jsonb`
- `encrypted_private_signing_key jsonb`
- `recovery_wrapper jsonb`
- `key_version int`

`devices_device`

- `id uuid pk`
- `user_id uuid fk`
- `name_ciphertext jsonb`
- `public_signing_key bytea`
- `last_seen_at timestamptz`
- `revoked_at timestamptz null`
- `trusted_at timestamptz null`

`authentication_session`

- `id uuid pk`
- `user_id uuid fk`
- `device_id uuid fk null`
- `refresh_token_hash text`
- `ip_hash text`
- `user_agent_hash text`
- `expires_at timestamptz`
- `revoked_at timestamptz null`

`tenants_organization`

- `id uuid pk`
- `name_ciphertext jsonb`
- `plan text`
- `owner_user_id uuid fk`
- `created_at timestamptz`

`tenants_membership`

- `id uuid pk`
- `tenant_id uuid fk`
- `user_id uuid fk`
- `role text`
- `status text`

`notes_note`

- `id uuid pk`
- `tenant_id uuid fk`
- `owner_user_id uuid fk`
- `state text` (`active`, `archived`, `trashed`, `deleted`)
- `pinned bool`
- `version bigint`
- `schema_version int`
- `encrypted_payload jsonb`
- `payload_hash bytea`
- `client_updated_at timestamptz`
- `deleted_at timestamptz null`

`notes_note_key_grant`

- `id uuid pk`
- `note_id uuid fk`
- `recipient_user_id uuid fk`
- `sender_user_id uuid fk`
- `role text`
- `encrypted_note_key jsonb`
- `grant_signature bytea`
- `revoked_at timestamptz null`

`notes_label`

- `id uuid pk`
- `tenant_id uuid fk`
- `owner_user_id uuid fk`
- `encrypted_payload jsonb`
- `created_at timestamptz`

`notes_note_label`

- `id uuid pk`
- `note_id uuid fk`
- `label_id uuid fk`

`attachments_attachment`

- `id uuid pk`
- `tenant_id uuid fk`
- `note_id uuid fk`
- `object_key text`
- `ciphertext_size bigint`
- `ciphertext_sha256 bytea`
- `encrypted_metadata jsonb`
- `upload_state text`

`collaboration_sync_event`

- `id uuid pk`
- `tenant_id uuid fk`
- `note_id uuid fk`
- `actor_user_id uuid fk`
- `note_version bigint`
- `encrypted_delta jsonb`
- `event_signature bytea`
- `created_at timestamptz`

`subscriptions_subscription`

- `id uuid pk`
- `tenant_id uuid fk`
- `plan text`
- `status text`
- `billing_provider text`
- `provider_customer_id text`
- `provider_subscription_id text`
- `current_period_end timestamptz`

`audit_audit_event`

- `id uuid pk`
- `tenant_id uuid null`
- `actor_user_id uuid null`
- `event_type text`
- `target_type text`
- `target_id uuid null`
- `metadata jsonb`
- `signature bytea`
- `created_at timestamptz`

`notifications_notification`

- `id uuid pk`
- `user_id uuid fk`
- `type text`
- `encrypted_payload jsonb`
- `read_at timestamptz null`

### Indexes

- `(tenant_id, updated_at)` for sync.
- `(user_id, revoked_at)` for active sessions and devices.
- `(note_id, recipient_user_id)` unique active grants.
- `(tenant_id, state, updated_at)` for note listing.
- `(tenant_id, plan, status)` for quota enforcement.
- Partial indexes for unrevoked sessions, active grants, and non-deleted notes.

## API Specification

All APIs use JSON over HTTPS. Authenticated routes require access token or secure browser session. Mutating requests include idempotency keys.

### Authentication

- `POST /api/v1/auth/register` creates user and stores encrypted key material.
- `POST /api/v1/auth/login` authenticates and returns session plus encrypted key material.
- `POST /api/v1/auth/refresh` rotates refresh token.
- `POST /api/v1/auth/logout` revokes current session.
- `POST /api/v1/auth/recovery/start` fetches recovery metadata.
- `POST /api/v1/auth/recovery/complete` replaces password wrapper after local recovery.

### Users and Devices

- `GET /api/v1/me` returns account, tenant, quota, and public profile metadata.
- `PATCH /api/v1/me` updates encrypted profile fields.
- `GET /api/v1/users/{id}/public-keys` returns public encryption and signing keys.
- `GET /api/v1/devices` lists devices.
- `POST /api/v1/devices` registers a device.
- `DELETE /api/v1/devices/{id}` revokes a device and its sessions.

### Notes

- `GET /api/v1/notes?cursor=&state=&updated_after=` lists encrypted note envelopes.
- `POST /api/v1/notes` creates encrypted note envelope.
- `GET /api/v1/notes/{id}` fetches encrypted note and grants visible to caller.
- `PUT /api/v1/notes/{id}` replaces encrypted payload with version check.
- `PATCH /api/v1/notes/{id}/state` archives, restores, trashes, or soft-deletes.
- `POST /api/v1/notes/{id}/duplicate` creates a server-side metadata shell; client uploads new encrypted payload.
- `DELETE /api/v1/notes/{id}` permanently deletes note where policy allows.
- `GET /api/v1/sync/changes?cursor=` returns ordered encrypted changes.
- `POST /api/v1/sync/batch` applies idempotent encrypted client changes.

### Labels

- `GET /api/v1/labels` lists encrypted labels.
- `POST /api/v1/labels` creates encrypted label.
- `PUT /api/v1/labels/{id}` updates encrypted label.
- `DELETE /api/v1/labels/{id}` deletes label association metadata.

### Sharing

- `GET /api/v1/notes/{id}/collaborators` lists collaborator ids, roles, and encrypted grants.
- `POST /api/v1/notes/{id}/share` uploads encrypted note key grant.
- `PATCH /api/v1/notes/{id}/collaborators/{user_id}` changes role.
- `DELETE /api/v1/notes/{id}/collaborators/{user_id}` revokes grant.
- `POST /api/v1/notes/{id}/transfer-owner` transfers ownership.

### Attachments

- `POST /api/v1/attachments/initiate` creates upload target for encrypted blob.
- `PUT /api/v1/attachments/{id}/complete` confirms ciphertext checksum and metadata.
- `GET /api/v1/attachments/{id}/download` returns signed URL for encrypted blob.
- `DELETE /api/v1/attachments/{id}` deletes encrypted blob and metadata.

### Collaboration

- `WS /ws/v1/notes/{id}` joins encrypted realtime note channel.
- `POST /api/v1/notes/{id}/events` appends encrypted collaboration event.
- `GET /api/v1/notes/{id}/events?since=` fetches encrypted event backlog.

### Subscriptions and Billing

- `GET /api/v1/subscription` returns plan, quotas, usage, and status.
- `POST /api/v1/subscription/checkout` creates billing checkout session.
- `POST /api/v1/subscription/portal` creates customer portal session.
- `POST /api/v1/billing/webhook` receives signed provider events.

### Search

- `GET /api/v1/search/status` returns local-search policy and sync cursor only.
- No endpoint accepts plaintext search queries or content-derived tokens.

### Notifications

- `GET /api/v1/notifications` returns encrypted notification payloads.
- `PATCH /api/v1/notifications/{id}` marks read.

## Offline Sync and Conflict Resolution

MVP:

- Local writes always succeed after unlock.
- Each note has monotonic `version` and client timestamp.
- Server rejects stale writes unless caller explicitly sends conflict resolution.
- Default conflict policy is last-write-wins for MVP.
- Client keeps conflict copies when both versions include user edits after the last common sync.

Future:

- Replace full-note updates with encrypted CRDT operations.
- Use per-field or per-block encrypted deltas.
- Preserve encrypted operation logs for collaboration history.

## Threat Model

| Threat | Impact | Risk | Mitigation | Residual Risk |
| --- | --- | --- | --- | --- |
| Database leak | Encrypted records, emails, metadata exposed | High | E2EE, envelope encryption, key separation, minimal metadata | Emails, sizes, timestamps leak |
| Stolen backups | Same as database leak | High | Encrypted content, backup access controls, short retention | Metadata exposure remains |
| Rogue administrator | Insider attempts content access | High | No plaintext keys server-side, RBAC, audit logs, break-glass workflow | Admin can disrupt service |
| Server compromise | Attacker controls API responses | Critical | E2EE, signed grants/events, key transparency roadmap, CSP, monitoring | Malicious key substitution possible before verification |
| Supply-chain attack | Client crypto or app code altered | Critical | Lockfiles, signed builds, dependency scanning, reproducible build goals | Web client remains harder to verify |
| MITM attack | Credential/session theft, key substitution | High | TLS, HSTS, certificate pinning on mobile where practical, key fingerprints | Compromised CA/device can still harm |
| XSS | Web client secrets exposed after unlock | Critical | Strong CSP, no inline scripts, dependency hygiene, trusted types roadmap | Browser platform risk remains |
| CSRF | Unauthorized state changes | Medium | SameSite cookies, CSRF tokens, origin checks | Token theft bypasses |
| Session theft | Account access until revoked | High | Refresh rotation, device binding, revocation, anomaly detection | Unlocked local data may remain exposed |
| Credential stuffing | Account takeover | High | Rate limits, breached password checks, optional MFA/passkeys | Weak reused passwords remain risky |
| Device theft | Local vault exposure | High | Encrypted local DB, biometric/PIN unlock, remote revocation | If app unlocked, content exposed |
| Malicious collaborator | Shared note copied or altered | Medium | Roles, signed events, owner revocation, history | Viewers can copy plaintext they can read |
| Lost password | User loses access | High | Recovery key, clear onboarding, recovery tests | If recovery key lost, data is unrecoverable |
| Phishing | User reveals password/recovery | High | Passkeys roadmap, phishing-resistant UX, device alerts | Human risk remains |
| API abuse | Quota exhaustion or scraping metadata | Medium | Rate limits, quotas, anomaly detection | Public endpoints leak existence timing |
| DDoS | Availability loss | High | CDN/WAF, autoscaling, rate limits, queue isolation | Large attacks may require provider support |

## SaaS Architecture

### Plans

Free:

- Limited storage.
- Limited attachment quota.
- Basic collaboration.
- Core E2EE notes.

Pro:

- Increased storage.
- Unlimited notes subject to fair use.
- Larger attachments.
- Version history.

Team:

- Team workspaces.
- Role administration.
- Shared billing.
- Advanced collaboration.

Enterprise:

- SSO-ready architecture.
- Audit capability without content visibility.
- Data residency.
- Enterprise controls and legal workflows.

### Multi-Tenancy

- Tenant represents personal workspace, family, team, or organization.
- Every note belongs to a tenant.
- Membership and role tables enforce authorization.
- Content remains encrypted per note, not per tenant, so tenant admins cannot read all content unless granted keys.
- Quotas are tenant-level; sessions and devices are user-level.

### Privacy-Preserving Analytics

Allowed:

- Opt-in first-party telemetry.
- Aggregated operational metrics.
- Events like app version, sync latency, encrypted object count.

Forbidden:

- Advertising.
- Data selling.
- Behavioral profiling.
- Third-party analytics SDKs with content or identity leakage.
- Note content, search query, decrypted label, or attachment filename telemetry.

## Infrastructure Architecture

### Local Development

- Docker Compose with backend, Postgres, Redis, object storage emulator, mail catcher.
- Separate Flutter run targets for web and mobile.
- Seed data never includes real keys or plaintext production-like content.

### Production

- Kubernetes-ready container architecture.
- Django API deployment horizontally scaled.
- Django Channels workers separately scaled.
- Celery or Django-Q workers for async billing, email, cleanup, and storage tasks.
- PostgreSQL managed service or HA cluster.
- Redis managed service or clustered deployment.
- S3-compatible encrypted object storage.
- CDN for encrypted attachment blobs and static assets.

### Kubernetes and Helm

Generate:

- `Deployment` for API.
- `Deployment` for realtime workers.
- `Deployment` for background workers.
- `Service` for internal routing.
- `Ingress` with TLS.
- `HorizontalPodAutoscaler`.
- `NetworkPolicy`.
- `PodDisruptionBudget`.
- Helm values for Hetzner, AWS, Azure, and GCP.

### Secrets

- Use cloud KMS or sealed secrets for server secrets.
- Rotate signing secrets and API credentials.
- Never store user content encryption keys in infrastructure secret stores.
- Separate billing webhook secrets, JWT/session secrets, database credentials, object storage credentials.

### Backups and Disaster Recovery

- Daily encrypted PostgreSQL backups with point-in-time recovery.
- Object storage versioning and lifecycle policy.
- Quarterly restore drills.
- RPO target: 15 minutes for paid plans after launch.
- RTO target: 4 hours MVP, 1 hour mature production.
- Backups contain encrypted user content only, but still require strict access due to metadata.

### Monitoring and Logging

- Metrics: request latency, error rates, sync lag, websocket fanout, queue depth, storage usage, auth failures.
- Logs: structured, redacted, no request bodies for encrypted payload routes.
- Alerts: auth anomaly, billing webhook failure, DB replication lag, backup failure, high 5xx rate, high sync conflict rate.
- Tracing: sampled traces with payload redaction.

## Cost Estimation

MVP private beta on Hetzner:

- 2 small API nodes: 20-40 EUR/month.
- Managed or self-hosted PostgreSQL primary plus backup volume: 30-80 EUR/month.
- Redis node: 10-25 EUR/month.
- Object storage: 5-50 EUR/month depending on attachment use.
- Monitoring/logging: 0-50 EUR/month with open-source stack.
- Total early infrastructure: roughly 65-245 EUR/month before staff, audits, billing fees, support, and email.

Production launch:

- Multi-node API/realtime/worker pool: 150-600 EUR/month.
- HA PostgreSQL and backups: 200-1,000 EUR/month.
- Redis HA: 100-400 EUR/month.
- Object storage and CDN: usage-driven, likely 100-1,000 EUR/month early.
- Observability and security tooling: 100-1,000 EUR/month.
- External security audit: one-time 15,000-80,000+ EUR depending on scope.

Cost optimization:

- Store encrypted attachments in object storage, not Postgres.
- Bucket attachment sizes and lifecycle deleted blobs.
- Use autoscaling for realtime separately from API.
- Keep audit logs compact and avoid encrypted payload duplication.
- Offer free-plan quotas that reflect storage cost and abuse controls.

## Competitive Analysis

Compared products are inferred from the product vision: Google Keep, Notesnook, Standard Notes, Notion, and Obsidian.

| Product | Strength | Weakness/opportunity | Proposed differentiator |
| --- | --- | --- | --- |
| Google Keep | Fast capture, simple UI, labels, colors, checklists, broad Google ecosystem | Not positioned as zero-knowledge E2EE; limited role model and advanced privacy | Keep-level speed with encrypted content, private labels, encrypted attachments |
| Notesnook | Privacy-oriented, E2EE, cross-platform notes | Smaller ecosystem and team collaboration surface than Notion-style tools | Stronger team SaaS, organization controls, and realtime encrypted collaboration |
| Standard Notes | Mature encrypted notes, offline support, longevity posture | Collaboration and Keep-like quick capture can be less central | Simpler capture-first UX plus team and family sharing |
| Notion | Excellent collaboration, permissions, workspaces, databases, templates | Not zero-knowledge for general workspace content | Notion-like sharing for sensitive notes without provider-readable contents |
| Obsidian | Local-first, offline, user-owned files, strong knowledge graph culture | SaaS collaboration requires optional services and setup decisions | Offline-first SaaS with simple sync, mobile-first UI, and encrypted collaboration |

Unique selling propositions:

- Zero-knowledge collaboration for simple notes and checklists.
- Private labels and local-only search.
- Mobile-first offline encrypted vault.
- Team and family sharing without plaintext backend access.
- Clear recovery honesty: no password plus no recovery key means no data recovery.

## Weakness Review and Improvements

Weaknesses:

- Web clients are harder to make cryptographically trustworthy because served JavaScript can change.
- Metadata leakage remains: email, note counts, storage size, timestamps, collaborator graph, IPs.
- Last-write-wins can lose edits under concurrent collaboration.
- Sharing is vulnerable to public-key substitution unless users verify keys or key transparency exists.
- Recovery keys create onboarding friction.
- E2EE limits server-side abuse detection and content moderation.

Recommended improvements:

- Add native mobile apps before broad enterprise claims.
- Implement public key transparency before high-risk team/enterprise use.
- Add passkeys and TOTP early.
- Add conflict copies in MVP, then encrypted CRDT operations.
- Offer optional attachment padding for high-privacy plans.
- Commission external crypto and application security audits before public launch.
- Publish a security whitepaper and open-source client crypto package.

## Phase 2 Implementation Gate

Before coding the backend foundation:

- Select vetted Dart crypto library supporting XChaCha20-Poly1305, X25519, Ed25519, and Argon2id or audited bindings.
- Decide JWT versus opaque session token strategy; prefer opaque refresh tokens plus short-lived access tokens.
- Define exact encrypted envelope schema as JSON Schema.
- Create Django project and apps matching the package structure.
- Create initial migrations for users, key material, tenants, devices, notes, grants, attachments, subscriptions, audit, and notifications.
- Add tests proving no note routes accept plaintext fields such as `title`, `content`, `label_name`, or `filename`.

## Reference Notes

Current public positioning used for competitor framing was checked against public web sources on 2026-06-09, including Google Keep coverage, Notesnook/Standard Notes privacy positioning, Notion collaboration positioning, Obsidian local-file positioning, and general E2EE definitions. Product features can change, so competitor claims should be refreshed during fundraising, launch positioning, and security whitepaper publication.

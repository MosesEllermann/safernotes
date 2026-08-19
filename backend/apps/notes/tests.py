from __future__ import annotations

import pytest

from apps.attachments.serializers import AttachmentSerializer
from apps.collaboration.consumers import valid_encrypted_event_payload
from apps.collaboration.serializers import SyncEventSerializer
from apps.notes.exceptions import VersionConflict
from apps.notes.serializers import (
    ConflictResolutionSerializer,
    NoteSerializer,
    OwnershipTransferSerializer,
    ShareInvitationSerializer,
)
from apps.notes.sync import SyncBatchSerializer
from apps.notifications.serializers import (
    EncryptedNotificationFanoutSerializer,
    NotificationSerializer,
)


def encrypted_payload():
    return {
        "version": 1,
        "algorithm": "XCHACHA20_POLY1305",
        "nonce": "nonce",
        "ciphertext": "ciphertext",
    }


def test_note_serializer_rejects_plaintext_title():
    serializer = NoteSerializer(
        data={
            "tenant": "00000000-0000-0000-0000-000000000001",
            "title": "plaintext is forbidden",
            "encrypted_payload": encrypted_payload(),
            "payload_hash": "hash",
            "client_updated_at": "2026-06-09T00:00:00Z",
        }
    )

    assert not serializer.is_valid()
    assert "encrypted_payload" in serializer.errors


def test_note_serializer_requires_ciphertext_envelope(tenant):
    serializer = NoteSerializer(
        data={
            "tenant": str(tenant.id),
            "encrypted_payload": {"version": 1},
            "payload_hash": "hash",
            "client_updated_at": "2026-06-09T00:00:00Z",
        }
    )

    assert not serializer.is_valid()
    assert "encrypted_payload" in serializer.errors


def test_attachment_serializer_rejects_plaintext_filename():
    serializer = AttachmentSerializer(
        data={
            "tenant": "00000000-0000-0000-0000-000000000001",
            "note": "00000000-0000-0000-0000-000000000002",
            "filename": "secret.pdf",
            "ciphertext_size": 1024,
            "ciphertext_sha256": "ciphertext-hash",
            "encrypted_metadata": encrypted_payload(),
        }
    )

    assert not serializer.is_valid()
    assert "encrypted_payload" in serializer.errors


def test_notification_serializer_rejects_plaintext_body():
    serializer = NotificationSerializer(
        data={
            "type": "share_invite",
            "body": "plaintext notification",
            "encrypted_payload": encrypted_payload(),
        }
    )

    assert not serializer.is_valid()
    assert "encrypted_payload" in serializer.errors


def test_collaboration_serializer_rejects_plaintext_content():
    serializer = SyncEventSerializer(
        data={
            "tenant": "00000000-0000-0000-0000-000000000001",
            "note": "00000000-0000-0000-0000-000000000002",
            "note_version": 1,
            "content": "plaintext delta",
            "encrypted_delta": encrypted_payload(),
            "event_signature": "signature",
        },
        context={"request": object()},
    )

    assert not serializer.is_valid()
    assert "encrypted_payload" in serializer.errors


def test_websocket_encrypted_event_payload_requires_envelope():
    assert valid_encrypted_event_payload(
        {
            "type": "encrypted.event",
            "note_version": 1,
            "encrypted_delta": encrypted_payload(),
            "event_signature": "signature",
        }
    )
    assert not valid_encrypted_event_payload(
        {
            "type": "encrypted.event",
            "note_version": 1,
            "encrypted_delta": {"ciphertext": "missing envelope metadata"},
            "event_signature": "signature",
        }
    )


def test_note_serializer_conflict_raises_409(db, django_user_model):
    user = django_user_model.objects.create_user(email="owner@example.com", password="strong-password")
    from apps.notes.models import Note
    from apps.tenants.models import Organization

    tenant = Organization.objects.create(name_ciphertext=encrypted_payload(), owner_user=user)
    note = Note.objects.create(
        tenant=tenant,
        owner_user=user,
        encrypted_payload=encrypted_payload(),
        payload_hash=b"server-hash",
        client_updated_at="2026-06-09T00:00:00Z",
        version=3,
    )
    request = type("Request", (), {"user": user})()
    serializer = NoteSerializer(
        note,
        data={
            "expected_version": 2,
            "encrypted_payload": encrypted_payload(),
            "payload_hash": "client-hash",
            "client_updated_at": "2026-06-10T00:00:00Z",
        },
        partial=True,
        context={"request": request},
    )

    assert serializer.is_valid()
    with pytest.raises(VersionConflict):
        serializer.save()


def test_note_serializer_ignores_expected_version_on_create(tenant, owner_user):
    request = type("Request", (), {"user": owner_user})()
    serializer = NoteSerializer(
        data={
            "tenant": str(tenant.id),
            "expected_version": 1,
            "encrypted_payload": encrypted_payload(),
            "payload_hash": "client-hash",
            "client_updated_at": "2026-06-10T00:00:00Z",
        },
        context={"request": request},
    )

    assert serializer.is_valid()
    note = serializer.save()

    assert note.owner_user == owner_user
    assert note.version == 1


def test_sync_batch_requires_idempotency_key():
    serializer = SyncBatchSerializer(
        data={
            "operations": [
                {
                    "type": "change_state",
                    "note_id": "00000000-0000-0000-0000-000000000002",
                    "payload": {"state": "archived"},
                }
            ]
        }
    )

    assert not serializer.is_valid()
    assert "idempotency_key" in serializer.errors["operations"][0]


def test_conflict_resolution_serializer_accepts_minimal_resolution():
    serializer = ConflictResolutionSerializer(data={})

    assert serializer.is_valid()
    assert serializer.validated_data["resolved"] is True


def test_encrypted_notification_fanout_rejects_plaintext_body(db, django_user_model):
    user = django_user_model.objects.create_user(email="recipient@example.com", password="strong-password")
    serializer = EncryptedNotificationFanoutSerializer(
        data={
            "type": "share_invite",
            "recipients": [
                {
                    "user": str(user.id),
                    "body": "plaintext invite",
                    "encrypted_payload": encrypted_payload(),
                }
            ],
        }
    )

    assert not serializer.is_valid()
    assert "encrypted_payload" in serializer.errors["recipients"][0]


def test_share_invitation_rejects_plaintext_note_key(db, django_user_model):
    owner = django_user_model.objects.create_user(email="share-owner@example.com", password="strong-password")
    recipient = django_user_model.objects.create_user(email="share-recipient@example.com", password="strong-password")
    from apps.notes.models import Note
    from apps.tenants.models import Organization

    tenant = Organization.objects.create(name_ciphertext=encrypted_payload(), owner_user=owner)
    note = Note.objects.create(
        tenant=tenant,
        owner_user=owner,
        encrypted_payload=encrypted_payload(),
        payload_hash=b"server-hash",
        client_updated_at="2026-06-09T00:00:00Z",
    )
    request = type("Request", (), {"user": owner})()
    serializer = ShareInvitationSerializer(
        data={
            "note": str(note.id),
            "recipient_user": str(recipient.id),
            "role": "viewer",
            "content": "plaintext leaked note key",
            "encrypted_note_key": encrypted_payload(),
            "invitation_signature": "signature",
        },
        context={"request": request},
    )

    assert not serializer.is_valid()
    assert "encrypted_payload" in serializer.errors


def test_share_invitation_rejects_owner_role(db, django_user_model):
    owner = django_user_model.objects.create_user(email="role-owner@example.com", password="strong-password")
    recipient = django_user_model.objects.create_user(email="role-recipient@example.com", password="strong-password")
    from apps.notes.models import Note
    from apps.tenants.models import Organization

    tenant = Organization.objects.create(name_ciphertext=encrypted_payload(), owner_user=owner)
    note = Note.objects.create(
        tenant=tenant,
        owner_user=owner,
        encrypted_payload=encrypted_payload(),
        payload_hash=b"server-hash",
        client_updated_at="2026-06-09T00:00:00Z",
    )
    request = type("Request", (), {"user": owner})()
    serializer = ShareInvitationSerializer(
        data={
            "note": str(note.id),
            "recipient_user": str(recipient.id),
            "role": "owner",
            "encrypted_note_key": encrypted_payload(),
            "invitation_signature": "signature",
        },
        context={"request": request},
    )

    assert not serializer.is_valid()


def test_share_invitation_accepts_recipient_email(db, django_user_model):
    owner = django_user_model.objects.create_user(email="email-owner@example.com", password="strong-password")
    recipient = django_user_model.objects.create_user(email="email-recipient@example.com", password="strong-password")
    from apps.notes.models import Note
    from apps.tenants.models import Organization

    tenant = Organization.objects.create(name_ciphertext=encrypted_payload(), owner_user=owner)
    note = Note.objects.create(
        tenant=tenant,
        owner_user=owner,
        encrypted_payload=encrypted_payload(),
        payload_hash=b"server-hash",
        client_updated_at="2026-06-09T00:00:00Z",
    )
    request = type("Request", (), {"user": owner})()
    serializer = ShareInvitationSerializer(
        data={
            "note": str(note.id),
            "recipient_user": recipient.email,
            "role": "viewer",
            "encrypted_note_key": encrypted_payload(),
            "invitation_signature": "signature",
        },
        context={"request": request},
    )

    assert serializer.is_valid(), serializer.errors
    assert serializer.validated_data["recipient_user"] == recipient


def test_ownership_transfer_rejects_plaintext_fields(db, django_user_model):
    user = django_user_model.objects.create_user(email="new-owner@example.com", password="strong-password")
    serializer = OwnershipTransferSerializer(
        data={
            "new_owner_user": str(user.id),
            "title": "plaintext transfer message",
            "encrypted_note_key": encrypted_payload(),
            "transfer_signature": "signature",
        }
    )

    assert not serializer.is_valid()
    assert "encrypted_payload" in serializer.errors

from __future__ import annotations

from html.parser import HTMLParser
from urllib.parse import parse_qs, urlparse

import pytest
from django.core import mail
from django.test import override_settings
from rest_framework import serializers as drf_serializers
from rest_framework.test import APIRequestFactory, force_authenticate

from apps.attachments.serializers import AttachmentSerializer
from apps.collaboration.consumers import valid_encrypted_event_payload
from apps.collaboration.serializers import SyncEventSerializer
from apps.core.storage import encrypted_note_storage_size
from apps.notes.exceptions import VersionConflict
from apps.notes.serializers import (
    ConflictResolutionSerializer,
    NoteSerializer,
    OwnershipTransferSerializer,
    ShareInvitationSerializer,
)
from apps.notes.sync import SyncBatchSerializer
from apps.notes.views import NoteViewSet, ShareInvitationViewSet
from apps.notifications.serializers import (
    EncryptedNotificationFanoutSerializer,
    NotificationSerializer,
)


class _EmailLinkParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            href = dict(attrs).get("href")
            if href:
                self.links.append(href)


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
    user = django_user_model.objects.create_user(
        email="owner@example.com", password="strong-password"
    )
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


def test_note_storage_size_tracks_encrypted_payload_updates(note):
    expected_initial = encrypted_note_storage_size(
        note.encrypted_payload,
        note.payload_hash,
    )
    assert note.storage_bytes == expected_initial

    note.encrypted_payload = {
        **note.encrypted_payload,
        "ciphertext": "a-much-longer-encrypted-payload",
    }
    note.payload_hash = b"updated-server-hash"
    note.save(
        update_fields=[
            "encrypted_payload",
            "payload_hash",
            "updated_at",
        ]
    )
    note.refresh_from_db()

    assert note.storage_bytes == encrypted_note_storage_size(
        note.encrypted_payload,
        note.payload_hash,
    )


def test_empty_trash_permanently_deletes_only_trashed_notes(
    db,
    owner_user,
    tenant,
    note,
    encrypted_payload,
):
    from apps.notes.models import Note

    note.state = "trashed"
    note.save(update_fields=["state", "updated_at"])
    active_note = Note.objects.create(
        tenant=tenant,
        owner_user=owner_user,
        encrypted_payload=encrypted_payload,
        payload_hash=b"active-note",
        client_updated_at="2026-09-08T00:00:00Z",
    )
    request = APIRequestFactory().post("/api/v1/notes/trash/empty/", {}, format="json")
    force_authenticate(request, user=owner_user)

    response = NoteViewSet.as_view({"post": "empty_trash"})(request)

    assert response.status_code == 200
    assert response.data == {"deleted_count": 1}
    note.refresh_from_db()
    active_note.refresh_from_db()
    assert note.state == "deleted"
    assert note.deleted_at is not None
    assert active_note.state == "active"
    assert active_note.deleted_at is None


def test_note_create_rejects_workspace_storage_overflow(
    monkeypatch,
    tenant,
    owner_user,
):
    monkeypatch.setattr(
        "apps.notes.serializers.can_store_note_bytes",
        lambda *args, **kwargs: False,
    )
    request = type("Request", (), {"user": owner_user})()
    serializer = NoteSerializer(
        data={
            "tenant": str(tenant.id),
            "encrypted_payload": encrypted_payload(),
            "payload_hash": "client-hash",
            "client_updated_at": "2026-06-10T00:00:00Z",
        },
        context={"request": request},
    )

    assert serializer.is_valid()
    with pytest.raises(
        drf_serializers.ValidationError,
        match="Workspace storage quota exceeded",
    ):
        serializer.save()


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
    user = django_user_model.objects.create_user(
        email="recipient@example.com", password="strong-password"
    )
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
    owner = django_user_model.objects.create_user(
        email="share-owner@example.com", password="strong-password"
    )
    recipient = django_user_model.objects.create_user(
        email="share-recipient@example.com", password="strong-password"
    )
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
    owner = django_user_model.objects.create_user(
        email="role-owner@example.com", password="strong-password"
    )
    recipient = django_user_model.objects.create_user(
        email="role-recipient@example.com", password="strong-password"
    )
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
    owner = django_user_model.objects.create_user(
        email="email-owner@example.com", password="strong-password"
    )
    recipient = django_user_model.objects.create_user(
        email="email-recipient@example.com", password="strong-password"
    )
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


@pytest.mark.parametrize(
    ("locale", "role", "expected_subject"),
    [
        ("en", "editor", "owner-mail@example.com invited you to edit a note"),
        ("en", "viewer", "owner-mail@example.com invited you to view a note"),
        (
            "de",
            "editor",
            "owner-mail@example.com hat dich eingeladen, eine Notiz zu bearbeiten",
        ),
        ("de", "viewer", "owner-mail@example.com hat eine Notiz mit dir geteilt"),
    ],
)
@override_settings(
    EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend",
    APP_BASE_URL="https://app.safernotes.com/",
    WEBSITE_BASE_URL="https://safernotes.com/",
)
def test_share_invitation_email_has_safe_acceptance_link_in_every_locale(
    db,
    django_user_model,
    locale,
    role,
    expected_subject,
):
    from apps.notes.models import Note, ShareInvitation
    from apps.tenants.models import Organization
    from apps.users.models import Profile

    owner = django_user_model.objects.create_user(
        email="owner-mail@example.com", password="strong-password"
    )
    recipient = django_user_model.objects.create_user(
        email=f"recipient-{locale}-{role}@example.com", password="strong-password"
    )
    Profile.objects.create(user=recipient, locale=locale)
    tenant = Organization.objects.create(name_ciphertext=encrypted_payload(), owner_user=owner)
    note = Note.objects.create(
        tenant=tenant,
        owner_user=owner,
        encrypted_payload=encrypted_payload(),
        payload_hash=b"server-hash",
        client_updated_at="2026-06-09T00:00:00Z",
    )
    request = APIRequestFactory().post(
        "/api/v1/notes/invitations/",
        {
            "note": str(note.id),
            "recipient_user": recipient.email,
            "role": role,
            "encrypted_note_key": encrypted_payload(),
            "invitation_signature": "signature",
        },
        format="json",
    )
    force_authenticate(request, user=owner)

    response = ShareInvitationViewSet.as_view({"post": "create"})(request)

    assert response.status_code == 201
    assert len(mail.outbox) == 1
    message = mail.outbox[0]
    invitation = ShareInvitation.objects.get()
    parser = _EmailLinkParser()
    parser.feed(message.alternatives[0][0])
    invitation_links = [
        link for link in parser.links if link.startswith("https://app.safernotes.com")
    ]

    assert message.subject == expected_subject
    assert len(invitation_links) == 1
    parsed = urlparse(invitation_links[0])
    assert parsed.scheme == "https"
    assert parsed.netloc == "app.safernotes.com"
    assert parse_qs(parsed.query) == {"invitation": [str(invitation.id)]}
    assert invitation_links[0] in message.body
    assert "https://safernotes.com" in parser.links
    assert "localhost" not in message.body
    assert "localhost" not in message.alternatives[0][0]
    assert str(note.id) not in invitation_links[0]
    assert "ciphertext" not in invitation_links[0]
    assert "signature" not in invitation_links[0]


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
def test_duplicate_pending_invitation_sends_one_email(db, django_user_model):
    from apps.notes.models import Note, ShareInvitation
    from apps.tenants.models import Organization

    owner = django_user_model.objects.create_user(
        email="dedupe-owner@example.com", password="strong-password"
    )
    recipient = django_user_model.objects.create_user(
        email="dedupe-recipient@example.com", password="strong-password"
    )
    tenant = Organization.objects.create(name_ciphertext=encrypted_payload(), owner_user=owner)
    note = Note.objects.create(
        tenant=tenant,
        owner_user=owner,
        encrypted_payload=encrypted_payload(),
        payload_hash=b"server-hash",
        client_updated_at="2026-06-09T00:00:00Z",
    )
    payload = {
        "note": str(note.id),
        "recipient_user": recipient.email,
        "role": "viewer",
        "encrypted_note_key": encrypted_payload(),
        "invitation_signature": "signature",
    }
    view = ShareInvitationViewSet.as_view({"post": "create"})
    for _ in range(2):
        request = APIRequestFactory().post("/api/v1/notes/invitations/", payload, format="json")
        force_authenticate(request, user=owner)
        assert view(request).status_code == 201

    assert ShareInvitation.objects.count() == 1
    assert len(mail.outbox) == 1


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
def test_invitation_link_id_opens_recipient_acceptance_flow(db, django_user_model):
    from apps.notes.models import Note, NoteKeyGrant, ShareInvitation
    from apps.tenants.models import Organization

    owner = django_user_model.objects.create_user(
        email="flow-owner@example.com", password="strong-password"
    )
    recipient = django_user_model.objects.create_user(
        email="flow-recipient@example.com", password="strong-password"
    )
    stranger = django_user_model.objects.create_user(
        email="flow-stranger@example.com", password="strong-password"
    )
    tenant = Organization.objects.create(name_ciphertext=encrypted_payload(), owner_user=owner)
    note = Note.objects.create(
        tenant=tenant,
        owner_user=owner,
        encrypted_payload=encrypted_payload(),
        payload_hash=b"server-hash",
        client_updated_at="2026-06-09T00:00:00Z",
    )
    invitation = ShareInvitation.objects.create(
        note=note,
        sender_user=owner,
        recipient_user=recipient,
        role="viewer",
        encrypted_note_key=encrypted_payload(),
        invitation_signature=b"signature",
    )

    retrieve = APIRequestFactory().get(f"/api/v1/notes/invitations/{invitation.id}/")
    force_authenticate(retrieve, user=recipient)
    retrieve_response = ShareInvitationViewSet.as_view({"get": "retrieve"})(
        retrieve, pk=invitation.id
    )

    hidden = APIRequestFactory().get(f"/api/v1/notes/invitations/{invitation.id}/")
    force_authenticate(hidden, user=stranger)
    hidden_response = ShareInvitationViewSet.as_view({"get": "retrieve"})(hidden, pk=invitation.id)

    accept = APIRequestFactory().post(
        f"/api/v1/notes/invitations/{invitation.id}/decide/",
        {"decision": "accept"},
        format="json",
    )
    force_authenticate(accept, user=recipient)
    accept_response = ShareInvitationViewSet.as_view({"post": "decide"})(accept, pk=invitation.id)

    invitation.refresh_from_db()
    assert retrieve_response.status_code == 200
    assert retrieve_response.data["id"] == str(invitation.id)
    assert hidden_response.status_code == 404
    assert accept_response.status_code == 200
    assert invitation.status == "accepted"
    assert NoteKeyGrant.objects.filter(
        source_invitation=invitation,
        recipient_user=recipient,
    ).exists()

    note_payload = NoteSerializer(note, context={"request": accept}).data
    assert note_payload["current_user_role"] == "viewer"
    assert note_payload["current_key_grant"]["encrypted_note_key"] == encrypted_payload()
    assert note_payload["is_shared"] is True


def test_share_invitation_contacts_include_sent_and_received(db, django_user_model):
    from apps.notes.models import Note, ShareInvitation
    from apps.tenants.models import Organization

    user = django_user_model.objects.create_user(
        email="contacts@example.com", password="strong-password"
    )
    sent_contact = django_user_model.objects.create_user(
        email="sent-contact@example.com", password="strong-password"
    )
    received_contact = django_user_model.objects.create_user(
        email="received-contact@example.com", password="strong-password"
    )
    tenant = Organization.objects.create(name_ciphertext=encrypted_payload(), owner_user=user)
    received_tenant = Organization.objects.create(
        name_ciphertext=encrypted_payload(), owner_user=received_contact
    )
    note = Note.objects.create(
        tenant=tenant,
        owner_user=user,
        encrypted_payload=encrypted_payload(),
        payload_hash=b"server-hash",
        client_updated_at="2026-06-09T00:00:00Z",
    )
    received_note = Note.objects.create(
        tenant=received_tenant,
        owner_user=received_contact,
        encrypted_payload=encrypted_payload(),
        payload_hash=b"received-server-hash",
        client_updated_at="2026-06-09T00:00:00Z",
    )
    ShareInvitation.objects.create(
        note=note,
        sender_user=user,
        recipient_user=sent_contact,
        role="editor",
        encrypted_note_key=encrypted_payload(),
        invitation_signature=b"signature",
    )
    ShareInvitation.objects.create(
        note=received_note,
        sender_user=received_contact,
        recipient_user=user,
        role="viewer",
        encrypted_note_key=encrypted_payload(),
        invitation_signature=b"signature",
    )
    request = APIRequestFactory().get("/api/v1/notes/invitations/contacts/")
    force_authenticate(request, user=user)

    response = ShareInvitationViewSet.as_view({"get": "contacts"})(request)

    assert response.status_code == 200
    contacts = response.data["results"]
    assert {item["email"] for item in contacts} == {
        "sent-contact@example.com",
        "received-contact@example.com",
    }
    directions = {item["email"]: item["last_direction"] for item in contacts}
    assert directions["sent-contact@example.com"] == "sent"
    assert directions["received-contact@example.com"] == "received"


def test_ownership_transfer_rejects_plaintext_fields(db, django_user_model):
    user = django_user_model.objects.create_user(
        email="new-owner@example.com", password="strong-password"
    )
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

from __future__ import annotations

import hashlib
import io
from datetime import timedelta
from unittest.mock import Mock
from urllib.parse import urlsplit

import pytest
from asgiref.sync import async_to_sync
from botocore.response import StreamingBody
from django.utils import timezone
from rest_framework.test import APIClient

from apps.attachments.models import Attachment, AttachmentUploadState
from apps.attachments.transfer import transfer_target
from apps.notes.models import CollaboratorRole, NoteKeyGrant


@pytest.fixture
def transfer(settings, monkeypatch, note, tenant, owner_user, encrypted_payload):
    settings.ATTACHMENT_PROXY_ENABLED = True
    settings.APP_BASE_URL = "https://notes.example.com"
    content = b"encrypted-content"
    attachment = Attachment.objects.create(
        note=note,
        tenant=tenant,
        object_key="attachments/test",
        ciphertext_size=len(content),
        ciphertext_sha256=hashlib.sha256(content).hexdigest().encode(),
        encrypted_metadata=encrypted_payload,
        upload_expires_at=timezone.now() + timedelta(minutes=5),
    )
    client = Mock()
    stored = {}

    def put_object(**kwargs):
        stored["body"] = kwargs["Body"].read()

    def get_object(**kwargs):
        body = stored.get("body", content)
        return {"Body": StreamingBody(io.BytesIO(body), len(body)), "ContentLength": len(body)}

    client.put_object.side_effect = put_object
    client.get_object.side_effect = get_object
    monkeypatch.setattr("apps.attachments.transfer.s3_client", lambda: client)
    return attachment, content, client, stored


def target_path(attachment, user, method):
    target = transfer_target(attachment, user, method)
    url = urlsplit(target.url)
    assert url.netloc == "notes.example.com"
    assert url.path.startswith("/api/v1/attachments/")
    return url.path + "?" + url.query


def test_transfer_round_trip(transfer, owner_user):
    attachment, content, storage, stored = transfer
    anonymous = APIClient()
    upload = target_path(attachment, owner_user, "PUT")
    assert (
        anonymous.put(upload, content, content_type="application/octet-stream").status_code == 204
    )
    assert stored["body"] == content
    attachment.refresh_from_db()
    assert attachment.upload_state == AttachmentUploadState.UPLOADED
    authenticated = APIClient()
    authenticated.force_authenticate(owner_user)
    complete = authenticated.put(
        f"/api/v1/attachments/{attachment.pk}/complete/",
        {"ciphertext_sha256": bytes(attachment.ciphertext_sha256).decode()},
        format="json",
    )
    assert complete.status_code == 200
    result = authenticated.get(f"/api/v1/attachments/{attachment.pk}/download/")
    assert result.status_code == 200
    url = urlsplit(result.data["download"]["url"])
    downloaded = anonymous.get(url.path + "?" + url.query)
    assert downloaded.status_code == 200

    async def consume():
        return b"".join([chunk async for chunk in downloaded.streaming_content])

    assert async_to_sync(consume)() == content
    downloaded.close()
    assert downloaded["Cache-Control"] == "no-store"
    assert (
        anonymous.put(upload, content, content_type="application/octet-stream").status_code == 400
    )
    assert storage.put_object.call_count == 1


@pytest.mark.parametrize("body", [b"", b"too-short", b"x" * 18, b"x" * 17])
def test_upload_rejects_wrong_length_or_hash(transfer, owner_user, body):
    attachment, _, storage, _ = transfer
    result = APIClient().put(
        target_path(attachment, owner_user, "PUT"), body, content_type="application/octet-stream"
    )
    assert result.status_code == 400
    storage.put_object.assert_not_called()


def test_invalid_missing_expired_and_wrong_method_links(transfer, owner_user, monkeypatch):
    attachment, content, storage, _ = transfer
    client = APIClient()
    path = target_path(attachment, owner_user, "PUT")
    assert client.get(path).status_code == 403
    assert (
        client.put(path + "tampered", content, content_type="application/octet-stream").status_code
        == 403
    )
    assert (
        client.put(path.split("?")[0], content, content_type="application/octet-stream").status_code
        == 403
    )
    import time

    future = time.time() + 2000
    monkeypatch.setattr("django.core.signing.time.time", lambda: future)
    assert client.put(path, content, content_type="application/octet-stream").status_code == 403
    storage.put_object.assert_not_called()


def test_other_user_and_other_object_cannot_use_link(transfer, recipient_user, owner_user):
    attachment, content, storage, _ = transfer
    url = target_path(attachment, recipient_user, "PUT")
    assert APIClient().put(url, content, content_type="application/octet-stream").status_code == 404
    url = target_path(attachment, owner_user, "PUT").replace(
        str(attachment.pk), "00000000-0000-0000-0000-000000000001", 1
    )
    assert APIClient().put(url, content, content_type="application/octet-stream").status_code == 403
    storage.put_object.assert_not_called()


def test_completion_requires_verified_upload_and_no_metadata_overwrite(transfer, owner_user):
    attachment, _, storage, _ = transfer
    client = APIClient()
    client.force_authenticate(owner_user)
    path = f"/api/v1/attachments/{attachment.pk}/"
    assert (
        client.put(
            path + "complete/",
            {"ciphertext_sha256": bytes(attachment.ciphertext_sha256).decode()},
            format="json",
        ).status_code
        == 400
    )
    assert client.patch(path, {"ciphertext_size": 1}, format="json").status_code == 405
    assert client.get(path + "download/").status_code == 400
    storage.put_object.assert_not_called()


def test_transfer_disabled_outside_proxy_mode(transfer, owner_user, settings):
    attachment, _, _, _ = transfer
    url = target_path(attachment, owner_user, "GET")
    settings.ATTACHMENT_PROXY_ENABLED = False
    assert APIClient().get(url).status_code == 404


def test_expired_upload_and_aborted_upload(transfer, owner_user):
    attachment, content, storage, _ = transfer
    url = target_path(attachment, owner_user, "PUT")
    attachment.upload_expires_at = timezone.now() - timedelta(seconds=1)
    attachment.save()
    assert APIClient().put(url, content, content_type="application/octet-stream").status_code == 400
    attachment.upload_state = AttachmentUploadState.ABORTED
    attachment.save()
    assert APIClient().put(url, content, content_type="application/octet-stream").status_code == 400
    storage.put_object.assert_not_called()


def test_viewer_read_only_and_revocation(transfer, owner_user, recipient_user, encrypted_payload):
    attachment, content, storage, _ = transfer
    grant = NoteKeyGrant.objects.create(
        note=attachment.note,
        recipient_user=recipient_user,
        sender_user=owner_user,
        role=CollaboratorRole.VIEWER,
        encrypted_note_key=encrypted_payload,
        grant_signature=b"signature",
    )
    upload = target_path(attachment, recipient_user, "PUT")
    assert (
        APIClient().put(upload, content, content_type="application/octet-stream").status_code == 403
    )
    storage.put_object.assert_not_called()
    attachment.upload_state = AttachmentUploadState.COMPLETE
    attachment.save()
    download = target_path(attachment, recipient_user, "GET")
    result = APIClient().get(download)
    assert result.status_code == 200
    result.close()
    grant.revoked_at = timezone.now()
    grant.save()
    assert APIClient().get(download).status_code == 404


def test_storage_failure_does_not_mark_uploaded(transfer, owner_user):
    from botocore.exceptions import ClientError

    attachment, content, storage, _ = transfer
    storage.put_object.side_effect = ClientError(
        {"Error": {"Code": "Unavailable", "Message": "private-storage-details"}}, "PutObject"
    )
    result = APIClient().put(
        target_path(attachment, owner_user, "PUT"), content, content_type="application/octet-stream"
    )
    assert result.status_code == 503
    assert b"private-storage-details" not in result.content
    attachment.refresh_from_db()
    assert attachment.upload_state == AttachmentUploadState.INITIATED


def test_inactive_user_cannot_use_issued_link(transfer, owner_user):
    attachment, content, storage, _ = transfer
    upload = target_path(attachment, owner_user, "PUT")
    owner_user.is_active = False
    owner_user.save()
    assert (
        APIClient().put(upload, content, content_type="application/octet-stream").status_code == 403
    )
    storage.put_object.assert_not_called()

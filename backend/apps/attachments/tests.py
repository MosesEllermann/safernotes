from __future__ import annotations

from datetime import timedelta

from django.utils import timezone

from apps.attachments.models import AttachmentUploadState, size_bucket_for
from apps.attachments.quota import can_reserve_attachment_bytes
from apps.attachments.serializers import AttachmentCompleteSerializer, AttachmentSerializer


def encrypted_payload():
    return {
        "version": 1,
        "algorithm": "XCHACHA20_POLY1305",
        "nonce": "nonce",
        "ciphertext": "ciphertext",
    }


class FakeAttachment:
    upload_state = AttachmentUploadState.INITIATED
    ciphertext_sha256 = b"expected-hash"
    upload_expires_at = timezone.now() + timedelta(minutes=5)


def test_attachment_serializer_rejects_plaintext_filename():
    serializer = AttachmentSerializer(
        data={
            "tenant": "00000000-0000-0000-0000-000000000001",
            "note": "00000000-0000-0000-0000-000000000002",
            "filename": "private.pdf",
            "ciphertext_size": 1024,
            "ciphertext_sha256": "expected-hash",
            "encrypted_metadata": encrypted_payload(),
        }
    )

    assert not serializer.is_valid()
    assert "encrypted_payload" in serializer.errors


def test_attachment_complete_rejects_checksum_mismatch():
    serializer = AttachmentCompleteSerializer(
        data={"ciphertext_sha256": "different-hash"},
        context={"attachment": FakeAttachment()},
    )

    assert not serializer.is_valid()


def test_attachment_complete_rejects_expired_upload():
    attachment = FakeAttachment()
    attachment.upload_expires_at = timezone.now() - timedelta(seconds=1)
    serializer = AttachmentCompleteSerializer(
        data={"ciphertext_sha256": "expected-hash"},
        context={"attachment": attachment},
    )

    assert not serializer.is_valid()


def test_attachment_size_buckets():
    assert size_bucket_for(1024) == "le_1mb"
    assert size_bucket_for(2 * 1024 * 1024) == "le_10mb"
    assert size_bucket_for(20 * 1024 * 1024) == "le_100mb"
    assert size_bucket_for(200 * 1024 * 1024) == "gt_100mb"


def test_note_storage_counts_toward_attachment_quota(monkeypatch, tenant, note):
    monkeypatch.setattr(
        "apps.attachments.quota.quota_for_tenant",
        lambda _: note.storage_bytes + 100,
    )

    assert can_reserve_attachment_bytes(tenant, 100)
    assert not can_reserve_attachment_bytes(tenant, 101)

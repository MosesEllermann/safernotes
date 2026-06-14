from __future__ import annotations

from django.db import models

from apps.core.models import EncryptedJSONField, TimeStampedUUIDModel


class AttachmentUploadState(models.TextChoices):
    INITIATED = "initiated", "Initiated"
    UPLOADED = "uploaded", "Uploaded"
    COMPLETE = "complete", "Complete"
    ABORTED = "aborted", "Aborted"
    DELETED = "deleted", "Deleted"


class Attachment(TimeStampedUUIDModel):
    tenant = models.ForeignKey("tenants.Organization", on_delete=models.CASCADE, related_name="attachments")
    note = models.ForeignKey("notes.Note", on_delete=models.CASCADE, related_name="attachments")
    object_key = models.CharField(max_length=512, unique=True)
    ciphertext_size = models.PositiveBigIntegerField()
    ciphertext_sha256 = models.BinaryField()
    encrypted_metadata = EncryptedJSONField()
    upload_state = models.CharField(
        max_length=32,
        choices=AttachmentUploadState.choices,
        default=AttachmentUploadState.INITIATED,
    )
    upload_expires_at = models.DateTimeField(null=True, blank=True)
    completed_at = models.DateTimeField(null=True, blank=True)
    deleted_at = models.DateTimeField(null=True, blank=True)
    size_bucket = models.CharField(max_length=32, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=["tenant", "note"]),
            models.Index(fields=["tenant", "upload_state"]),
            models.Index(fields=["upload_expires_at"]),
        ]


class TenantStorageUsage(TimeStampedUUIDModel):
    tenant = models.OneToOneField("tenants.Organization", on_delete=models.CASCADE, related_name="storage_usage")
    ciphertext_bytes_used = models.PositiveBigIntegerField(default=0)
    attachments_count = models.PositiveBigIntegerField(default=0)


def size_bucket_for(ciphertext_size: int) -> str:
    if ciphertext_size <= 1024 * 1024:
        return "le_1mb"
    if ciphertext_size <= 10 * 1024 * 1024:
        return "le_10mb"
    if ciphertext_size <= 100 * 1024 * 1024:
        return "le_100mb"
    return "gt_100mb"

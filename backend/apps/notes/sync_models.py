from __future__ import annotations

from django.db import models

from apps.core.models import TimeStampedUUIDModel


class SyncCheckpoint(TimeStampedUUIDModel):
    user = models.ForeignKey("users.User", on_delete=models.CASCADE, related_name="sync_checkpoints")
    device = models.ForeignKey(
        "devices.Device", null=True, blank=True, on_delete=models.CASCADE, related_name="sync_checkpoints"
    )
    cursor = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["user", "device"], name="unique_user_device_sync_checkpoint")
        ]
        indexes = [models.Index(fields=["user", "updated_at"])]


class SyncOperationReceipt(TimeStampedUUIDModel):
    user = models.ForeignKey("users.User", on_delete=models.CASCADE, related_name="sync_receipts")
    device = models.ForeignKey(
        "devices.Device", null=True, blank=True, on_delete=models.SET_NULL, related_name="sync_receipts"
    )
    idempotency_key = models.CharField(max_length=128)
    operation_type = models.CharField(max_length=32)
    result = models.JSONField(default=dict)

    class Meta:
        constraints = [
            models.UniqueConstraint(
                fields=["user", "idempotency_key"],
                name="unique_user_sync_idempotency_key",
            )
        ]
        indexes = [models.Index(fields=["user", "created_at"])]


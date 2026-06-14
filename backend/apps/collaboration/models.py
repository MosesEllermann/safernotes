from __future__ import annotations

from django.db import models

from apps.core.models import EncryptedJSONField, TimeStampedUUIDModel


class SyncEvent(TimeStampedUUIDModel):
    tenant = models.ForeignKey("tenants.Organization", on_delete=models.CASCADE, related_name="sync_events")
    note = models.ForeignKey("notes.Note", on_delete=models.CASCADE, related_name="sync_events")
    actor_user = models.ForeignKey("users.User", on_delete=models.PROTECT, related_name="sync_events")
    note_version = models.PositiveBigIntegerField()
    encrypted_delta = EncryptedJSONField()
    event_signature = models.BinaryField()

    class Meta:
        indexes = [models.Index(fields=["tenant", "created_at"]), models.Index(fields=["note", "created_at"])]


class SyncEventAck(TimeStampedUUIDModel):
    event = models.ForeignKey(SyncEvent, on_delete=models.CASCADE, related_name="acks")
    user = models.ForeignKey("users.User", on_delete=models.CASCADE, related_name="sync_event_acks")
    device = models.ForeignKey(
        "devices.Device", null=True, blank=True, on_delete=models.SET_NULL, related_name="sync_event_acks"
    )
    received_at = models.DateTimeField()

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["event", "user", "device"], name="unique_event_user_device_ack")
        ]
        indexes = [models.Index(fields=["user", "created_at"])]


class CollaborationPresence(TimeStampedUUIDModel):
    note = models.ForeignKey("notes.Note", on_delete=models.CASCADE, related_name="presence")
    user = models.ForeignKey("users.User", on_delete=models.CASCADE, related_name="collaboration_presence")
    device = models.ForeignKey(
        "devices.Device", null=True, blank=True, on_delete=models.SET_NULL, related_name="collaboration_presence"
    )
    status = models.CharField(max_length=32, default="offline")

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["note", "user", "device"], name="unique_note_user_device_presence")
        ]
        indexes = [models.Index(fields=["note", "status", "updated_at"])]

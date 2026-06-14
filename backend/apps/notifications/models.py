from __future__ import annotations

from django.db import models

from apps.core.models import EncryptedJSONField, TimeStampedUUIDModel


class Notification(TimeStampedUUIDModel):
    user = models.ForeignKey("users.User", on_delete=models.CASCADE, related_name="notifications")
    type = models.CharField(max_length=64)
    encrypted_payload = EncryptedJSONField()
    read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["user", "read_at", "created_at"])]


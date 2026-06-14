from __future__ import annotations

from django.db import models

from apps.core.models import EncryptedJSONField, TimeStampedUUIDModel


class Device(TimeStampedUUIDModel):
    user = models.ForeignKey("users.User", on_delete=models.CASCADE, related_name="devices")
    name_ciphertext = EncryptedJSONField()
    public_signing_key = models.BinaryField()
    last_seen_at = models.DateTimeField(null=True, blank=True)
    revoked_at = models.DateTimeField(null=True, blank=True)
    trusted_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["user", "revoked_at"])]


from __future__ import annotations

import uuid

from django.db import models


class TimeStampedUUIDModel(models.Model):
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        abstract = True


class EncryptedJSONField(models.JSONField):
    """JSON envelope that must contain ciphertext, never plaintext content."""

    description = "Encrypted JSON envelope"


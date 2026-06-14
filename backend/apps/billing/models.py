from __future__ import annotations

from django.db import models

from apps.core.models import TimeStampedUUIDModel


class BillingEvent(TimeStampedUUIDModel):
    provider = models.CharField(max_length=32)
    provider_event_id = models.CharField(max_length=255, unique=True)
    event_type = models.CharField(max_length=128)
    payload = models.JSONField()
    signature_valid = models.BooleanField(default=False)
    processing_status = models.CharField(max_length=32, default="received")
    processed_at = models.DateTimeField(null=True, blank=True)

from __future__ import annotations

from django.db import models

from apps.core.models import TimeStampedUUIDModel


class AuditEvent(TimeStampedUUIDModel):
    tenant = models.ForeignKey(
        "tenants.Organization", null=True, blank=True, on_delete=models.SET_NULL, related_name="audit_events"
    )
    actor_user = models.ForeignKey(
        "users.User", null=True, blank=True, on_delete=models.SET_NULL, related_name="audit_events"
    )
    event_type = models.CharField(max_length=128)
    target_type = models.CharField(max_length=64)
    target_id = models.UUIDField(null=True, blank=True)
    metadata = models.JSONField(default=dict)
    signature = models.BinaryField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["tenant", "created_at"]), models.Index(fields=["event_type"])]


from __future__ import annotations

from django.db import models

from apps.core.models import TimeStampedUUIDModel


class Subscription(TimeStampedUUIDModel):
    tenant = models.OneToOneField(
        "tenants.Organization", on_delete=models.CASCADE, related_name="subscription"
    )
    plan = models.CharField(max_length=32, default="free")
    status = models.CharField(max_length=32, default="active")
    billing_provider = models.CharField(max_length=32, blank=True)
    provider_customer_id = models.CharField(max_length=255, blank=True)
    provider_subscription_id = models.CharField(max_length=255, blank=True)
    current_period_end = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [models.Index(fields=["plan", "status"])]


from __future__ import annotations

from django.db import models

from apps.core.models import EncryptedJSONField, TimeStampedUUIDModel


class Organization(TimeStampedUUIDModel):
    name_ciphertext = EncryptedJSONField()
    plan = models.CharField(max_length=32, default="free")
    owner_user = models.ForeignKey("users.User", on_delete=models.PROTECT, related_name="owned_tenants")


class Membership(TimeStampedUUIDModel):
    tenant = models.ForeignKey(Organization, on_delete=models.CASCADE, related_name="memberships")
    user = models.ForeignKey("users.User", on_delete=models.CASCADE, related_name="memberships")
    role = models.CharField(max_length=32)
    status = models.CharField(max_length=32, default="active")

    class Meta:
        constraints = [
            models.UniqueConstraint(fields=["tenant", "user"], name="unique_tenant_membership")
        ]


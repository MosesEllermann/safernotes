from __future__ import annotations

from apps.attachments.models import TenantStorageUsage
from apps.subscriptions.plans import policy_for_plan


def quota_for_tenant(tenant) -> int:
    return policy_for_plan(tenant.plan).storage_bytes


def usage_for_tenant(tenant) -> TenantStorageUsage:
    usage, _ = TenantStorageUsage.objects.get_or_create(tenant=tenant)
    return usage


def can_reserve_attachment_bytes(tenant, ciphertext_size: int) -> bool:
    usage = usage_for_tenant(tenant)
    return usage.ciphertext_bytes_used + ciphertext_size <= quota_for_tenant(tenant)


def reserve_attachment_bytes(tenant, ciphertext_size: int) -> TenantStorageUsage:
    usage = usage_for_tenant(tenant)
    usage.ciphertext_bytes_used += ciphertext_size
    usage.attachments_count += 1
    usage.save(update_fields=["ciphertext_bytes_used", "attachments_count", "updated_at"])
    return usage


def release_attachment_bytes(tenant, ciphertext_size: int) -> TenantStorageUsage:
    usage = usage_for_tenant(tenant)
    usage.ciphertext_bytes_used = max(0, usage.ciphertext_bytes_used - ciphertext_size)
    usage.attachments_count = max(0, usage.attachments_count - 1)
    usage.save(update_fields=["ciphertext_bytes_used", "attachments_count", "updated_at"])
    return usage

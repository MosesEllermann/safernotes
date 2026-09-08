from __future__ import annotations

from django.db import transaction
from django.db.models import Sum

from apps.attachments.models import TenantStorageUsage
from apps.subscriptions.plans import policy_for_plan


def quota_for_tenant(tenant) -> int:
    return policy_for_plan(tenant.plan).storage_bytes


def usage_for_tenant(tenant) -> TenantStorageUsage:
    usage, _ = TenantStorageUsage.objects.get_or_create(tenant=tenant)
    return usage


def locked_usage_for_tenant(tenant) -> TenantStorageUsage:
    usage = usage_for_tenant(tenant)
    return TenantStorageUsage.objects.select_for_update().get(pk=usage.pk)


def note_bytes_for_tenant(tenant) -> int:
    from apps.notes.models import Note

    result = (
        Note.objects.filter(tenant=tenant)
        .exclude(state="deleted")
        .aggregate(total=Sum("storage_bytes"))
    )
    return int(result["total"] or 0)


def storage_breakdown_for_tenant(
    tenant,
    *,
    attachment_usage: TenantStorageUsage | None = None,
) -> dict[str, int]:
    usage = attachment_usage or usage_for_tenant(tenant)
    notes_bytes = note_bytes_for_tenant(tenant)
    attachment_bytes = int(usage.ciphertext_bytes_used)
    return {
        "notes_bytes_used": notes_bytes,
        "attachments_bytes_used": attachment_bytes,
        "storage_bytes_used": notes_bytes + attachment_bytes,
    }


def can_store_note_bytes(
    tenant,
    *,
    previous_bytes: int,
    next_bytes: int,
    attachment_usage: TenantStorageUsage | None = None,
) -> bool:
    breakdown = storage_breakdown_for_tenant(
        tenant,
        attachment_usage=attachment_usage,
    )
    projected = breakdown["storage_bytes_used"] - previous_bytes + next_bytes
    return projected <= quota_for_tenant(tenant)


def can_reserve_attachment_bytes(tenant, ciphertext_size: int) -> bool:
    breakdown = storage_breakdown_for_tenant(tenant)
    return breakdown["storage_bytes_used"] + ciphertext_size <= quota_for_tenant(tenant)


def reserve_attachment_bytes(tenant, ciphertext_size: int) -> TenantStorageUsage | None:
    with transaction.atomic():
        usage = locked_usage_for_tenant(tenant)
        breakdown = storage_breakdown_for_tenant(
            tenant,
            attachment_usage=usage,
        )
        if breakdown["storage_bytes_used"] + ciphertext_size > quota_for_tenant(tenant):
            return None
        usage.ciphertext_bytes_used += ciphertext_size
        usage.attachments_count += 1
        usage.save(update_fields=["ciphertext_bytes_used", "attachments_count", "updated_at"])
        return usage


def release_attachment_bytes(tenant, ciphertext_size: int) -> TenantStorageUsage:
    with transaction.atomic():
        usage = locked_usage_for_tenant(tenant)
        usage.ciphertext_bytes_used = max(0, usage.ciphertext_bytes_used - ciphertext_size)
        usage.attachments_count = max(0, usage.attachments_count - 1)
        usage.save(update_fields=["ciphertext_bytes_used", "attachments_count", "updated_at"])
        return usage

from __future__ import annotations

from apps.attachments.quota import storage_breakdown_for_tenant, usage_for_tenant
from apps.notes.models import Note
from apps.subscriptions.plans import policy_for_plan


def usage_report_for_tenant(tenant) -> dict:
    storage = usage_for_tenant(tenant)
    breakdown = storage_breakdown_for_tenant(tenant, attachment_usage=storage)
    policy = policy_for_plan(tenant.plan)
    notes_count = Note.objects.filter(tenant=tenant).exclude(state="deleted").count()
    return {
        "tenant": str(tenant.id),
        "plan": tenant.plan,
        "policy": policy.as_dict(),
        "usage": {
            "storage_bytes_used": breakdown["storage_bytes_used"],
            "ciphertext_bytes_used": breakdown["storage_bytes_used"],
            "notes_bytes_used": breakdown["notes_bytes_used"],
            "attachments_bytes_used": breakdown["attachments_bytes_used"],
            "attachments_count": storage.attachments_count,
            "notes_count": notes_count,
        },
        "limits": {
            "storage_bytes": policy.storage_bytes,
            "max_notes": policy.max_notes,
            "max_attachment_bytes": policy.max_attachment_bytes,
            "max_collaborators_per_note": policy.max_collaborators_per_note,
        },
    }

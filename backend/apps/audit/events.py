from __future__ import annotations

import json
from hashlib import sha256

from django.conf import settings

from apps.audit.models import AuditEvent
from apps.core.security import redact_value


def audit_signature(event_type: str, target_type: str, target_id, metadata: dict) -> bytes:
    payload = json.dumps(
        {
            "event_type": event_type,
            "target_type": target_type,
            "target_id": str(target_id) if target_id else None,
            "metadata": redact_value(metadata),
        },
        sort_keys=True,
    )
    return sha256((settings.SECRET_KEY + payload).encode("utf-8")).hexdigest().encode("utf-8")


def record_audit_event(
    *,
    event_type: str,
    actor_user=None,
    tenant=None,
    target_type: str,
    target_id=None,
    metadata: dict | None = None,
) -> AuditEvent:
    safe_metadata = redact_value(metadata or {})
    signature = audit_signature(event_type, target_type, target_id, safe_metadata)
    return AuditEvent.objects.create(
        tenant=tenant,
        actor_user=actor_user if getattr(actor_user, "is_authenticated", False) else None,
        event_type=event_type,
        target_type=target_type,
        target_id=target_id,
        metadata=safe_metadata,
        signature=signature,
    )


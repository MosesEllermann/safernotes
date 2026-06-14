from __future__ import annotations

from django.utils import dateparse, timezone

from apps.subscriptions.models import Subscription
from apps.subscriptions.plans import PLAN_POLICIES
from apps.tenants.models import Organization


def process_billing_event(event) -> None:
    payload = event.payload
    event_type = event.event_type
    tenant_id = payload.get("tenant_id")
    if not tenant_id:
        event.processing_status = "ignored"
        event.processed_at = timezone.now()
        event.save(update_fields=["processing_status", "processed_at", "updated_at"])
        return

    tenant = Organization.objects.filter(id=tenant_id).first()
    if tenant is None:
        event.processing_status = "tenant-not-found"
        event.processed_at = timezone.now()
        event.save(update_fields=["processing_status", "processed_at", "updated_at"])
        return

    if event_type in {"subscription.created", "subscription.updated"}:
        plan = payload.get("plan", tenant.plan)
        if plan not in PLAN_POLICIES:
            plan = "free"
        status = payload.get("status", "active")
        period_end = payload.get("current_period_end")
        subscription, _ = Subscription.objects.update_or_create(
            tenant=tenant,
            defaults={
                "plan": plan,
                "status": status,
                "billing_provider": event.provider,
                "provider_customer_id": payload.get("provider_customer_id", ""),
                "provider_subscription_id": payload.get("provider_subscription_id", ""),
                "current_period_end": dateparse.parse_datetime(period_end) if period_end else None,
            },
        )
        tenant.plan = subscription.plan
        tenant.save(update_fields=["plan", "updated_at"])
        event.processing_status = "processed"
    elif event_type in {"subscription.deleted", "subscription.canceled"}:
        Subscription.objects.update_or_create(
            tenant=tenant,
            defaults={
                "plan": "free",
                "status": "canceled",
                "billing_provider": event.provider,
            },
        )
        tenant.plan = "free"
        tenant.save(update_fields=["plan", "updated_at"])
        event.processing_status = "processed"
    else:
        event.processing_status = "ignored"

    event.processed_at = timezone.now()
    event.save(update_fields=["processing_status", "processed_at", "updated_at"])

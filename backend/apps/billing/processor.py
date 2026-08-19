from __future__ import annotations

from django.utils import dateparse, timezone

from apps.subscriptions.models import Subscription
from apps.subscriptions.plans import PLAN_POLICIES
from apps.tenants.models import Organization

LEMONSQUEEZY_EVENT_TYPES = {
    "subscription_created": "subscription.created",
    "subscription_updated": "subscription.updated",
    "subscription_cancelled": "subscription.canceled",
    "subscription_expired": "subscription.canceled",
    "subscription_payment_recovered": "subscription.updated",
}


PADDLE_CANCELED_STATUSES = {"canceled", "past_due", "paused"}


def normalize_billing_event(provider: str, event_type: str, payload: dict) -> tuple[str, dict]:
    if provider == "paddle" and "data" in payload:
        return normalize_paddle_event(event_type, payload)
    if provider != "lemonsqueezy" or "meta" not in payload:
        return event_type, payload

    meta = payload.get("meta") or {}
    custom_data = meta.get("custom_data") or {}
    data = payload.get("data") or {}
    attributes = data.get("attributes") or {}

    return LEMONSQUEEZY_EVENT_TYPES.get(meta.get("event_name"), event_type), {
        "tenant_id": custom_data.get("tenant_id"),
        "plan": custom_data.get("plan"),
        "status": attributes.get("status", "active"),
        "provider_customer_id": str(attributes.get("customer_id", "")),
        "provider_subscription_id": str(data.get("id", "")),
        "current_period_end": attributes.get("renews_at") or attributes.get("ends_at"),
    }


def normalize_paddle_event(event_type: str, payload: dict) -> tuple[str, dict]:
    data = payload.get("data") or {}
    custom_data = data.get("custom_data") or {}
    current_billing_period = data.get("current_billing_period") or {}
    status = data.get("status", "active")
    normalized_type = event_type
    if event_type == "subscription.activated":
        normalized_type = "subscription.created"
    elif event_type in {"subscription.canceled", "subscription.paused"} or status in PADDLE_CANCELED_STATUSES:
        normalized_type = "subscription.canceled"
    elif event_type in {"subscription.created", "subscription.updated"}:
        normalized_type = event_type

    return normalized_type, {
        "tenant_id": custom_data.get("tenant_id"),
        "plan": custom_data.get("plan"),
        "status": status,
        "provider_customer_id": data.get("customer_id", ""),
        "provider_subscription_id": data.get("id", ""),
        "current_period_end": current_billing_period.get("ends_at"),
    }


def process_billing_event(event) -> None:
    event_type, payload = normalize_billing_event(event.provider, event.event_type, event.payload)
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

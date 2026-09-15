from __future__ import annotations

from django.conf import settings
from django.utils import dateparse, timezone

from apps.subscriptions.models import Subscription
from apps.subscriptions.plans import PLAN_POLICIES
from apps.tenants.models import Organization

CREEM_ACTIVE_EVENTS = {
    "checkout.completed",
    "subscription.active",
    "subscription.paid",
    "subscription.trialing",
    "subscription.update",
    "subscription.scheduled_cancel",
    "subscription.past_due",
    "subscription.expired",
}
CREEM_TERMINAL_EVENTS = {
    "subscription.canceled",
    "subscription.paused",
    "subscription.unpaid",
    "refund.created",
    "dispute.created",
}
CREEM_TERMINAL_STATUSES = {"canceled", "paused", "unpaid"}


def _entity_id(value) -> str:
    if isinstance(value, dict):
        return str(value.get("id") or "")
    return str(value or "")


def _creem_plan(metadata: dict, product) -> str | None:
    plan = metadata.get("plan")
    if plan in PLAN_POLICIES:
        return plan

    product_id = _entity_id(product)
    return next(
        (
            configured_plan
            for configured_plan, configured_product_id in settings.BILLING_PRODUCT_IDS.items()
            if configured_product_id == product_id
        ),
        None,
    )


def normalize_creem_event(event_type: str, payload: dict) -> tuple[str, dict]:
    event_object = payload.get("object") or {}
    data = event_object

    if event_type == "checkout.completed":
        subscription = event_object.get("subscription")
        if not subscription:
            return event_type, {}
        data = subscription if isinstance(subscription, dict) else {"id": subscription}
    elif event_type in {"refund.created", "dispute.created"}:
        subscription = event_object.get("subscription")
        data = subscription if isinstance(subscription, dict) else {"id": subscription}

    checkout = event_object.get("checkout") or {}
    metadata = (
        event_object.get("metadata") or data.get("metadata") or checkout.get("metadata") or {}
    )
    product = data.get("product") or event_object.get("product")
    customer = data.get("customer") or event_object.get("customer")
    status = data.get("status") or event_object.get("status") or "active"

    if event_type in CREEM_TERMINAL_EVENTS or status in CREEM_TERMINAL_STATUSES:
        normalized_type = "subscription.canceled"
    elif event_type in CREEM_ACTIVE_EVENTS:
        normalized_type = (
            "subscription.created"
            if event_type in {"checkout.completed", "subscription.active"}
            else "subscription.updated"
        )
    else:
        normalized_type = event_type

    return normalized_type, {
        "tenant_id": metadata.get("tenant_id"),
        "plan": _creem_plan(metadata, product),
        "status": status,
        "provider_customer_id": _entity_id(customer),
        "provider_subscription_id": _entity_id(data),
        "current_period_end": data.get("current_period_end_date"),
    }


def normalize_billing_event(provider: str, event_type: str, payload: dict) -> tuple[str, dict]:
    if provider == "creem":
        return normalize_creem_event(event_type, payload)
    return event_type, payload


def process_billing_event(event) -> None:
    event_type, payload = normalize_billing_event(event.provider, event.event_type, event.payload)
    tenant_id = payload.get("tenant_id")
    provider_subscription_id = payload.get("provider_subscription_id")
    tenant = Organization.objects.filter(id=tenant_id).first() if tenant_id else None
    if tenant is None and provider_subscription_id:
        known_subscription = (
            Subscription.objects.select_related("tenant")
            .filter(
                billing_provider=event.provider,
                provider_subscription_id=provider_subscription_id,
            )
            .first()
        )
        tenant = known_subscription.tenant if known_subscription else None

    if tenant is None and not tenant_id:
        event.processing_status = "ignored"
        event.processed_at = timezone.now()
        event.save(update_fields=["processing_status", "processed_at", "updated_at"])
        return
    if tenant is None:
        event.processing_status = "tenant-not-found"
        event.processed_at = timezone.now()
        event.save(update_fields=["processing_status", "processed_at", "updated_at"])
        return

    if event_type in {"subscription.created", "subscription.updated"}:
        existing_subscription = Subscription.objects.filter(tenant=tenant).first()
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
                "provider_customer_id": payload.get("provider_customer_id")
                or getattr(existing_subscription, "provider_customer_id", ""),
                "provider_subscription_id": payload.get("provider_subscription_id")
                or getattr(existing_subscription, "provider_subscription_id", ""),
                "current_period_end": dateparse.parse_datetime(period_end) if period_end else None,
            },
        )
        tenant.plan = subscription.plan
        tenant.save(update_fields=["plan", "updated_at"])
        event.processing_status = "processed"
    elif event_type in {"subscription.deleted", "subscription.canceled"}:
        existing_subscription = Subscription.objects.filter(tenant=tenant).first()
        Subscription.objects.update_or_create(
            tenant=tenant,
            defaults={
                "plan": "free",
                "status": "canceled",
                "billing_provider": event.provider,
                "provider_customer_id": payload.get("provider_customer_id")
                or getattr(existing_subscription, "provider_customer_id", ""),
                "provider_subscription_id": payload.get("provider_subscription_id")
                or getattr(existing_subscription, "provider_subscription_id", ""),
            },
        )
        tenant.plan = "free"
        tenant.save(update_fields=["plan", "updated_at"])
        event.processing_status = "processed"
    else:
        event.processing_status = "ignored"

    event.processed_at = timezone.now()
    event.save(update_fields=["processing_status", "processed_at", "updated_at"])

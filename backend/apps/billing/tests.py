from __future__ import annotations

from django.test import override_settings

from apps.billing.models import BillingEvent
from apps.billing.processor import process_billing_event
from apps.billing.signatures import (
    expected_paddle_signature,
    expected_signature,
    verify_webhook_signature,
)


@override_settings(BILLING_WEBHOOK_SECRET="secret")
def test_billing_webhook_signature_verifies_expected_hmac():
    body = b'{"id":"evt_1"}'

    assert verify_webhook_signature(body, expected_signature(body))
    assert not verify_webhook_signature(body, "wrong")


@override_settings(BILLING_WEBHOOK_SECRET="secret")
def test_billing_webhook_signature_verifies_paddle_hmac():
    body = b'{"event_type":"subscription.created"}'
    timestamp = "1782138000"
    signature = f"ts={timestamp};h1={expected_paddle_signature(body, timestamp)}"

    assert verify_webhook_signature(body, signature)
    assert not verify_webhook_signature(body, f"ts={timestamp};h1=wrong")


@override_settings(BILLING_WEBHOOK_SECRET="")
def test_billing_webhook_signature_requires_configured_secret():
    assert not verify_webhook_signature(b"{}", "")


def test_subscription_updated_event_updates_tenant_plan(db, tenant):
    event = BillingEvent.objects.create(
        provider="test",
        provider_event_id="evt_1",
        event_type="subscription.updated",
        payload={
            "tenant_id": str(tenant.id),
            "plan": "pro",
            "status": "active",
            "provider_customer_id": "cus_1",
            "provider_subscription_id": "sub_1",
        },
        signature_valid=True,
    )

    process_billing_event(event)
    tenant.refresh_from_db()
    event.refresh_from_db()

    assert tenant.plan == "pro"
    assert tenant.subscription.plan == "pro"
    assert event.processing_status == "processed"


def test_lemonsqueezy_subscription_event_updates_tenant_plan(db, tenant):
    event = BillingEvent.objects.create(
        provider="lemonsqueezy",
        provider_event_id="sub_1",
        event_type="subscription_created",
        payload={
            "meta": {
                "event_name": "subscription_created",
                "custom_data": {"tenant_id": str(tenant.id), "plan": "pro"},
            },
            "data": {
                "id": "sub_1",
                "attributes": {
                    "customer_id": 42,
                    "status": "active",
                    "renews_at": "2026-07-22T12:00:00Z",
                },
            },
        },
        signature_valid=True,
    )

    process_billing_event(event)
    tenant.refresh_from_db()
    event.refresh_from_db()

    assert tenant.plan == "pro"
    assert tenant.subscription.billing_provider == "lemonsqueezy"
    assert tenant.subscription.provider_customer_id == "42"
    assert tenant.subscription.provider_subscription_id == "sub_1"
    assert event.processing_status == "processed"


def test_paddle_subscription_event_updates_tenant_plan(db, tenant):
    event = BillingEvent.objects.create(
        provider="paddle",
        provider_event_id="sub_1",
        event_type="subscription.created",
        payload={
            "event_type": "subscription.created",
            "data": {
                "id": "sub_1",
                "customer_id": "ctm_1",
                "status": "active",
                "custom_data": {"tenant_id": str(tenant.id), "plan": "essential"},
                "current_billing_period": {"ends_at": "2027-06-22T12:00:00Z"},
            },
        },
        signature_valid=True,
    )

    process_billing_event(event)
    tenant.refresh_from_db()
    event.refresh_from_db()

    assert tenant.plan == "essential"
    assert tenant.subscription.plan == "essential"
    assert tenant.subscription.billing_provider == "paddle"
    assert tenant.subscription.provider_customer_id == "ctm_1"
    assert tenant.subscription.provider_subscription_id == "sub_1"
    assert event.processing_status == "processed"


def test_subscription_canceled_event_downgrades_tenant_to_free(db, tenant):
    tenant.plan = "pro"
    tenant.save(update_fields=["plan"])
    event = BillingEvent.objects.create(
        provider="test",
        provider_event_id="evt_2",
        event_type="subscription.canceled",
        payload={"tenant_id": str(tenant.id)},
        signature_valid=True,
    )

    process_billing_event(event)
    tenant.refresh_from_db()

    assert tenant.plan == "free"
    assert tenant.subscription.status == "canceled"

from __future__ import annotations

from django.test import override_settings

from apps.billing.models import BillingEvent
from apps.billing.processor import process_billing_event
from apps.billing.signatures import expected_signature, verify_webhook_signature


@override_settings(BILLING_WEBHOOK_SECRET="secret")
def test_billing_webhook_signature_verifies_expected_hmac():
    body = b'{"id":"evt_1"}'

    assert verify_webhook_signature(body, expected_signature(body))
    assert not verify_webhook_signature(body, "wrong")


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

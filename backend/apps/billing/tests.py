from __future__ import annotations

from django.test import override_settings
from rest_framework.test import APIRequestFactory

from apps.billing.models import BillingEvent
from apps.billing.processor import process_billing_event
from apps.billing.signatures import expected_creem_signature, verify_webhook_signature
from apps.billing.views import BillingWebhookView


@override_settings(BILLING_WEBHOOK_SECRET="secret")
def test_creem_webhook_signature_verifies_expected_hmac():
    body = b'{"id":"evt_1"}'

    assert verify_webhook_signature(body, expected_creem_signature(body))
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


@override_settings(BILLING_PRODUCT_IDS={"pro": "prod_pro"})
def test_creem_subscription_paid_event_updates_tenant_plan(db, tenant):
    event = BillingEvent.objects.create(
        provider="creem",
        provider_event_id="evt_creem_paid",
        event_type="subscription.paid",
        payload={
            "id": "evt_creem_paid",
            "eventType": "subscription.paid",
            "object": {
                "id": "sub_1",
                "status": "active",
                "product": {"id": "prod_pro"},
                "customer": {"id": "cust_1"},
                "metadata": {"tenant_id": str(tenant.id), "plan": "pro"},
                "current_period_end_date": "2027-06-22T12:00:00Z",
            },
        },
        signature_valid=True,
    )

    process_billing_event(event)
    tenant.refresh_from_db()
    event.refresh_from_db()

    assert tenant.plan == "pro"
    assert tenant.subscription.billing_provider == "creem"
    assert tenant.subscription.provider_customer_id == "cust_1"
    assert tenant.subscription.provider_subscription_id == "sub_1"
    assert tenant.subscription.current_period_end.isoformat() == "2027-06-22T12:00:00+00:00"
    assert event.processing_status == "processed"


@override_settings(BILLING_PRODUCT_IDS={"essential": "prod_essential"})
def test_creem_event_resolves_plan_from_configured_product_id(db, tenant):
    event = BillingEvent.objects.create(
        provider="creem",
        provider_event_id="evt_creem_product",
        event_type="subscription.active",
        payload={
            "id": "evt_creem_product",
            "eventType": "subscription.active",
            "object": {
                "id": "sub_essential",
                "status": "active",
                "product": {"id": "prod_essential"},
                "customer": {"id": "cust_essential"},
                "metadata": {"tenant_id": str(tenant.id)},
            },
        },
        signature_valid=True,
    )

    process_billing_event(event)
    tenant.refresh_from_db()

    assert tenant.plan == "essential"
    assert tenant.subscription.plan == "essential"


@override_settings(BILLING_PRODUCT_IDS={"pro": "prod_pro"})
def test_creem_scheduled_cancel_keeps_access_until_terminal_event(db, tenant):
    tenant.plan = "pro"
    tenant.save(update_fields=["plan"])
    event = BillingEvent.objects.create(
        provider="creem",
        provider_event_id="evt_creem_scheduled_cancel",
        event_type="subscription.scheduled_cancel",
        payload={
            "id": "evt_creem_scheduled_cancel",
            "eventType": "subscription.scheduled_cancel",
            "object": {
                "id": "sub_1",
                "status": "scheduled_cancel",
                "product": {"id": "prod_pro"},
                "customer": {"id": "cust_1"},
                "metadata": {"tenant_id": str(tenant.id), "plan": "pro"},
            },
        },
        signature_valid=True,
    )

    process_billing_event(event)
    tenant.refresh_from_db()

    assert tenant.plan == "pro"
    assert tenant.subscription.status == "scheduled_cancel"


@override_settings(BILLING_PRODUCT_IDS={"pro": "prod_pro"})
def test_creem_expired_event_keeps_access_while_payment_retries_continue(db, tenant):
    tenant.plan = "pro"
    tenant.save(update_fields=["plan"])
    event = BillingEvent.objects.create(
        provider="creem",
        provider_event_id="evt_creem_expired",
        event_type="subscription.expired",
        payload={
            "id": "evt_creem_expired",
            "eventType": "subscription.expired",
            "object": {
                "id": "sub_1",
                "status": "active",
                "product": {"id": "prod_pro"},
                "customer": {"id": "cust_1"},
                "metadata": {"tenant_id": str(tenant.id), "plan": "pro"},
            },
        },
        signature_valid=True,
    )

    process_billing_event(event)
    tenant.refresh_from_db()

    assert tenant.plan == "pro"
    assert tenant.subscription.status == "active"


def test_creem_canceled_event_downgrades_tenant_to_free(db, tenant):
    tenant.plan = "pro"
    tenant.save(update_fields=["plan"])
    event = BillingEvent.objects.create(
        provider="creem",
        provider_event_id="evt_creem_canceled",
        event_type="subscription.canceled",
        payload={
            "id": "evt_creem_canceled",
            "eventType": "subscription.canceled",
            "object": {
                "id": "sub_1",
                "status": "canceled",
                "customer": {"id": "cust_1"},
                "metadata": {"tenant_id": str(tenant.id), "plan": "pro"},
            },
        },
        signature_valid=True,
    )

    process_billing_event(event)
    tenant.refresh_from_db()

    assert tenant.plan == "free"
    assert tenant.subscription.status == "canceled"
    assert tenant.subscription.provider_customer_id == "cust_1"
    assert tenant.subscription.provider_subscription_id == "sub_1"


@override_settings(BILLING_PRODUCT_IDS={"pro": "prod_pro"})
def test_creem_refund_resolves_tenant_from_existing_subscription_id(db, tenant):
    paid_event = BillingEvent.objects.create(
        provider="creem",
        provider_event_id="evt_creem_paid_before_refund",
        event_type="subscription.paid",
        payload={
            "id": "evt_creem_paid_before_refund",
            "eventType": "subscription.paid",
            "object": {
                "id": "sub_refunded",
                "status": "active",
                "product": {"id": "prod_pro"},
                "customer": {"id": "cust_1"},
                "metadata": {"tenant_id": str(tenant.id), "plan": "pro"},
            },
        },
        signature_valid=True,
    )
    process_billing_event(paid_event)

    refund_event = BillingEvent.objects.create(
        provider="creem",
        provider_event_id="evt_creem_refund",
        event_type="refund.created",
        payload={
            "id": "evt_creem_refund",
            "eventType": "refund.created",
            "object": {
                "id": "ref_1",
                "status": "succeeded",
                "subscription": {
                    "id": "sub_refunded",
                    "status": "canceled",
                    "product": "prod_pro",
                    "customer": "cust_1",
                },
            },
        },
        signature_valid=True,
    )

    process_billing_event(refund_event)
    tenant.refresh_from_db()
    refund_event.refresh_from_db()

    assert tenant.plan == "free"
    assert tenant.subscription.provider_subscription_id == "sub_refunded"
    assert refund_event.processing_status == "processed"


@override_settings(
    BILLING_PROVIDER="creem",
    BILLING_WEBHOOK_SECRET="secret",
    BILLING_PRODUCT_IDS={"pro": "prod_pro"},
)
def test_creem_webhook_uses_event_type_and_returns_200(db, tenant):
    payload = {
        "id": "evt_webhook",
        "eventType": "subscription.paid",
        "object": {
            "id": "sub_1",
            "status": "active",
            "product": {"id": "prod_pro"},
            "customer": {"id": "cust_1"},
            "metadata": {"tenant_id": str(tenant.id), "plan": "pro"},
        },
    }
    request = APIRequestFactory().post("/api/v1/billing/webhook", payload, format="json")
    request.META["HTTP_CREEM_SIGNATURE"] = expected_creem_signature(request.body)

    response = BillingWebhookView.as_view()(request)

    assert response.status_code == 200
    assert response.data["created"] is True
    event = BillingEvent.objects.get(provider_event_id="evt_webhook")
    assert event.provider == "creem"
    assert event.event_type == "subscription.paid"
    assert event.processing_status == "processed"

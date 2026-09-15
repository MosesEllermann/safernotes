from __future__ import annotations

import json

from django.test import override_settings
from rest_framework.test import APIRequestFactory, force_authenticate

from apps.subscriptions.models import Subscription
from apps.subscriptions.plans import policy_for_plan
from apps.subscriptions.views import CheckoutView, PlanCatalogView, PortalView, UsageView


def test_usage_view_requires_tenant_membership(db, owner_user):
    request = APIRequestFactory().get("/api/v1/subscription/usage")
    force_authenticate(request, user=owner_user)
    response = UsageView.as_view()(request)

    assert response.status_code == 400


def test_usage_view_returns_total_workspace_storage(db, tenant, owner_user, note):
    request = APIRequestFactory().get(
        "/api/v1/subscription/usage",
        {"tenant": str(tenant.id)},
    )
    force_authenticate(request, user=owner_user)

    response = UsageView.as_view()(request)

    assert response.status_code == 200
    assert response.data["usage"]["notes_bytes_used"] == note.storage_bytes
    assert response.data["usage"]["attachments_bytes_used"] == 0
    assert response.data["usage"]["storage_bytes_used"] == note.storage_bytes


def test_checkout_view_rejects_invalid_plan(db, tenant, owner_user):
    request = APIRequestFactory().post(
        "/api/v1/subscription/checkout",
        {"tenant": str(tenant.id), "plan": "not-a-plan"},
        format="json",
    )
    force_authenticate(request, user=owner_user)
    response = CheckoutView.as_view()(request)

    assert response.status_code == 400


def test_checkout_view_rejects_non_self_service_plan(db, tenant, owner_user):
    request = APIRequestFactory().post(
        "/api/v1/subscription/checkout",
        {"tenant": str(tenant.id), "plan": "team"},
        format="json",
    )
    force_authenticate(request, user=owner_user)

    response = CheckoutView.as_view()(request)

    assert response.status_code == 400


def test_checkout_view_prevents_a_second_paid_subscription(db, tenant, owner_user):
    tenant.plan = "pro"
    tenant.save(update_fields=["plan"])
    request = APIRequestFactory().post(
        "/api/v1/subscription/checkout",
        {"tenant": str(tenant.id), "plan": "essential"},
        format="json",
    )
    force_authenticate(request, user=owner_user)

    response = CheckoutView.as_view()(request)

    assert response.status_code == 409
    assert "already has a paid plan" in response.data["detail"]


@override_settings(
    BILLING_PROVIDER="creem",
    BILLING_API_KEY="creem_test_key",
    BILLING_API_BASE_URL="https://api.creem.io/v1",
    BILLING_PRODUCT_IDS={"essential": "prod_essential"},
)
def test_plan_catalog_is_public_and_only_offers_essential_and_pro(db):
    request = APIRequestFactory().get("/api/v1/subscription/plans")

    response = PlanCatalogView.as_view()(request)

    assert response.status_code == 200
    assert response.data["currency"] == "EUR"
    assert [plan["key"] for plan in response.data["plans"]] == ["essential", "pro"]
    essential, pro = response.data["plans"]
    assert essential["pricing"] == {
        "monthly_equivalent_cents": 150,
        "yearly_cents": 1800,
        "billing_interval": "year",
    }
    assert essential["limits"]["storage_bytes"] == 5 * 1024 * 1024 * 1024
    assert essential["checkout_enabled"] is True
    assert pro["checkout_enabled"] is False


@override_settings(
    BILLING_PROVIDER="creem",
    BILLING_API_KEY="creem_test_key",
    BILLING_API_BASE_URL="https://test-api.creem.io/v1",
    BILLING_PRODUCT_IDS={"essential": "prod_essential", "pro": "prod_pro"},
    BILLING_TESTER_EMAILS=["owner@example.com"],
)
def test_test_mode_catalog_only_enables_checkout_for_allowlisted_users(db, owner_user):
    anonymous_request = APIRequestFactory().get("/api/v1/subscription/plans")
    anonymous_response = PlanCatalogView.as_view()(anonymous_request)
    assert all(
        plan["checkout_enabled"] is False
        for plan in anonymous_response.data["plans"]
    )

    owner_user.email = "OWNER@example.com"
    owner_user.save(update_fields=["email"])
    owner_request = APIRequestFactory().get("/api/v1/subscription/plans")
    force_authenticate(owner_request, user=owner_user)
    owner_response = PlanCatalogView.as_view()(owner_request)
    assert all(plan["checkout_enabled"] is True for plan in owner_response.data["plans"])


@override_settings(
    BILLING_PROVIDER="creem",
    BILLING_API_BASE_URL="https://test-api.creem.io/v1",
    BILLING_TESTER_EMAILS=["tester@example.com"],
)
def test_test_mode_checkout_rejects_non_allowlisted_owner(db, tenant, owner_user):
    request = APIRequestFactory().post(
        "/api/v1/subscription/checkout",
        {"tenant": str(tenant.id), "plan": "essential"},
        format="json",
    )
    force_authenticate(request, user=owner_user)

    response = CheckoutView.as_view()(request)

    assert response.status_code == 403
    assert response.data["detail"] == "Test checkout is not enabled for this account."


@override_settings(
    BILLING_PROVIDER="creem",
    BILLING_API_KEY="creem_test_key",
    BILLING_API_BASE_URL="https://test-api.creem.io/v1",
    BILLING_PRODUCT_IDS={"essential": "prod_essential"},
    BILLING_SUCCESS_URL="https://app.example/subscription/success",
    BILLING_TESTER_EMAILS=["owner@example.com"],
)
def test_creem_checkout_creates_session_with_tenant_metadata(db, tenant, owner_user, monkeypatch):
    captured_payload = {}
    captured_url = ""
    captured_headers = {}

    class FakeResponse:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def read(self):
            return b'{"id":"ch_1","checkout_url":"https://checkout.creem.io/ch_1"}'

    def fake_urlopen(request, timeout):
        nonlocal captured_url
        captured_url = request.full_url
        captured_payload.update(json.loads(request.data.decode("utf-8")))
        captured_headers.update({key.lower(): value for key, value in request.header_items()})
        return FakeResponse()

    monkeypatch.setattr("apps.subscriptions.providers.urlopen", fake_urlopen)
    request = APIRequestFactory().post(
        "/api/v1/subscription/checkout",
        {"tenant": str(tenant.id), "plan": "essential"},
        format="json",
    )
    force_authenticate(request, user=owner_user)
    response = CheckoutView.as_view()(request)

    assert response.status_code == 200
    assert response.data["status"] == "ready"
    assert response.data["provider"] == "creem"
    assert response.data["provider_checkout_id"] == "ch_1"
    assert response.data["checkout_url"] == "https://checkout.creem.io/ch_1"
    assert captured_url == "https://test-api.creem.io/v1/checkouts"
    assert captured_headers["x-api-key"] == "creem_test_key"
    assert captured_payload["product_id"] == "prod_essential"
    assert captured_payload["request_id"].startswith(f"{tenant.id}:essential:")
    assert captured_payload["customer"] == {"email": owner_user.email}
    assert captured_payload["metadata"] == {
        "tenant_id": str(tenant.id),
        "plan": "essential",
    }
    assert captured_payload["success_url"] == "https://app.example/subscription/success"


@override_settings(
    BILLING_PROVIDER="creem",
    BILLING_API_KEY="creem_test_key",
    BILLING_API_BASE_URL="https://test-api.creem.io/v1",
    BILLING_PRODUCT_IDS={},
    BILLING_TESTER_EMAILS=["owner@example.com"],
)
def test_creem_checkout_reports_missing_product_configuration(db, tenant, owner_user):
    request = APIRequestFactory().post(
        "/api/v1/subscription/checkout",
        {"tenant": str(tenant.id), "plan": "essential"},
        format="json",
    )
    force_authenticate(request, user=owner_user)

    response = CheckoutView.as_view()(request)

    assert response.status_code == 200
    assert response.data["status"] == "checkout-api-not-configured"
    assert response.data["checkout_url"] is None


@override_settings(
    BILLING_PROVIDER="creem",
    BILLING_API_KEY="creem_test_key",
    BILLING_API_BASE_URL="https://test-api.creem.io/v1",
)
def test_creem_portal_uses_stored_customer_id(db, tenant, owner_user, monkeypatch):
    Subscription.objects.create(
        tenant=tenant,
        plan="pro",
        status="active",
        billing_provider="creem",
        provider_customer_id="cust_1",
        provider_subscription_id="sub_1",
    )
    captured_payload = {}
    captured_url = ""

    class FakeResponse:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def read(self):
            return b'{"customer_portal_link":"https://creem.io/portal/cust_1"}'

    def fake_urlopen(request, timeout):
        nonlocal captured_url
        captured_url = request.full_url
        captured_payload.update(json.loads(request.data.decode("utf-8")))
        return FakeResponse()

    monkeypatch.setattr("apps.subscriptions.providers.urlopen", fake_urlopen)
    request = APIRequestFactory().post(
        "/api/v1/subscription/portal",
        {"tenant": str(tenant.id)},
        format="json",
    )
    force_authenticate(request, user=owner_user)

    response = PortalView.as_view()(request)

    assert response.status_code == 200
    assert response.data["status"] == "ready"
    assert response.data["portal_url"] == "https://creem.io/portal/cust_1"
    assert captured_url == "https://test-api.creem.io/v1/customers/billing"
    assert captured_payload == {"customer_id": "cust_1"}


def test_plan_policy_exposes_launch_pricing_metadata():
    essential_policy = policy_for_plan("essential").as_dict()
    pro_policy = policy_for_plan("pro").as_dict()
    team_policy = policy_for_plan("team").as_dict()

    assert essential_policy["monthly_price_eur_cents"] == 150
    assert essential_policy["yearly_price_eur_cents"] == 1800
    assert essential_policy["billing_interval_note"] == "yearly-first"
    assert pro_policy["monthly_price_eur_cents"] == 500
    assert pro_policy["yearly_price_eur_cents"] == 6000
    assert team_policy["monthly_price_eur_cents"] == 1500
    assert team_policy["billing_interval_note"] == "per workspace, monthly or yearly"

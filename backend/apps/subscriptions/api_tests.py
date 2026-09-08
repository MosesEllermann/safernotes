from __future__ import annotations

import json

from django.test import override_settings
from rest_framework.test import APIRequestFactory, force_authenticate

from apps.subscriptions.plans import policy_for_plan
from apps.subscriptions.views import CheckoutView, UsageView


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


@override_settings(
    BILLING_PROVIDER="paddle",
    BILLING_CHECKOUT_URLS={"essential": "https://checkout.example/essential"},
    BILLING_PORTAL_URL="",
)
def test_checkout_view_returns_configured_hosted_checkout_url(db, tenant, owner_user):
    request = APIRequestFactory().post(
        "/api/v1/subscription/checkout",
        {"tenant": str(tenant.id), "plan": "essential"},
        format="json",
    )
    force_authenticate(request, user=owner_user)
    response = CheckoutView.as_view()(request)

    assert response.status_code == 200
    assert response.data["status"] == "ready"
    assert response.data["provider"] == "paddle"
    assert response.data["target_plan"] == "essential"
    assert response.data["checkout_url"].startswith("https://checkout.example/essential?")
    assert f"tenant_id={tenant.id}" in response.data["checkout_url"]
    assert "plan=essential" in response.data["checkout_url"]


@override_settings(
    BILLING_PROVIDER="paddle",
    BILLING_API_KEY="test-key",
    BILLING_API_BASE_URL="https://sandbox-api.paddle.com",
    BILLING_PRICE_IDS={"essential": "pri_essential"},
    BILLING_CHECKOUT_URLS={},
    BILLING_PORTAL_URL="",
)
def test_paddle_checkout_creates_transaction_with_custom_data(db, tenant, owner_user, monkeypatch):
    captured_payload = {}
    captured_url = ""

    class FakeResponse:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def read(self):
            return b'{"data":{"id":"txn_1","checkout":{"url":"https://checkout.paddle.com/txn_1"}}}'

    def fake_urlopen(request, timeout):
        nonlocal captured_url
        captured_url = request.full_url
        captured_payload.update(json.loads(request.data.decode("utf-8")))
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
    assert response.data["provider_transaction_id"] == "txn_1"
    assert response.data["checkout_url"] == "https://checkout.paddle.com/txn_1"
    assert captured_url == "https://sandbox-api.paddle.com/transactions"
    assert captured_payload["collection_mode"] == "automatic"
    assert captured_payload["items"] == [{"price_id": "pri_essential", "quantity": 1}]
    assert captured_payload["custom_data"] == {
        "tenant_id": str(tenant.id),
        "plan": "essential",
        "owner_email": owner_user.email,
    }


@override_settings(
    BILLING_PROVIDER="lemonsqueezy",
    BILLING_API_KEY="test-key",
    BILLING_STORE_ID="store_1",
    BILLING_VARIANT_IDS={"pro": "variant_1"},
    BILLING_CHECKOUT_URLS={},
    BILLING_PORTAL_URL="",
    BILLING_SUCCESS_URL="https://app.example/subscription/success",
)
def test_lemonsqueezy_checkout_includes_tenant_custom_data(db, tenant, owner_user, monkeypatch):
    captured_payload = {}

    class FakeResponse:
        def __enter__(self):
            return self

        def __exit__(self, exc_type, exc, tb):
            return False

        def read(self):
            return b'{"data":{"attributes":{"url":"https://checkout.example/generated"}}}'

    def fake_urlopen(request, timeout):
        captured_payload.update(json.loads(request.data.decode("utf-8")))
        return FakeResponse()

    monkeypatch.setattr("apps.subscriptions.providers.urlopen", fake_urlopen)
    request = APIRequestFactory().post(
        "/api/v1/subscription/checkout",
        {"tenant": str(tenant.id), "plan": "pro"},
        format="json",
    )
    force_authenticate(request, user=owner_user)
    response = CheckoutView.as_view()(request)

    checkout_data = captured_payload["data"]["attributes"]["checkout_data"]
    assert response.status_code == 200
    assert response.data["checkout_url"] == "https://checkout.example/generated"
    assert checkout_data["custom"] == {"tenant_id": str(tenant.id), "plan": "pro"}
    assert checkout_data["email"] == owner_user.email


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

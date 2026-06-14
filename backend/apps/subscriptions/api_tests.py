from __future__ import annotations

from rest_framework.test import APIRequestFactory, force_authenticate

from apps.subscriptions.views import CheckoutView, UsageView


def test_usage_view_requires_tenant_membership(db, owner_user):
    request = APIRequestFactory().get("/api/v1/subscription/usage")
    force_authenticate(request, user=owner_user)
    response = UsageView.as_view()(request)

    assert response.status_code == 400


def test_checkout_view_rejects_invalid_plan(db, tenant, owner_user):
    request = APIRequestFactory().post(
        "/api/v1/subscription/checkout",
        {"tenant": str(tenant.id), "plan": "not-a-plan"},
        format="json",
    )
    force_authenticate(request, user=owner_user)
    response = CheckoutView.as_view()(request)

    assert response.status_code == 400


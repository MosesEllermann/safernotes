from __future__ import annotations

from django.urls import path

from apps.subscriptions.views import (
    CheckoutView,
    PlanCatalogView,
    PortalView,
    SubscriptionView,
    UsageView,
)

urlpatterns = [
    path("plans", PlanCatalogView.as_view(), name="subscription-plans"),
    path("", SubscriptionView.as_view(), name="subscription"),
    path("checkout", CheckoutView.as_view(), name="subscription-checkout"),
    path("portal", PortalView.as_view(), name="subscription-portal"),
    path("usage", UsageView.as_view(), name="subscription-usage"),
]

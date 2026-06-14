from __future__ import annotations

from django.urls import path

from apps.billing.views import BillingWebhookView

urlpatterns = [path("webhook", BillingWebhookView.as_view(), name="billing-webhook")]


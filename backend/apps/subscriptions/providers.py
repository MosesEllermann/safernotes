from __future__ import annotations

import json
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from django.conf import settings


class BillingProvider:
    name = "unconfigured"

    def create_checkout_session(self, tenant, target_plan: str) -> dict:
        return {
            "checkout_url": None,
            "status": "billing-provider-not-configured",
            "tenant": str(tenant.id),
            "target_plan": target_plan,
        }

    def create_portal_session(self, tenant) -> dict:
        return {
            "portal_url": None,
            "status": "billing-provider-not-configured",
            "tenant": str(tenant.id),
        }


class HostedCheckoutBillingProvider(BillingProvider):
    def __init__(self, name: str, checkout_urls: dict[str, str], portal_url: str = ""):
        self.name = name
        self.checkout_urls = checkout_urls
        self.portal_url = portal_url

    def create_checkout_session(self, tenant, target_plan: str) -> dict:
        checkout_url = self.checkout_urls.get(target_plan)
        if not checkout_url:
            return {
                "checkout_url": None,
                "status": "checkout-url-not-configured",
                "provider": self.name,
                "tenant": str(tenant.id),
                "target_plan": target_plan,
            }

        query = urlencode(
            {
                "tenant_id": str(tenant.id),
                "plan": target_plan,
                "owner_email": getattr(tenant.owner_user, "email", ""),
            }
        )
        separator = "&" if "?" in checkout_url else "?"
        return {
            "checkout_url": f"{checkout_url}{separator}{query}",
            "status": "ready",
            "provider": self.name,
            "tenant": str(tenant.id),
            "target_plan": target_plan,
        }

    def create_portal_session(self, tenant) -> dict:
        if not self.portal_url:
            return {
                "portal_url": None,
                "status": "portal-url-not-configured",
                "provider": self.name,
                "tenant": str(tenant.id),
            }
        query = urlencode({"tenant_id": str(tenant.id)})
        separator = "&" if "?" in self.portal_url else "?"
        return {
            "portal_url": f"{self.portal_url}{separator}{query}",
            "status": "ready",
            "provider": self.name,
            "tenant": str(tenant.id),
        }


class LemonSqueezyBillingProvider(HostedCheckoutBillingProvider):
    checkout_api_url = "https://api.lemonsqueezy.com/v1/checkouts"

    def create_checkout_session(self, tenant, target_plan: str) -> dict:
        if settings.BILLING_API_KEY and settings.BILLING_STORE_ID:
            variant_id = settings.BILLING_VARIANT_IDS.get(target_plan)
            if variant_id:
                return self._create_api_checkout(tenant, target_plan, variant_id)
        return super().create_checkout_session(tenant, target_plan)

    def _create_api_checkout(self, tenant, target_plan: str, variant_id: str) -> dict:
        attributes = {
            "checkout_data": {
                "email": getattr(tenant.owner_user, "email", ""),
                "custom": {
                    "tenant_id": str(tenant.id),
                    "plan": target_plan,
                },
            },
        }
        if settings.BILLING_SUCCESS_URL:
            attributes["product_options"] = {"redirect_url": settings.BILLING_SUCCESS_URL}

        payload = {
            "data": {
                "type": "checkouts",
                "attributes": attributes,
                "relationships": {
                    "store": {"data": {"type": "stores", "id": settings.BILLING_STORE_ID}},
                    "variant": {"data": {"type": "variants", "id": variant_id}},
                },
            }
        }
        request = Request(
            self.checkout_api_url,
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Accept": "application/vnd.api+json",
                "Authorization": f"Bearer {settings.BILLING_API_KEY}",
                "Content-Type": "application/vnd.api+json",
            },
            method="POST",
        )
        try:
            with urlopen(request, timeout=10) as response:
                body = json.loads(response.read().decode("utf-8"))
        except HTTPError as exc:
            return {
                "checkout_url": None,
                "status": "checkout-api-error",
                "provider": self.name,
                "tenant": str(tenant.id),
                "target_plan": target_plan,
                "error_status": exc.code,
            }
        except URLError:
            return {
                "checkout_url": None,
                "status": "checkout-api-unavailable",
                "provider": self.name,
                "tenant": str(tenant.id),
                "target_plan": target_plan,
            }

        checkout_url = body.get("data", {}).get("attributes", {}).get("url")
        return {
            "checkout_url": checkout_url,
            "status": "ready" if checkout_url else "checkout-api-missing-url",
            "provider": self.name,
            "tenant": str(tenant.id),
            "target_plan": target_plan,
        }


class PaddleBillingProvider(HostedCheckoutBillingProvider):
    def create_checkout_session(self, tenant, target_plan: str) -> dict:
        price_id = settings.BILLING_PRICE_IDS.get(target_plan)
        if settings.BILLING_API_KEY and price_id:
            return self._create_transaction_checkout(tenant, target_plan, price_id)
        return super().create_checkout_session(tenant, target_plan)

    def _create_transaction_checkout(self, tenant, target_plan: str, price_id: str) -> dict:
        payload = {
            "collection_mode": "automatic",
            "items": [{"price_id": price_id, "quantity": 1}],
            "custom_data": {
                "tenant_id": str(tenant.id),
                "plan": target_plan,
                "owner_email": getattr(tenant.owner_user, "email", ""),
            },
        }
        request = Request(
            f"{settings.BILLING_API_BASE_URL.rstrip('/')}/transactions",
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Accept": "application/json",
                "Authorization": f"Bearer {settings.BILLING_API_KEY}",
                "Content-Type": "application/json",
            },
            method="POST",
        )
        try:
            with urlopen(request, timeout=10) as response:
                body = json.loads(response.read().decode("utf-8"))
        except HTTPError as exc:
            return {
                "checkout_url": None,
                "status": "checkout-api-error",
                "provider": self.name,
                "tenant": str(tenant.id),
                "target_plan": target_plan,
                "error_status": exc.code,
            }
        except URLError:
            return {
                "checkout_url": None,
                "status": "checkout-api-unavailable",
                "provider": self.name,
                "tenant": str(tenant.id),
                "target_plan": target_plan,
            }

        data = body.get("data", {})
        checkout_url = data.get("checkout", {}).get("url")
        return {
            "checkout_url": checkout_url,
            "status": "ready" if checkout_url else "checkout-api-missing-url",
            "provider": self.name,
            "tenant": str(tenant.id),
            "target_plan": target_plan,
            "provider_transaction_id": data.get("id"),
        }


def billing_provider() -> BillingProvider:
    provider_name = settings.BILLING_PROVIDER
    if provider_name == "lemonsqueezy":
        return LemonSqueezyBillingProvider(
            provider_name,
            settings.BILLING_CHECKOUT_URLS,
            settings.BILLING_PORTAL_URL,
        )
    if provider_name in {"paddle", "hosted"}:
        provider_cls = PaddleBillingProvider if provider_name == "paddle" else HostedCheckoutBillingProvider
        return provider_cls(
            provider_name,
            settings.BILLING_CHECKOUT_URLS,
            settings.BILLING_PORTAL_URL,
        )
    return BillingProvider()

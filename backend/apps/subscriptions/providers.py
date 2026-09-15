from __future__ import annotations

import json
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen
from uuid import uuid4

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


class CreemBillingProvider(BillingProvider):
    name = "creem"

    def create_checkout_session(self, tenant, target_plan: str) -> dict:
        product_id = settings.BILLING_PRODUCT_IDS.get(target_plan)
        if not settings.BILLING_API_KEY or not product_id:
            return {
                "checkout_url": None,
                "status": "checkout-api-not-configured",
                "provider": self.name,
                "tenant": str(tenant.id),
                "target_plan": target_plan,
            }

        payload = {
            "product_id": product_id,
            "request_id": f"{tenant.id}:{target_plan}:{uuid4().hex}",
            "customer": {"email": getattr(tenant.owner_user, "email", "")},
            "metadata": {
                "tenant_id": str(tenant.id),
                "plan": target_plan,
            },
        }
        if settings.BILLING_SUCCESS_URL:
            payload["success_url"] = settings.BILLING_SUCCESS_URL

        body, error = self._post_json("/checkouts", payload)
        if error:
            return {
                "checkout_url": None,
                "provider": self.name,
                "tenant": str(tenant.id),
                "target_plan": target_plan,
                **error,
            }

        checkout_url = body.get("checkout_url")
        return {
            "checkout_url": checkout_url,
            "status": "ready" if checkout_url else "checkout-api-missing-url",
            "provider": self.name,
            "tenant": str(tenant.id),
            "target_plan": target_plan,
            "provider_checkout_id": body.get("id"),
        }

    def create_portal_session(self, tenant) -> dict:
        subscription = getattr(tenant, "subscription", None)
        customer_id = getattr(subscription, "provider_customer_id", "")
        if not settings.BILLING_API_KEY or not customer_id:
            return {
                "portal_url": None,
                "status": "customer-not-available",
                "provider": self.name,
                "tenant": str(tenant.id),
            }

        body, error = self._post_json("/customers/billing", {"customer_id": customer_id})
        if error:
            return {
                "portal_url": None,
                "provider": self.name,
                "tenant": str(tenant.id),
                **error,
            }

        portal_url = body.get("customer_portal_link")
        return {
            "portal_url": portal_url,
            "status": "ready" if portal_url else "portal-api-missing-url",
            "provider": self.name,
            "tenant": str(tenant.id),
        }

    def _post_json(self, path: str, payload: dict) -> tuple[dict, dict | None]:
        request = Request(
            f"{settings.BILLING_API_BASE_URL.rstrip('/')}{path}",
            data=json.dumps(payload).encode("utf-8"),
            headers={
                "Accept": "application/json",
                "Content-Type": "application/json",
                # Creem rejects urllib's default Python-urllib user agent with 403.
                "User-Agent": "Safernotes/1.0 (+https://safernotes.com)",
                "x-api-key": settings.BILLING_API_KEY,
            },
            method="POST",
        )
        try:
            # Server-configured provider API URL, not user-controlled.
            with urlopen(request, timeout=10) as api_response:  # nosec B310
                return json.loads(api_response.read().decode("utf-8")), None
        except HTTPError as exc:
            return {}, {"status": "billing-api-error", "error_status": exc.code}
        except (URLError, TimeoutError):
            return {}, {"status": "billing-api-unavailable"}
        except (UnicodeDecodeError, json.JSONDecodeError):
            return {}, {"status": "billing-api-invalid-response"}


def billing_provider() -> BillingProvider:
    if settings.BILLING_PROVIDER == "creem":
        return CreemBillingProvider()
    return BillingProvider()

from __future__ import annotations


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


def billing_provider() -> BillingProvider:
    return BillingProvider()


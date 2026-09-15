from __future__ import annotations

from django.conf import settings
from rest_framework import permissions, response, serializers, views

from apps.subscriptions.models import Subscription
from apps.subscriptions.plans import SELF_SERVICE_PLAN_KEYS, public_plan_catalog
from apps.subscriptions.providers import billing_provider
from apps.subscriptions.serializers import SubscriptionSerializer
from apps.subscriptions.usage import usage_report_for_tenant
from apps.tenants.models import Organization


class TenantRequestSerializer(serializers.Serializer):
    tenant = serializers.PrimaryKeyRelatedField(queryset=Organization.objects.all())

    def validate_tenant(self, tenant):
        request = self.context["request"]
        if not tenant.memberships.filter(user=request.user, status="active").exists():
            raise serializers.ValidationError("You are not a member of this tenant.")
        return tenant


class OwnerTenantRequestSerializer(TenantRequestSerializer):
    def validate_tenant(self, tenant):
        tenant = super().validate_tenant(tenant)
        if tenant.owner_user != self.context["request"].user:
            raise serializers.ValidationError("Only tenant owners can manage billing.")
        return tenant


class CheckoutRequestSerializer(OwnerTenantRequestSerializer):
    plan = serializers.ChoiceField(choices=SELF_SERVICE_PLAN_KEYS)


class PlanCatalogView(views.APIView):
    permission_classes = [permissions.AllowAny]

    def get(self, request):
        checkout_enabled_for = set()
        if settings.BILLING_PROVIDER == "creem" and settings.BILLING_API_KEY:
            checkout_enabled_for = {
                plan for plan in SELF_SERVICE_PLAN_KEYS if settings.BILLING_PRODUCT_IDS.get(plan)
            }
        return response.Response(
            {
                "currency": "EUR",
                "plans": public_plan_catalog(checkout_enabled_for=checkout_enabled_for),
            }
        )


class SubscriptionView(views.APIView):
    def get(self, request):
        tenant_id = request.query_params.get("tenant")
        if tenant_id:
            serializer = TenantRequestSerializer(
                data={"tenant": tenant_id}, context={"request": request}
            )
            serializer.is_valid(raise_exception=True)
            tenant = serializer.validated_data["tenant"]
            subscription = getattr(tenant, "subscription", None)
            if subscription is None:
                return response.Response({"plan": tenant.plan, "status": "active"})
            return response.Response(SubscriptionSerializer(subscription).data)
        subscription = (
            Subscription.objects.filter(tenant__memberships__user=request.user)
            .order_by("created_at")
            .first()
        )
        if subscription is None:
            return response.Response({"plan": "free", "status": "active"})
        return response.Response(SubscriptionSerializer(subscription).data)


class CheckoutView(views.APIView):
    def post(self, request):
        serializer = CheckoutRequestSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        tenant = serializer.validated_data["tenant"]
        if tenant.plan != "free":
            return response.Response(
                {
                    "detail": (
                        "This workspace already has a paid plan. "
                        "Use subscription management to change or cancel it."
                    )
                },
                status=409,
            )
        target_plan = serializer.validated_data["plan"]
        session = billing_provider().create_checkout_session(tenant, target_plan)
        return response.Response(session)


class PortalView(views.APIView):
    def post(self, request):
        serializer = OwnerTenantRequestSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        session = billing_provider().create_portal_session(serializer.validated_data["tenant"])
        return response.Response(session)


class UsageView(views.APIView):
    def get(self, request):
        serializer = TenantRequestSerializer(
            data={"tenant": request.query_params.get("tenant")},
            context={"request": request},
        )
        serializer.is_valid(raise_exception=True)
        return response.Response(usage_report_for_tenant(serializer.validated_data["tenant"]))

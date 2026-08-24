from __future__ import annotations

from django import forms
from django.contrib import admin
from django.core.exceptions import ValidationError
from django.db import transaction
from django.utils import timezone

from apps.audit.events import record_audit_event
from apps.subscriptions.models import Subscription
from apps.subscriptions.plans import PLAN_POLICIES
from apps.tenants.models import Organization
from apps.users.admin_site import owner_admin_site

SUBSCRIPTION_STATUSES = (
    "active",
    "trialing",
    "on_trial",
    "paused",
    "past_due",
    "unpaid",
    "canceled",
    "cancelled",
    "expired",
)
INACTIVE_STATUSES = {"canceled", "cancelled", "expired"}


class SubscriptionAdminForm(forms.ModelForm):
    plan = forms.ChoiceField(choices=[(key, key.title()) for key in PLAN_POLICIES])
    status = forms.ChoiceField(
        choices=[(value, value.replace("_", " ").title()) for value in SUBSCRIPTION_STATUSES]
    )

    class Meta:
        model = Subscription
        fields = ("tenant", "plan", "status")

    def clean(self):
        cleaned_data = super().clean()
        plan = cleaned_data.get("plan")
        status = cleaned_data.get("status")
        if plan and status in INACTIVE_STATUSES and plan != "free":
            raise ValidationError("Canceled or expired subscriptions must use the Free plan.")
        return cleaned_data


@admin.register(Subscription, site=owner_admin_site)
class SubscriptionAdmin(admin.ModelAdmin):
    form = SubscriptionAdminForm
    list_display = (
        "owner_email",
        "tenant_id_display",
        "plan",
        "status",
        "provider_display",
        "current_period_end",
        "updated_at",
    )
    list_filter = ("plan", "status", "billing_provider", "created_at")
    search_fields = ("tenant__owner_user__email", "plan", "status", "billing_provider")
    ordering = ("-updated_at",)
    list_per_page = 50
    actions = None
    fields = (
        "tenant",
        "owner_email",
        "plan",
        "status",
        "billing_provider",
        "current_period_end",
        "created_at",
        "updated_at",
    )
    readonly_fields = (
        "owner_email",
        "billing_provider",
        "current_period_end",
        "created_at",
        "updated_at",
    )

    def get_queryset(self, request):
        return super().get_queryset(request).select_related("tenant__owner_user")

    def get_readonly_fields(self, request, obj=None):
        readonly = list(super().get_readonly_fields(request, obj))
        if obj is not None:
            readonly.append("tenant")
        return readonly

    @admin.display(description="Owner", ordering="tenant__owner_user__email")
    def owner_email(self, obj):
        return obj.tenant.owner_user.email if obj and obj.tenant_id else "-"

    @admin.display(description="Tenant")
    def tenant_id_display(self, obj):
        return str(obj.tenant_id)

    @admin.display(description="Provider", ordering="billing_provider")
    def provider_display(self, obj):
        return obj.billing_provider or "Manual"

    @transaction.atomic
    def save_model(self, request, obj, form, change):
        previous = None
        if change:
            previous = Subscription.objects.only("plan", "status").get(pk=obj.pk)

        super().save_model(request, obj, form, change)
        Organization.objects.filter(pk=obj.tenant_id).update(
            plan=obj.plan, updated_at=timezone.now()
        )

        changes = {}
        for field in ("plan", "status"):
            old_value = getattr(previous, field, None)
            new_value = getattr(obj, field)
            if previous is None or old_value != new_value:
                changes[field] = {"from": old_value, "to": new_value}

        if changes:
            record_audit_event(
                event_type="admin.subscription.changed",
                actor_user=request.user,
                tenant=obj.tenant,
                target_type="subscription",
                target_id=obj.pk,
                metadata={"changes": changes, "source": "django-admin"},
            )

    def has_delete_permission(self, request, obj=None):
        return False

    def has_module_permission(self, request):
        return owner_admin_site.has_permission(request)

    def has_view_permission(self, request, obj=None):
        return self.has_module_permission(request)

    def has_add_permission(self, request):
        return self.has_module_permission(request)

    def has_change_permission(self, request, obj=None):
        return self.has_module_permission(request)

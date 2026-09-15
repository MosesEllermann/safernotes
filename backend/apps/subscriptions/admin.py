from __future__ import annotations

import csv

from django import forms
from django.contrib import admin
from django.core.exceptions import ValidationError
from django.db import transaction
from django.http import HttpResponse
from django.utils import timezone
from django.utils.html import format_html

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


class SubscriptionHealthFilter(admin.SimpleListFilter):
    title = "billing health"
    parameter_name = "health"

    def lookups(self, request, model_admin):
        return (("healthy", "Healthy"), ("attention", "Needs attention"))

    def queryset(self, request, queryset):
        if self.value() == "healthy":
            return queryset.filter(status__in=("active", "trialing", "on_trial"))
        if self.value() == "attention":
            return queryset.filter(status__in=("past_due", "unpaid"))
        return queryset


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
        "plan_badge",
        "status_badge",
        "provider_display",
        "current_period_end",
        "updated_at",
    )
    list_filter = (
        SubscriptionHealthFilter,
        "plan",
        "status",
        "billing_provider",
        "created_at",
    )
    search_fields = ("tenant__owner_user__email", "plan", "status", "billing_provider")
    ordering = ("-updated_at",)
    list_per_page = 50
    list_max_show_all = 200
    show_full_result_count = False
    actions = ("export_subscriptions_csv",)
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

    @admin.display(description="Plan", ordering="plan")
    def plan_badge(self, obj):
        tone = "accent" if obj.plan != "free" else "neutral"
        return format_html('<span class="sn-badge sn-badge--{}">{}</span>', tone, obj.plan)

    @admin.display(description="Status", ordering="status")
    def status_badge(self, obj):
        if obj.status in ("active", "trialing", "on_trial"):
            tone = "positive"
        elif obj.status in ("past_due", "unpaid"):
            tone = "danger"
        else:
            tone = "neutral"
        return format_html('<span class="sn-badge sn-badge--{}">{}</span>', tone, obj.status)

    @admin.action(description="Export selected subscriptions as CSV")
    def export_subscriptions_csv(self, request, queryset):
        response = HttpResponse(content_type="text/csv")
        response["Content-Disposition"] = 'attachment; filename="safernotes-subscriptions.csv"'
        writer = csv.writer(response)
        writer.writerow(
            (
                "owner_email",
                "tenant_id",
                "plan",
                "status",
                "provider",
                "current_period_end",
                "updated_at",
            )
        )
        for subscription in queryset.iterator():
            writer.writerow(
                (
                    self.owner_email(subscription),
                    subscription.tenant_id,
                    subscription.plan,
                    subscription.status,
                    self.provider_display(subscription),
                    subscription.current_period_end.isoformat()
                    if subscription.current_period_end
                    else "",
                    subscription.updated_at.isoformat(),
                )
            )
        return response

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

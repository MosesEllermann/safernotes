from __future__ import annotations

from django.contrib import admin
from django.db.models import Count
from django.urls import reverse
from django.utils.html import format_html

from apps.users.admin_site import owner_admin_site
from apps.users.models import User


class EmailVerificationFilter(admin.SimpleListFilter):
    title = "email verification"
    parameter_name = "email_verified"

    def lookups(self, request, model_admin):
        return (("yes", "Verified"), ("no", "Not verified"))

    def queryset(self, request, queryset):
        if self.value() == "yes":
            return queryset.filter(email_verified_at__isnull=False)
        if self.value() == "no":
            return queryset.filter(email_verified_at__isnull=True)
        return queryset


@admin.register(User, site=owner_admin_site)
class SafeUserAdmin(admin.ModelAdmin):
    """Operational account metadata only; cryptographic and auth material stays unregistered."""

    list_display = (
        "email",
        "status",
        "verification_state",
        "subscription_plan",
        "subscription_status",
        "billing_provider",
        "notes_count",
        "storage_usage",
        "created_at",
    )
    list_filter = (
        EmailVerificationFilter,
        "status",
        "is_active",
        "is_staff",
        "created_at",
    )
    search_fields = (
        "email",
        "status",
        "default_tenant__subscription__plan",
        "default_tenant__subscription__status",
        "default_tenant__subscription__billing_provider",
    )
    ordering = ("-created_at",)
    date_hierarchy = "created_at"
    list_per_page = 50
    actions = None
    fields = (
        "id",
        "email",
        "status",
        "email_verified_at",
        "is_active",
        "is_staff",
        "is_superuser",
        "default_tenant_id_display",
        "subscription_management",
        "subscription_plan",
        "subscription_status",
        "billing_provider",
        "notes_count",
        "storage_usage",
        "attachment_count",
        "last_login",
        "date_joined",
        "created_at",
        "updated_at",
    )
    readonly_fields = fields

    def get_queryset(self, request):
        return (
            super()
            .get_queryset(request)
            .select_related("default_tenant__subscription", "default_tenant__storage_usage")
            .annotate(admin_notes_count=Count("default_tenant__notes", distinct=True))
        )

    @admin.display(description="Verified", boolean=True, ordering="email_verified_at")
    def verification_state(self, obj):
        return obj.email_verified_at is not None

    @admin.display(description="Default tenant")
    def default_tenant_id_display(self, obj):
        return str(obj.default_tenant_id) if obj.default_tenant_id else "-"

    @admin.display(description="Plan", ordering="default_tenant__subscription__plan")
    def subscription_plan(self, obj):
        subscription = self._subscription(obj)
        if subscription:
            return subscription.plan
        return obj.default_tenant.plan if obj.default_tenant_id else "-"

    @admin.display(description="Subscription", ordering="default_tenant__subscription__status")
    def subscription_status(self, obj):
        subscription = self._subscription(obj)
        return subscription.status if subscription else "Not configured"

    @admin.display(
        description="Provider", ordering="default_tenant__subscription__billing_provider"
    )
    def billing_provider(self, obj):
        subscription = self._subscription(obj)
        return subscription.billing_provider or "Manual" if subscription else "-"

    @admin.display(description="Notes")
    def notes_count(self, obj):
        return getattr(obj, "admin_notes_count", 0)

    @admin.display(description="Storage")
    def storage_usage(self, obj):
        usage = self._storage_usage(obj)
        if usage is None:
            return "0 B"
        return self._format_bytes(usage.ciphertext_bytes_used)

    @admin.display(description="Attachments")
    def attachment_count(self, obj):
        usage = self._storage_usage(obj)
        return usage.attachments_count if usage else 0

    @admin.display(description="Manage subscription")
    def subscription_management(self, obj):
        if not obj.default_tenant_id:
            return "No default tenant"
        subscription = self._subscription(obj)
        if subscription:
            url = reverse(
                "owner_admin:subscriptions_subscription_change",
                args=(subscription.pk,),
            )
            return format_html('<a class="button" href="{}">Edit subscription</a>', url)
        url = reverse("owner_admin:subscriptions_subscription_add")
        return format_html(
            '<a class="button" href="{}?tenant={}">Create subscription</a>',
            url,
            obj.default_tenant_id,
        )

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def has_module_permission(self, request):
        return owner_admin_site.has_permission(request)

    def has_view_permission(self, request, obj=None):
        return self.has_module_permission(request)

    def has_change_permission(self, request, obj=None):
        return self.has_view_permission(request, obj)

    @staticmethod
    def _subscription(obj):
        tenant = obj.default_tenant
        if tenant is None:
            return None
        try:
            return tenant.subscription
        except tenant._meta.apps.get_model("subscriptions", "Subscription").DoesNotExist:
            return None

    @staticmethod
    def _storage_usage(obj):
        tenant = obj.default_tenant
        if tenant is None:
            return None
        try:
            return tenant.storage_usage
        except tenant._meta.apps.get_model("attachments", "TenantStorageUsage").DoesNotExist:
            return None

    @staticmethod
    def _format_bytes(value: int) -> str:
        amount = float(value)
        for unit in ("B", "KB", "MB", "GB", "TB"):
            if amount < 1024 or unit == "TB":
                return f"{amount:.0f} {unit}" if unit == "B" else f"{amount:.1f} {unit}"
            amount /= 1024
        return f"{value} B"

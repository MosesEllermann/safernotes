from __future__ import annotations

import csv

from django.contrib import admin, messages
from django.contrib.admin.helpers import ACTION_CHECKBOX_NAME
from django.db import transaction
from django.db.models import Count
from django.http import HttpResponse
from django.template.response import TemplateResponse
from django.utils.html import format_html

from apps.audit.events import record_audit_event
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
        "status_badge",
        "verification_state",
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
    )
    ordering = ("-created_at",)
    date_hierarchy = "created_at"
    list_per_page = 50
    list_max_show_all = 200
    show_full_result_count = False
    actions = ("export_accounts_csv", "activate_accounts", "deactivate_accounts")
    fields = (
        "id",
        "email",
        "status",
        "email_verified_at",
        "is_active",
        "is_staff",
        "is_superuser",
        "default_tenant_id_display",
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
            .select_related("default_tenant__storage_usage")
            .annotate(admin_notes_count=Count("default_tenant__notes", distinct=True))
        )

    @admin.display(description="Verified", boolean=True, ordering="email_verified_at")
    def verification_state(self, obj):
        return obj.email_verified_at is not None

    @admin.display(description="Status", ordering="status")
    def status_badge(self, obj):
        tone = "positive" if obj.is_active and obj.status == "active" else "warning"
        return self._badge(obj.status, tone)

    @admin.display(description="Default tenant")
    def default_tenant_id_display(self, obj):
        return str(obj.default_tenant_id) if obj.default_tenant_id else "-"

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

    @admin.action(description="Export selected accounts as CSV")
    def export_accounts_csv(self, request, queryset):
        response = HttpResponse(content_type="text/csv")
        response["Content-Disposition"] = 'attachment; filename="safernotes-accounts.csv"'
        writer = csv.writer(response)
        writer.writerow(
            (
                "email",
                "account_status",
                "active",
                "email_verified",
                "notes",
                "storage",
                "created_at",
            )
        )
        for account in queryset.iterator():
            writer.writerow(
                (
                    account.email,
                    account.status,
                    account.is_active,
                    account.email_verified_at is not None,
                    self.notes_count(account),
                    self.storage_usage(account),
                    account.created_at.isoformat(),
                )
            )
        return response

    @admin.action(description="Activate selected accounts")
    def activate_accounts(self, request, queryset):
        accounts = list(queryset.filter(is_superuser=False, is_active=False))
        with transaction.atomic():
            for account in accounts:
                previous_status = account.status
                account.is_active = True
                account.status = "active"
                account.save(update_fields=("is_active", "status", "updated_at"))
                self._audit_account_action(request, account, "activated", previous_status)
        self.message_user(
            request,
            f"Activated {len(accounts)} account(s).",
            messages.SUCCESS,
        )

    @admin.action(description="Deactivate selected accounts (reversible)")
    def deactivate_accounts(self, request, queryset):
        accounts = queryset.filter(is_superuser=False, is_active=True)
        if "apply" not in request.POST:
            return TemplateResponse(
                request,
                "admin/users/user/deactivate_confirmation.html",
                {
                    **self.admin_site.each_context(request),
                    "title": "Confirm account deactivation",
                    "opts": self.model._meta,
                    "accounts": accounts,
                    "action_checkbox_name": ACTION_CHECKBOX_NAME,
                    "action_name": "deactivate_accounts",
                },
            )

        accounts = list(accounts)
        with transaction.atomic():
            for account in accounts:
                previous_status = account.status
                account.is_active = False
                account.status = "suspended"
                account.save(update_fields=("is_active", "status", "updated_at"))
                self._audit_account_action(request, account, "deactivated", previous_status)
        self.message_user(
            request,
            f"Deactivated {len(accounts)} account(s). Superuser accounts were skipped.",
            messages.SUCCESS,
        )

    @staticmethod
    def _audit_account_action(request, account, action, previous_status):
        record_audit_event(
            event_type=f"admin.account.{action}",
            actor_user=request.user,
            tenant=account.default_tenant,
            target_type="user",
            metadata={
                "account_id": account.pk,
                "previous_status": previous_status,
                "source": "django-admin",
            },
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

    @staticmethod
    def _badge(value, tone):
        return format_html(
            '<span class="sn-badge sn-badge--{}">{}</span>',
            tone,
            value,
        )

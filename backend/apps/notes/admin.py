from __future__ import annotations

from django.contrib import admin
from django.utils import timezone
from django.utils.html import format_html
from django.utils.timesince import timesince

from apps.notes.models import ShareInvitation
from apps.users.admin_site import owner_admin_site


@admin.register(ShareInvitation, site=owner_admin_site)
class ShareInvitationAdmin(admin.ModelAdmin):
    """Invite diagnostics only; encrypted keys and signatures remain inaccessible."""

    list_display = (
        "note_reference",
        "sender_email",
        "recipient_email",
        "role",
        "status_badge",
        "age",
        "created_at",
    )
    list_filter = ("status", "role", "created_at")
    search_fields = ("sender_user__email", "recipient_user__email")
    ordering = ("-created_at",)
    date_hierarchy = "created_at"
    list_per_page = 50
    list_max_show_all = 200
    show_full_result_count = False
    actions = None
    fields = (
        "id",
        "note_reference",
        "sender_email",
        "recipient_email",
        "role",
        "status",
        "created_at",
        "accepted_at",
        "declined_at",
        "revoked_at",
        "updated_at",
    )
    readonly_fields = fields

    def get_queryset(self, request):
        return super().get_queryset(request).select_related("sender_user", "recipient_user")

    @admin.display(description="Note")
    def note_reference(self, obj):
        return format_html('<code class="sn-id">{}</code>', str(obj.note_id)[:8])

    @admin.display(description="Sender", ordering="sender_user__email")
    def sender_email(self, obj):
        return obj.sender_user.email

    @admin.display(description="Recipient", ordering="recipient_user__email")
    def recipient_email(self, obj):
        return obj.recipient_user.email

    @admin.display(description="Status", ordering="status")
    def status_badge(self, obj):
        tone = {
            "accepted": "positive",
            "pending": "warning",
            "declined": "neutral",
            "revoked": "danger",
        }.get(obj.status, "neutral")
        return format_html('<span class="sn-badge sn-badge--{}">{}</span>', tone, obj.status)

    @admin.display(description="Age", ordering="created_at")
    def age(self, obj):
        return f"{timesince(obj.created_at, timezone.now())} ago"

    def has_add_permission(self, request):
        return False

    def has_delete_permission(self, request, obj=None):
        return False

    def has_module_permission(self, request):
        return owner_admin_site.has_permission(request)

    def has_view_permission(self, request, obj=None):
        return self.has_module_permission(request)

    def has_change_permission(self, request, obj=None):
        return False

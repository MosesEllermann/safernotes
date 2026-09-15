from __future__ import annotations

from datetime import timedelta

from django.conf import settings
from django.contrib.admin import AdminSite
from django.db.models import Count, Q, Sum
from django.urls import reverse
from django.utils import timezone


class OwnerAdminSite(AdminSite):
    site_header = "Safernotes operations"
    site_title = "Safernotes admin"
    index_title = "Owner dashboard"
    index_template = "admin/index.html"

    def has_permission(self, request):
        return bool(request.user.is_active and request.user.is_superuser)

    def index(self, request, extra_context=None):
        """Render operational metadata without exposing encrypted user content."""
        dashboard_context = self._dashboard_context()
        dashboard_context.update(extra_context or {})
        return super().index(request, extra_context=dashboard_context)

    def _dashboard_context(self):
        # Import lazily so Django can finish populating the app registry first.
        from apps.attachments.models import TenantStorageUsage
        from apps.audit.models import AuditEvent
        from apps.notes.models import Note, ShareInvitation, ShareInvitationStatus
        from apps.subscriptions.models import Subscription
        from apps.users.models import User

        now = timezone.now()
        last_week = now - timedelta(days=7)
        stale_invite_cutoff = now - timedelta(hours=24)

        user_totals = User.objects.aggregate(
            total=Count("pk"),
            active=Count("pk", filter=Q(is_active=True)),
            verified=Count("pk", filter=Q(email_verified_at__isnull=False)),
            new_this_week=Count("pk", filter=Q(created_at__gte=last_week)),
        )
        subscription_totals = Subscription.objects.aggregate(
            active=Count("pk", filter=Q(status__in=("active", "trialing", "on_trial"))),
            attention=Count("pk", filter=Q(status__in=("past_due", "unpaid"))),
        )
        invitation_totals = ShareInvitation.objects.aggregate(
            pending=Count("pk", filter=Q(status=ShareInvitationStatus.PENDING)),
            stale=Count(
                "pk",
                filter=Q(
                    status=ShareInvitationStatus.PENDING,
                    created_at__lt=stale_invite_cutoff,
                ),
            ),
        )
        storage_bytes = (
            TenantStorageUsage.objects.aggregate(total=Sum("ciphertext_bytes_used"))["total"] or 0
        )

        plan_rows = list(
            Subscription.objects.values("plan")
            .annotate(total=Count("pk"))
            .order_by("-total", "plan")
        )
        plan_total = sum(row["total"] for row in plan_rows)
        for row in plan_rows:
            row["percentage"] = round((row["total"] / plan_total) * 100) if plan_total else 0

        recent_users = []
        for user in User.objects.only("pk", "email", "status", "created_at").order_by(
            "-created_at"
        )[:5]:
            recent_users.append(
                {
                    "email": user.email,
                    "status": user.status,
                    "created_at": user.created_at,
                    "url": reverse("owner_admin:users_user_change", args=(user.pk,)),
                }
            )

        recent_events = list(
            AuditEvent.objects.select_related("actor_user")
            .only("event_type", "target_type", "created_at", "actor_user__email")
            .order_by("-created_at")[:7]
        )

        return {
            "dashboard": {
                "users": user_totals,
                "subscriptions": subscription_totals,
                "invitations": invitation_totals,
                "notes": Note.objects.count(),
                "storage": self._format_bytes(storage_bytes),
                "plans": plan_rows,
                "recent_users": recent_users,
                "recent_events": recent_events,
                "generated_at": now,
                "environment": "Development" if settings.DEBUG else "Production",
            }
        }

    @staticmethod
    def _format_bytes(value: int) -> str:
        amount = float(value)
        for unit in ("B", "KB", "MB", "GB", "TB"):
            if amount < 1024 or unit == "TB":
                return f"{amount:.0f} {unit}" if unit == "B" else f"{amount:.1f} {unit}"
            amount /= 1024
        return f"{value} B"


owner_admin_site = OwnerAdminSite(name="owner_admin")

"""Root API routing."""

from __future__ import annotations

from django.urls import include, path

from apps.core.views import HealthLiveView, HealthReadyView
from apps.users.admin_site import owner_admin_site

urlpatterns = [
    path("owner-admin/", owner_admin_site.urls),
    path("api/v1/health/live", HealthLiveView.as_view(), name="health-live"),
    path("api/v1/health/ready", HealthReadyView.as_view(), name="health-ready"),
    path("api/v1/auth/", include("apps.authentication.urls")),
    path("api/v1/users/", include("apps.users.urls")),
    path("api/v1/devices/", include("apps.devices.urls")),
    path("api/v1/tenants/", include("apps.tenants.urls")),
    path("api/v1/notes/", include("apps.notes.urls")),
    path("api/v1/attachments/", include("apps.attachments.urls")),
    path("api/v1/collaboration/", include("apps.collaboration.urls")),
    path("api/v1/notifications/", include("apps.notifications.urls")),
    path("api/v1/search/", include("apps.search.urls")),
]

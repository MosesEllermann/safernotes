from __future__ import annotations

from django.contrib.admin import AdminSite


class OwnerAdminSite(AdminSite):
    site_header = "Safernotes operations"
    site_title = "Safernotes admin"
    index_title = "Owner dashboard"

    def has_permission(self, request):
        return bool(request.user.is_active and request.user.is_superuser)


owner_admin_site = OwnerAdminSite(name="owner_admin")

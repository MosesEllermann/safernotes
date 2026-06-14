from __future__ import annotations

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from apps.tenants.views import MembershipViewSet, OrganizationViewSet

router = DefaultRouter()
router.register("memberships", MembershipViewSet, basename="memberships")
router.register("", OrganizationViewSet, basename="tenants")

urlpatterns = [path("", include(router.urls))]


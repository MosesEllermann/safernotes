from __future__ import annotations

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from apps.devices.views import DeviceViewSet

router = DefaultRouter()
router.register("", DeviceViewSet, basename="devices")

urlpatterns = [path("", include(router.urls))]


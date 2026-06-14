from __future__ import annotations

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from apps.attachments.views import AttachmentViewSet

router = DefaultRouter()
router.register("", AttachmentViewSet, basename="attachments")

urlpatterns = [path("", include(router.urls))]


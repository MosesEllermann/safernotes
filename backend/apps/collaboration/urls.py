from __future__ import annotations

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from apps.collaboration.views import (
    CollaborationPresenceViewSet,
    SyncEventAckViewSet,
    SyncEventViewSet,
)

router = DefaultRouter()
router.register("events", SyncEventViewSet, basename="collaboration-events")
router.register("acks", SyncEventAckViewSet, basename="collaboration-event-acks")
router.register("presence", CollaborationPresenceViewSet, basename="collaboration-presence")

urlpatterns = [path("", include(router.urls))]

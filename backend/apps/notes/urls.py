from __future__ import annotations

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from apps.notes.sync import SyncBatchView, SyncChangesView
from apps.notes.views import LabelViewSet, NoteKeyGrantViewSet, NoteViewSet, ShareInvitationViewSet

router = DefaultRouter()
router.register("labels", LabelViewSet, basename="labels")
router.register("grants", NoteKeyGrantViewSet, basename="note-grants")
router.register("invitations", ShareInvitationViewSet, basename="share-invitations")
router.register("", NoteViewSet, basename="notes")

urlpatterns = [
    path("sync/changes", SyncChangesView.as_view(), name="sync-changes"),
    path("sync/batch", SyncBatchView.as_view(), name="sync-batch"),
    path("", include(router.urls)),
]

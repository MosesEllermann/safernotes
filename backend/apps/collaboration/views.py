from __future__ import annotations

from django.db.models import Q
from rest_framework import viewsets

from apps.collaboration.models import CollaborationPresence, SyncEvent, SyncEventAck
from apps.collaboration.serializers import (
    CollaborationPresenceSerializer,
    SyncEventAckSerializer,
    SyncEventSerializer,
)


class SyncEventViewSet(viewsets.ModelViewSet):
    serializer_class = SyncEventSerializer

    def get_queryset(self):
        return SyncEvent.objects.filter(
            Q(note__owner_user=self.request.user)
            | Q(note__key_grants__recipient_user=self.request.user, note__key_grants__revoked_at__isnull=True)
        ).distinct()


class SyncEventAckViewSet(viewsets.ModelViewSet):
    serializer_class = SyncEventAckSerializer

    def get_queryset(self):
        return SyncEventAck.objects.filter(user=self.request.user)


class CollaborationPresenceViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = CollaborationPresenceSerializer

    def get_queryset(self):
        return CollaborationPresence.objects.filter(
            Q(note__owner_user=self.request.user)
            | Q(note__key_grants__recipient_user=self.request.user, note__key_grants__revoked_at__isnull=True)
        ).distinct()

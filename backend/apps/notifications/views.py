from __future__ import annotations

from django.utils import timezone
from rest_framework import decorators, response, viewsets

from apps.notifications.models import Notification
from apps.notifications.serializers import (
    EncryptedNotificationFanoutSerializer,
    NotificationSerializer,
)


class NotificationViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = NotificationSerializer

    def get_queryset(self):
        return Notification.objects.filter(user=self.request.user)

    @decorators.action(detail=True, methods=["patch"])
    def read(self, request, pk=None):
        notification = self.get_object()
        notification.read_at = timezone.now()
        notification.save(update_fields=["read_at", "updated_at"])
        return response.Response(NotificationSerializer(notification).data)

    @decorators.action(detail=False, methods=["post"], url_path="fanout")
    def fanout(self, request):
        serializer = EncryptedNotificationFanoutSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        notifications = serializer.save()
        return response.Response({"created": len(notifications)}, status=201)

from __future__ import annotations

from django.utils import timezone
from rest_framework import response, viewsets

from apps.devices.models import Device
from apps.devices.serializers import DeviceSerializer


class DeviceViewSet(viewsets.ModelViewSet):
    serializer_class = DeviceSerializer

    def get_queryset(self):
        return Device.objects.filter(user=self.request.user)

    def destroy(self, request, *args, **kwargs):
        device = self.get_object()
        device.revoked_at = timezone.now()
        device.save(update_fields=["revoked_at", "updated_at"])
        device.sessions.filter(revoked_at__isnull=True).update(
            revoked_at=device.revoked_at,
            updated_at=device.revoked_at,
        )
        return response.Response(status=204)

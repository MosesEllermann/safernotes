from __future__ import annotations

from django.db import connection
from rest_framework import permissions, response, views


class HealthLiveView(views.APIView):
    permission_classes = [permissions.AllowAny]
    authentication_classes = []
    throttle_classes = []

    def get(self, request):
        return response.Response({"status": "ok"})


class HealthReadyView(views.APIView):
    permission_classes = [permissions.AllowAny]
    authentication_classes = []
    throttle_classes = []

    def get(self, request):
        with connection.cursor() as cursor:
            cursor.execute("SELECT 1")
            cursor.fetchone()
        return response.Response({"status": "ready"})

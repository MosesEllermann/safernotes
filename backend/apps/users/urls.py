from __future__ import annotations

from django.urls import path

from apps.users.views import MeView, PublicKeysView

urlpatterns = [
    path("me", MeView.as_view(), name="me"),
    path("<uuid:pk>/public-keys", PublicKeysView.as_view(), name="public-keys"),
]


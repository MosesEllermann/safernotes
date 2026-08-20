from __future__ import annotations

from django.urls import path

from apps.users.views import MeView, PreferencesView, PublicKeysView

urlpatterns = [
    path("me", MeView.as_view(), name="me"),
    path("me/preferences", PreferencesView.as_view(), name="me-preferences"),
    path("<uuid:pk>/public-keys", PublicKeysView.as_view(), name="public-keys"),
]

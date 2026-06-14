from __future__ import annotations

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from apps.authentication.views import (
    LoginView,
    LogoutView,
    RecoveryStartView,
    RefreshView,
    RegisterView,
    SessionViewSet,
)

router = DefaultRouter()
router.register("sessions", SessionViewSet, basename="sessions")

urlpatterns = [
    path("register", RegisterView.as_view(), name="register"),
    path("login", LoginView.as_view(), name="login"),
    path("refresh", RefreshView.as_view(), name="refresh"),
    path("logout", LogoutView.as_view(), name="logout"),
    path("recovery/start", RecoveryStartView.as_view(), name="recovery-start"),
    path("", include(router.urls)),
]

from __future__ import annotations

from django.urls import include, path
from rest_framework.routers import DefaultRouter

from apps.authentication.views import (
    EmailVerificationConfirmView,
    EmailVerificationResendView,
    LoginView,
    LogoutView,
    PasswordChangeView,
    RecoveryCompleteView,
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
    path("email/verification/resend", EmailVerificationResendView.as_view(), name="email-verification-resend"),
    path("email/verification/confirm", EmailVerificationConfirmView.as_view(), name="email-verification-confirm"),
    path("password/change", PasswordChangeView.as_view(), name="password-change"),
    path("recovery/start", RecoveryStartView.as_view(), name="recovery-start"),
    path("recovery/complete", RecoveryCompleteView.as_view(), name="recovery-complete"),
    path("", include(router.urls)),
]

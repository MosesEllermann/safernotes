from __future__ import annotations

from django.contrib.auth import login, logout
from django.utils import timezone
from rest_framework import decorators, permissions, response, views, viewsets

from apps.audit.events import record_audit_event
from apps.authentication.models import Session
from apps.authentication.serializers import (
    KeyMaterialSerializer,
    LoginSerializer,
    RecoveryStartSerializer,
    RefreshSerializer,
    RegistrationSerializer,
    SessionSerializer,
)
from apps.authentication.tokens import issue_session, rotate_refresh_token


class RegisterView(views.APIView):
    permission_classes = [permissions.AllowAny]
    throttle_scope = "register"

    def post(self, request):
        serializer = RegistrationSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.save()
        login(request, user)
        issued = issue_session(user, device=getattr(serializer, "device", None), request=request)
        record_audit_event(
            event_type="auth.registered",
            actor_user=user,
            target_type="user",
            target_id=user.id,
            metadata={"session_id": str(issued.session.id)},
        )
        return response.Response(
            {
                "id": str(user.id),
                "email": user.email,
                "access_token": issued.access_token,
                "refresh_token": issued.refresh_token,
                "session_id": str(issued.session.id),
                "default_tenant": str(user.default_tenant_id),
            },
            status=201,
        )


class LoginView(views.APIView):
    permission_classes = [permissions.AllowAny]
    throttle_scope = "login"

    def post(self, request):
        serializer = LoginSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]
        device = serializer.validated_data["device"]
        login(request, user)
        issued = issue_session(user, device=device, request=request)
        record_audit_event(
            event_type="auth.login",
            actor_user=user,
            target_type="session",
            target_id=issued.session.id,
            metadata={"device_id": str(device.id) if device else None},
        )
        return response.Response(
            {
                "id": str(user.id),
                "email": user.email,
                "access_token": issued.access_token,
                "refresh_token": issued.refresh_token,
                "session_id": str(issued.session.id),
                "default_tenant": str(user.default_tenant_id) if user.default_tenant_id else None,
                "key_material": KeyMaterialSerializer(user.key_material).data,
            }
        )


class RefreshView(views.APIView):
    permission_classes = [permissions.AllowAny]
    throttle_scope = "refresh"

    def post(self, request):
        serializer = RefreshSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        issued = rotate_refresh_token(serializer.validated_data["session"])
        record_audit_event(
            event_type="auth.refresh",
            actor_user=issued.session.user,
            target_type="session",
            target_id=issued.session.id,
        )
        return response.Response(
            {
                "access_token": issued.access_token,
                "refresh_token": issued.refresh_token,
                "session_id": str(issued.session.id),
            }
        )


class LogoutView(views.APIView):
    def post(self, request):
        if getattr(request, "auth", None):
            request.auth.revoked_at = timezone.now()
            request.auth.save(update_fields=["revoked_at", "updated_at"])
            record_audit_event(
                event_type="auth.logout",
                actor_user=request.user,
                target_type="session",
                target_id=request.auth.id,
            )
        logout(request)
        return response.Response(status=204)


class RecoveryStartView(views.APIView):
    permission_classes = [permissions.AllowAny]
    throttle_scope = "recovery"

    def post(self, request):
        serializer = RecoveryStartSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        user = serializer.validated_data["user"]
        if user is None or not hasattr(user, "key_material"):
            return response.Response({"recovery_available": False})
        material = user.key_material
        return response.Response(
            {
                "recovery_available": bool(material.recovery_wrapper),
                "kdf_algorithm": material.kdf_algorithm,
                "kdf_params": material.kdf_params,
                "recovery_wrapper": material.recovery_wrapper,
                "key_version": material.key_version,
            }
        )


class SessionViewSet(viewsets.ReadOnlyModelViewSet):
    serializer_class = SessionSerializer

    def get_queryset(self):
        return Session.objects.filter(user=self.request.user).order_by("-created_at")

    @decorators.action(detail=True, methods=["post"])
    def revoke(self, request, pk=None):
        session = self.get_object()
        session.revoked_at = timezone.now()
        session.save(update_fields=["revoked_at", "updated_at"])
        record_audit_event(
            event_type="auth.session_revoked",
            actor_user=request.user,
            target_type="session",
            target_id=session.id,
        )
        return response.Response(SessionSerializer(session).data)

    @decorators.action(detail=False, methods=["post"], url_path="revoke-others")
    def revoke_others(self, request):
        now = timezone.now()
        current_session = getattr(request, "auth", None)
        queryset = self.get_queryset().filter(revoked_at__isnull=True)
        if current_session:
            queryset = queryset.exclude(id=current_session.id)
        count = queryset.update(revoked_at=now, updated_at=now)
        record_audit_event(
            event_type="auth.sessions_revoked",
            actor_user=request.user,
            target_type="user",
            target_id=request.user.id,
            metadata={"count": count},
        )
        return response.Response({"revoked": count})

from __future__ import annotations

import secrets
from datetime import timedelta

from django.contrib.auth import login, logout
from django.core.mail import send_mail
from django.db import models, transaction
from django.utils import timezone
from rest_framework import decorators, permissions, response, views, viewsets

from apps.audit.events import record_audit_event
from apps.authentication.models import RecoveryCode, Session
from apps.authentication.serializers import (
    KeyMaterialSerializer,
    LoginSerializer,
    PasswordChangeSerializer,
    RecoveryCompleteSerializer,
    RecoveryStartSerializer,
    RefreshSerializer,
    RegistrationSerializer,
    SessionSerializer,
)
from apps.authentication.tokens import hash_token, issue_session, rotate_refresh_token
from apps.users.models import User


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


class PasswordChangeView(views.APIView):
    @transaction.atomic
    def post(self, request):
        serializer = PasswordChangeSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        material = request.user.key_material
        material.kdf_algorithm = data["kdf_algorithm"]
        material.kdf_params = data["kdf_params"]
        material.password_salt = data["password_salt"].encode("utf-8")
        material.encrypted_master_key = data["encrypted_master_key"]
        material.key_version += 1
        material.save(
            update_fields=[
                "kdf_algorithm",
                "kdf_params",
                "password_salt",
                "encrypted_master_key",
                "key_version",
                "updated_at",
            ]
        )
        request.user.set_password(data["new_password"])
        request.user.save(update_fields=["password", "updated_at"])
        record_audit_event(
            event_type="auth.password_changed",
            actor_user=request.user,
            target_type="user",
            target_id=request.user.id,
        )
        return response.Response({"key_material": KeyMaterialSerializer(material).data})


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
        if material.recovery_wrapper:
            code = f"{secrets.randbelow(1_000_000):06d}"
            RecoveryCode.objects.create(
                user=user,
                code_hash=hash_token(code),
                expires_at=timezone.now() + timedelta(minutes=15),
            )
            send_mail(
                "Your ZK Notes recovery code",
                f"Use this recovery code to reset your ZK Notes password: {code}\n\n"
                "The code expires in 15 minutes. If you did not request it, you can ignore this email.",
                None,
                [user.email],
                fail_silently=True,
            )
        return response.Response(
            {
                "recovery_available": bool(material.recovery_wrapper),
                "kdf_algorithm": material.kdf_algorithm,
                "kdf_params": material.kdf_params,
                "recovery_wrapper": material.recovery_wrapper,
                "key_version": material.key_version,
            }
        )


class RecoveryCompleteView(views.APIView):
    permission_classes = [permissions.AllowAny]
    throttle_scope = "recovery"

    @transaction.atomic
    def post(self, request):
        serializer = RecoveryCompleteSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        data = serializer.validated_data
        user = User.objects.select_for_update().filter(email__iexact=data["email"]).first()
        if user is None or not hasattr(user, "key_material"):
            return response.Response({"detail": "Invalid recovery code."}, status=400)

        now = timezone.now()
        recovery_code = (
            RecoveryCode.objects.select_for_update()
            .filter(
                user=user,
                code_hash=hash_token(data["code"]),
                used_at__isnull=True,
                expires_at__gt=now,
            )
            .order_by("-created_at")
            .first()
        )
        if recovery_code is None:
            RecoveryCode.objects.filter(user=user, used_at__isnull=True, expires_at__gt=now).update(
                attempts=models.F("attempts") + 1
            )
            return response.Response({"detail": "Invalid recovery code."}, status=400)
        if recovery_code.attempts >= 5:
            return response.Response({"detail": "Too many recovery attempts."}, status=429)

        material = user.key_material
        material.kdf_algorithm = data["kdf_algorithm"]
        material.kdf_params = data["kdf_params"]
        material.password_salt = data["password_salt"].encode("utf-8")
        material.encrypted_master_key = data["encrypted_master_key"]
        material.key_version += 1
        material.save(
            update_fields=[
                "kdf_algorithm",
                "kdf_params",
                "password_salt",
                "encrypted_master_key",
                "key_version",
                "updated_at",
            ]
        )
        user.set_password(data["password"])
        user.save(update_fields=["password", "updated_at"])
        recovery_code.used_at = now
        recovery_code.save(update_fields=["used_at", "updated_at"])
        Session.objects.filter(user=user, revoked_at__isnull=True).update(revoked_at=now, updated_at=now)

        login(request, user)
        issued = issue_session(user, request=request)
        record_audit_event(
            event_type="auth.password_recovered",
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
                "default_tenant": str(user.default_tenant_id) if user.default_tenant_id else None,
                "key_material": KeyMaterialSerializer(material).data,
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

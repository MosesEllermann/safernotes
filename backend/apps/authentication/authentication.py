from __future__ import annotations

from django.utils import timezone
from rest_framework import authentication, exceptions

from apps.authentication.models import Session
from apps.authentication.tokens import hash_token


class BearerTokenAuthentication(authentication.BaseAuthentication):
    keyword = "Bearer"

    def authenticate(self, request):
        header = authentication.get_authorization_header(request).decode("utf-8")
        if not header:
            return None
        parts = header.split()
        if len(parts) != 2 or parts[0] != self.keyword:
            return None
        token_hash = hash_token(parts[1])
        session = (
            Session.objects.select_related("user", "device")
            .filter(access_token_hash=token_hash, revoked_at__isnull=True, expires_at__gt=timezone.now())
            .first()
        )
        if session is None:
            raise exceptions.AuthenticationFailed("Invalid or expired access token.")
        if session.device and session.device.revoked_at:
            raise exceptions.AuthenticationFailed("Device has been revoked.")
        return (session.user, session)


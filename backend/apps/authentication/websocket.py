from __future__ import annotations

from urllib.parse import parse_qs

from channels.db import database_sync_to_async
from django.contrib.auth.models import AnonymousUser
from django.utils import timezone

from apps.authentication.models import Session
from apps.authentication.tokens import hash_token


@database_sync_to_async
def user_for_token(token: str):
    session = (
        Session.objects.select_related("user", "device")
        .filter(access_token_hash=hash_token(token), revoked_at__isnull=True, expires_at__gt=timezone.now())
        .first()
    )
    if session is None:
        return AnonymousUser(), None
    if session.device and session.device.revoked_at:
        return AnonymousUser(), None
    return session.user, session


class BearerTokenAuthMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        query = parse_qs(scope.get("query_string", b"").decode("utf-8"))
        token = (query.get("token") or [None])[0]
        if token:
            scope["user"], scope["auth"] = await user_for_token(token)
        else:
            scope["user"], scope["auth"] = AnonymousUser(), None
        return await self.app(scope, receive, send)


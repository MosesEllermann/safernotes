from __future__ import annotations

import hashlib
import secrets
from dataclasses import dataclass
from datetime import timedelta

from django.conf import settings
from django.utils import timezone

from apps.authentication.models import Session

ACCESS_TOKEN_BYTES = 32
REFRESH_TOKEN_BYTES = 48


@dataclass(frozen=True)
class IssuedTokens:
    access_token: str
    refresh_token: str
    session: Session


def hash_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def hash_request_value(value: str) -> str:
    if not value:
        return ""
    salt = settings.SECRET_KEY.encode("utf-8")
    return hashlib.blake2b(value.encode("utf-8"), key=salt, digest_size=32).hexdigest()


def make_access_token() -> str:
    return secrets.token_urlsafe(ACCESS_TOKEN_BYTES)


def make_refresh_token() -> str:
    return secrets.token_urlsafe(REFRESH_TOKEN_BYTES)


def issue_session(user, *, device=None, request=None) -> IssuedTokens:
    access_token = make_access_token()
    refresh_token = make_refresh_token()
    ip = request.META.get("REMOTE_ADDR", "") if request else ""
    user_agent = request.META.get("HTTP_USER_AGENT", "") if request else ""
    session = Session.objects.create(
        user=user,
        device=device,
        access_token_hash=hash_token(access_token),
        refresh_token_hash=hash_token(refresh_token),
        ip_hash=hash_request_value(ip),
        user_agent_hash=hash_request_value(user_agent),
        expires_at=timezone.now() + timedelta(days=30),
    )
    return IssuedTokens(access_token=access_token, refresh_token=refresh_token, session=session)


def rotate_refresh_token(session: Session) -> IssuedTokens:
    access_token = make_access_token()
    refresh_token = make_refresh_token()
    session.previous_refresh_token_hash = session.refresh_token_hash
    session.access_token_hash = hash_token(access_token)
    session.refresh_token_hash = hash_token(refresh_token)
    session.refreshed_at = timezone.now()
    session.save(
        update_fields=[
            "access_token_hash",
            "refresh_token_hash",
            "previous_refresh_token_hash",
            "refreshed_at",
            "updated_at",
        ]
    )
    return IssuedTokens(access_token=access_token, refresh_token=refresh_token, session=session)


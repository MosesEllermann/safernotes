from __future__ import annotations

from datetime import timedelta

from django.utils import timezone

from apps.authentication.models import Session
from apps.authentication.tokens import hash_token, rotate_refresh_token


def test_hash_token_is_deterministic_and_does_not_store_raw_token():
    token = "raw-refresh-token"

    assert hash_token(token) == hash_token(token)
    assert hash_token(token) != token


def test_rotate_refresh_token_replaces_hashes(db, django_user_model):
    user = django_user_model.objects.create_user(email="user@example.com", password="strong-password")
    session = Session.objects.create(
        user=user,
        access_token_hash=hash_token("old-access"),
        refresh_token_hash=hash_token("old-refresh"),
        expires_at=timezone.now() + timedelta(days=30),
    )

    issued = rotate_refresh_token(session)
    session.refresh_from_db()

    assert issued.access_token
    assert issued.refresh_token
    assert session.access_token_hash != hash_token("old-access")
    assert session.refresh_token_hash != hash_token("old-refresh")
    assert session.previous_refresh_token_hash == hash_token("old-refresh")


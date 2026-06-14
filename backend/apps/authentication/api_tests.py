from __future__ import annotations

from django.contrib.sessions.middleware import SessionMiddleware
from rest_framework.test import APIRequestFactory

from apps.authentication.views import LoginView, RegisterView


def encrypted_payload():
    return {
        "version": 1,
        "algorithm": "XCHACHA20_POLY1305",
        "nonce": "nonce",
        "ciphertext": "ciphertext",
    }


def registration_payload(email="new@example.com"):
    return {
        "email": email,
        "password": "very-strong-password",
        "kdf_params": {"m": 65536, "t": 3, "p": 1},
        "password_salt": "salt",
        "public_encryption_key": "public-encryption-key",
        "public_signing_key": "public-signing-key",
        "public_encryption_key_fingerprint": "enc-fingerprint",
        "public_signing_key_fingerprint": "sig-fingerprint",
        "encrypted_master_key": encrypted_payload(),
        "encrypted_private_encryption_key": encrypted_payload(),
        "encrypted_private_signing_key": encrypted_payload(),
        "default_tenant_name_ciphertext": encrypted_payload(),
    }


def attach_session(request):
    middleware = SessionMiddleware(lambda req: None)
    middleware.process_request(request)
    request.session.save()
    return request


def test_register_view_returns_tokens(db):
    request = APIRequestFactory().post("/api/v1/auth/register", registration_payload(), format="json")
    attach_session(request)
    response = RegisterView.as_view()(request)

    assert response.status_code == 201
    assert response.data["access_token"]
    assert response.data["refresh_token"]
    assert response.data["default_tenant"]


def test_login_view_returns_key_material(db, django_user_model):
    from apps.authentication.models import KeyMaterial

    user = django_user_model.objects.create_user(email="login@example.com", password="very-strong-password")
    KeyMaterial.objects.create(
        user=user,
        kdf_params={"m": 65536, "t": 3, "p": 1},
        password_salt=b"salt",
        public_encryption_key=b"public-encryption-key",
        public_signing_key=b"public-signing-key",
        encrypted_master_key=encrypted_payload(),
        encrypted_private_encryption_key=encrypted_payload(),
        encrypted_private_signing_key=encrypted_payload(),
    )
    request = APIRequestFactory().post(
        "/api/v1/auth/login",
        {"email": "login@example.com", "password": "very-strong-password"},
        format="json",
    )
    attach_session(request)
    response = LoginView.as_view()(request)

    assert response.status_code == 200
    assert response.data["key_material"]["encrypted_master_key"]["ciphertext"] == "ciphertext"

from __future__ import annotations

from datetime import timedelta

from django.contrib.sessions.middleware import SessionMiddleware
from django.core import mail
from django.test import override_settings
from rest_framework.test import APIRequestFactory, force_authenticate

from apps.authentication.tokens import hash_token
from apps.authentication.views import (
    EmailVerificationConfirmView,
    EmailVerificationResendView,
    EmailVerificationStatusView,
    LoginView,
    PasswordChangeView,
    RecoveryCompleteView,
    RecoveryKeyView,
    RecoveryStartView,
    RegisterView,
)


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
        "recovery_wrapper": encrypted_payload(),
        "default_tenant_name_ciphertext": encrypted_payload(),
    }


def attach_session(request):
    middleware = SessionMiddleware(lambda req: None)
    middleware.process_request(request)
    request.session.save()
    return request


def test_register_view_returns_tokens(db):
    from apps.authentication.models import EmailVerificationCode

    request = APIRequestFactory().post(
        "/api/v1/auth/register", registration_payload(), format="json"
    )
    attach_session(request)
    response = RegisterView.as_view()(request)

    assert response.status_code == 201
    assert response.data["access_token"]
    assert response.data["refresh_token"]
    assert response.data["default_tenant"]
    assert response.data["email_verified"] is False
    assert EmailVerificationCode.objects.filter(user__email="new@example.com").exists()


def test_register_requires_encrypted_recovery_wrapper(db, django_user_model):
    payload = registration_payload(email="missing-recovery@example.com")
    payload.pop("recovery_wrapper")
    request = APIRequestFactory().post("/api/v1/auth/register", payload, format="json")
    attach_session(request)
    response = RegisterView.as_view()(request)

    assert response.status_code == 400
    assert not django_user_model.objects.filter(email="missing-recovery@example.com").exists()


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
def test_register_sends_localized_verification_email(db):
    request = APIRequestFactory().post(
        "/api/v1/auth/register",
        registration_payload(email="de-register@example.com") | {"locale": "de"},
        format="json",
    )
    attach_session(request)
    response = RegisterView.as_view()(request)

    assert response.status_code == 201
    assert len(mail.outbox) == 1
    message = mail.outbox[0]
    assert message.subject == "Dein Safernotes Bestätigungscode"
    assert "sechsstelligen Code" in message.body
    assert message.alternatives[0][1] == "text/html"
    assert "Dein Bestätigungscode" in message.alternatives[0][0]


def test_login_view_returns_key_material(db, django_user_model):
    from apps.authentication.models import KeyMaterial

    user = django_user_model.objects.create_user(
        email="login@example.com", password="very-strong-password"
    )
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


def test_recovery_complete_rewraps_master_key(db, django_user_model):
    from django.utils import timezone

    from apps.authentication.models import KeyMaterial, RecoveryCode

    user = django_user_model.objects.create_user(
        email="recover@example.com", password="old-password"
    )
    KeyMaterial.objects.create(
        user=user,
        kdf_params={"m": 65536, "t": 3, "p": 1},
        password_salt=b"old-salt",
        public_encryption_key=b"public-encryption-key",
        public_signing_key=b"public-signing-key",
        encrypted_master_key=encrypted_payload(),
        encrypted_private_encryption_key=encrypted_payload(),
        encrypted_private_signing_key=encrypted_payload(),
        recovery_wrapper=encrypted_payload(),
    )
    RecoveryCode.objects.create(
        user=user,
        code_hash=hash_token("123456"),
        expires_at=timezone.now() + timedelta(minutes=15),
    )
    request = APIRequestFactory().post(
        "/api/v1/auth/recovery/complete",
        {
            "email": "recover@example.com",
            "code": "123456",
            "password": "new-strong-password",
            "kdf_algorithm": "pbkdf2-sha256",
            "kdf_params": {"iterations": 210000, "bits": 256},
            "password_salt": "new-salt",
            "encrypted_master_key": {**encrypted_payload(), "ciphertext": "new-ciphertext"},
        },
        format="json",
    )
    attach_session(request)
    response = RecoveryCompleteView.as_view()(request)

    assert response.status_code == 200
    assert response.data["access_token"]
    user.refresh_from_db()
    assert user.check_password("new-strong-password")
    user.key_material.refresh_from_db()
    assert user.key_material.encrypted_master_key["ciphertext"] == "new-ciphertext"


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
def test_recovery_start_sends_localized_email(db, django_user_model):
    from apps.authentication.models import KeyMaterial
    from apps.users.models import Profile

    user = django_user_model.objects.create_user(
        email="recover-de@example.com", password="old-password"
    )
    Profile.objects.create(user=user, locale="de")
    KeyMaterial.objects.create(
        user=user,
        kdf_params={"m": 65536, "t": 3, "p": 1},
        password_salt=b"old-salt",
        public_encryption_key=b"public-encryption-key",
        public_signing_key=b"public-signing-key",
        encrypted_master_key=encrypted_payload(),
        encrypted_private_encryption_key=encrypted_payload(),
        encrypted_private_signing_key=encrypted_payload(),
        recovery_wrapper=encrypted_payload(),
    )
    request = APIRequestFactory().post(
        "/api/v1/auth/recovery/start",
        {"email": "recover-de@example.com"},
        format="json",
    )
    response = RecoveryStartView.as_view()(request)

    assert response.status_code == 200
    assert response.data["recovery_available"] is True
    assert len(mail.outbox) == 1
    assert mail.outbox[0].subject == "Dein Safernotes Code zum Zurücksetzen des Passworts"
    assert "Passwort zurückzusetzen" in mail.outbox[0].alternatives[0][0]


def test_recovery_key_status_and_rotation_only_update_wrapper(db, django_user_model):
    from django.utils import timezone

    from apps.authentication.models import KeyMaterial, RecoveryCode

    user = django_user_model.objects.create_user(
        email="rotate-recovery@example.com", password="password"
    )
    material = KeyMaterial.objects.create(
        user=user,
        kdf_params={"m": 65536, "t": 3, "p": 1},
        password_salt=b"salt",
        public_encryption_key=b"public-encryption-key",
        public_signing_key=b"public-signing-key",
        encrypted_master_key=encrypted_payload(),
        encrypted_private_encryption_key=encrypted_payload(),
        encrypted_private_signing_key=encrypted_payload(),
        recovery_wrapper=encrypted_payload(),
    )
    code = RecoveryCode.objects.create(
        user=user,
        code_hash=hash_token("123456"),
        expires_at=timezone.now() + timedelta(minutes=15),
    )

    status_request = APIRequestFactory().get("/api/v1/auth/recovery-key")
    force_authenticate(status_request, user=user)
    status_response = RecoveryKeyView.as_view()(status_request)

    assert status_response.status_code == 200
    assert status_response.data == {"configured": True, "key_version": 1}

    replacement = {**encrypted_payload(), "ciphertext": "rotated-wrapper"}
    update_request = APIRequestFactory().patch(
        "/api/v1/auth/recovery-key",
        {"recovery_wrapper": replacement},
        format="json",
    )
    force_authenticate(update_request, user=user)
    update_response = RecoveryKeyView.as_view()(update_request)

    assert update_response.status_code == 200
    assert "recovery_key" not in update_response.data
    material.refresh_from_db()
    assert material.recovery_wrapper["ciphertext"] == "rotated-wrapper"
    assert material.encrypted_master_key["ciphertext"] == "ciphertext"
    assert material.key_version == 2
    code.refresh_from_db()
    assert code.used_at is not None


def test_recovery_key_can_be_added_to_existing_account(db, django_user_model):
    from apps.authentication.models import KeyMaterial

    user = django_user_model.objects.create_user(
        email="add-recovery@example.com", password="password"
    )
    material = KeyMaterial.objects.create(
        user=user,
        kdf_params={"m": 65536, "t": 3, "p": 1},
        password_salt=b"salt",
        public_encryption_key=b"public-encryption-key",
        public_signing_key=b"public-signing-key",
        encrypted_master_key=encrypted_payload(),
        encrypted_private_encryption_key=encrypted_payload(),
        encrypted_private_signing_key=encrypted_payload(),
    )
    status_request = APIRequestFactory().get("/api/v1/auth/recovery-key")
    force_authenticate(status_request, user=user)

    status_response = RecoveryKeyView.as_view()(status_request)

    assert status_response.data["configured"] is False

    update_request = APIRequestFactory().patch(
        "/api/v1/auth/recovery-key",
        {"recovery_wrapper": encrypted_payload()},
        format="json",
    )
    force_authenticate(update_request, user=user)

    update_response = RecoveryKeyView.as_view()(update_request)

    assert update_response.status_code == 200
    assert update_response.data["configured"] is True
    material.refresh_from_db()
    assert material.recovery_wrapper["ciphertext"] == "ciphertext"


def test_recovery_key_update_rejects_plaintext_key(db, django_user_model):
    from apps.authentication.models import KeyMaterial

    user = django_user_model.objects.create_user(
        email="plaintext-recovery@example.com", password="password"
    )
    material = KeyMaterial.objects.create(
        user=user,
        kdf_params={"m": 65536, "t": 3, "p": 1},
        password_salt=b"salt",
        public_encryption_key=b"public-encryption-key",
        public_signing_key=b"public-signing-key",
        encrypted_master_key=encrypted_payload(),
        encrypted_private_encryption_key=encrypted_payload(),
        encrypted_private_signing_key=encrypted_payload(),
    )
    request = APIRequestFactory().patch(
        "/api/v1/auth/recovery-key",
        {
            "recovery_key": "must-never-reach-the-server",
            "recovery_wrapper": encrypted_payload(),
        },
        format="json",
    )
    force_authenticate(request, user=user)
    response = RecoveryKeyView.as_view()(request)

    assert response.status_code == 400
    material.refresh_from_db()
    assert material.recovery_wrapper is None


def test_password_change_rewraps_master_key(db, django_user_model):
    from apps.authentication.models import KeyMaterial

    user = django_user_model.objects.create_user(
        email="change@example.com", password="old-password"
    )
    KeyMaterial.objects.create(
        user=user,
        kdf_params={"m": 65536, "t": 3, "p": 1},
        password_salt=b"old-salt",
        public_encryption_key=b"public-encryption-key",
        public_signing_key=b"public-signing-key",
        encrypted_master_key=encrypted_payload(),
        encrypted_private_encryption_key=encrypted_payload(),
        encrypted_private_signing_key=encrypted_payload(),
    )
    request = APIRequestFactory().post(
        "/api/v1/auth/password/change",
        {
            "current_password": "old-password",
            "new_password": "new-strong-password",
            "kdf_algorithm": "pbkdf2-sha256",
            "kdf_params": {"iterations": 210000, "bits": 256},
            "password_salt": "new-salt",
            "encrypted_master_key": {**encrypted_payload(), "ciphertext": "changed-ciphertext"},
        },
        format="json",
    )
    force_authenticate(request, user=user)
    response = PasswordChangeView.as_view()(request)

    assert response.status_code == 200
    user.refresh_from_db()
    assert user.check_password("new-strong-password")
    user.key_material.refresh_from_db()
    assert user.key_material.encrypted_master_key["ciphertext"] == "changed-ciphertext"


def test_email_verification_confirm_marks_user_verified(db, django_user_model):
    from django.utils import timezone

    from apps.authentication.models import EmailVerificationCode

    user = django_user_model.objects.create_user(email="verify@example.com", password="password")
    EmailVerificationCode.objects.create(
        user=user,
        code_hash=hash_token("654321"),
        expires_at=timezone.now() + timedelta(minutes=30),
    )
    request = APIRequestFactory().post(
        "/api/v1/auth/email/verification/confirm",
        {"code": "654321"},
        format="json",
    )
    force_authenticate(request, user=user)
    response = EmailVerificationConfirmView.as_view()(request)

    assert response.status_code == 200
    assert response.data["email_verified"] is True
    user.refresh_from_db()
    assert user.email_verified_at is not None


def test_email_verification_status_reflects_confirmation_on_another_device(
    db, django_user_model
):
    from django.utils import timezone

    user = django_user_model.objects.create_user(
        email="status@example.com", password="password"
    )
    user.email_verified_at = timezone.now()
    user.save(update_fields=["email_verified_at", "updated_at"])
    request = APIRequestFactory().get("/api/v1/auth/email/verification/status")
    force_authenticate(request, user=user)

    response = EmailVerificationStatusView.as_view()(request)

    assert response.status_code == 200
    assert response.data == {
        "email": "status@example.com",
        "email_verified": True,
    }


@override_settings(EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend")
def test_email_verification_resend_sends_email_for_unverified_user(db, django_user_model):
    from apps.authentication.models import EmailVerificationCode

    user = django_user_model.objects.create_user(email="resend@example.com", password="password")
    request = APIRequestFactory().post(
        "/api/v1/auth/email/verification/resend",
        {},
        format="json",
    )
    force_authenticate(request, user=user)
    response = EmailVerificationResendView.as_view()(request)

    assert response.status_code == 200
    assert response.data["email_verified"] is False
    assert len(mail.outbox) == 1
    assert mail.outbox[0].to == ["resend@example.com"]
    assert EmailVerificationCode.objects.filter(user=user).exists()


def test_email_verification_confirm_rejects_bad_code(db, django_user_model):
    from django.utils import timezone

    from apps.authentication.models import EmailVerificationCode

    user = django_user_model.objects.create_user(email="bad-code@example.com", password="password")
    code = EmailVerificationCode.objects.create(
        user=user,
        code_hash=hash_token("654321"),
        expires_at=timezone.now() + timedelta(minutes=30),
    )
    request = APIRequestFactory().post(
        "/api/v1/auth/email/verification/confirm",
        {"code": "111111"},
        format="json",
    )
    force_authenticate(request, user=user)
    response = EmailVerificationConfirmView.as_view()(request)

    assert response.status_code == 400
    user.refresh_from_db()
    assert user.email_verified_at is None
    code.refresh_from_db()
    assert code.attempts == 1

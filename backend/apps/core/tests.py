from __future__ import annotations

from html.parser import HTMLParser

import pytest
from django.core import mail
from django.test import override_settings
from rest_framework.test import APIRequestFactory

from apps.core.abuse import increment_metadata_limit
from apps.core.checks import production_configuration_check
from apps.core.emails import _send, send_recovery_code_email, send_verification_code_email
from apps.core.security import redact_value
from apps.core.views import HealthLiveView, HealthReadyView


class _LinkParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.links = []

    def handle_starttag(self, tag, attrs):
        if tag == "a":
            href = dict(attrs).get("href")
            if href:
                self.links.append(href)


def _html_links(message):
    parser = _LinkParser()
    parser.feed(message.alternatives[0][0])
    return parser.links


def test_redact_value_removes_tokens_and_ciphertext():
    redacted = redact_value(
        {
            "access_token": "token",
            "nested": {"ciphertext": "secret", "safe": "ok"},
        }
    )

    assert redacted["access_token"] == "[REDACTED]"
    assert redacted["nested"]["ciphertext"] == "[REDACTED]"
    assert redacted["nested"]["safe"] == "ok"


@override_settings(CACHES={"default": {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}})
def test_metadata_limit_blocks_after_limit():
    allowed = True
    for _ in range(121):
        allowed, count = increment_metadata_limit("sync_batch", "user-1")

    assert not allowed
    assert count == 121


def test_health_live_is_public():
    request = APIRequestFactory().get("/api/v1/health/live")
    response = HealthLiveView.as_view()(request)

    assert response.status_code == 200
    assert response.data == {"status": "ok"}


def test_health_live_renders_json_for_browser_accept_header():
    request = APIRequestFactory().get(
        "/api/v1/health/live",
        HTTP_ACCEPT="text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    )
    response = HealthLiveView.as_view()(request)
    response.render()

    assert response.status_code == 200
    assert response["Content-Type"] == "application/json"
    assert response.content == b'{"status":"ok"}'


def test_health_ready_checks_database(db):
    request = APIRequestFactory().get("/api/v1/health/ready")
    response = HealthReadyView.as_view()(request)

    assert response.status_code == 200
    assert response.data == {"status": "ready"}


def test_send_email_does_not_silence_delivery_errors(monkeypatch):
    calls = []

    def fake_send(self, *, fail_silently):
        calls.append(fail_silently)

    monkeypatch.setattr("django.core.mail.message.EmailMessage.send", fake_send)

    _send(
        to="user@example.test",
        subject="Test",
        text_body="Text",
        html_body="<p>Text</p>",
    )

    assert calls == [False]


@pytest.mark.parametrize(
    ("locale", "sender", "expected_subject", "expected_label"),
    [
        (
            "en",
            send_verification_code_email,
            "Your Safernotes verification code",
            "Verification code",
        ),
        (
            "de",
            send_verification_code_email,
            "Dein Safernotes Bestätigungscode",
            "Bestätigungscode",
        ),
        (
            "en",
            send_recovery_code_email,
            "Your Safernotes password reset code",
            "Recovery code",
        ),
        (
            "de",
            send_recovery_code_email,
            "Dein Safernotes Code zum Zurücksetzen des Passworts",
            "Wiederherstellungscode",
        ),
    ],
)
@override_settings(
    EMAIL_BACKEND="django.core.mail.backends.locmem.EmailBackend",
    APP_BASE_URL="https://app.safernotes.com/",
    WEBSITE_BASE_URL="https://safernotes.com/",
)
def test_code_emails_have_production_safe_links_in_every_locale(
    db,
    django_user_model,
    locale,
    sender,
    expected_subject,
    expected_label,
):
    from apps.users.models import Profile

    user = django_user_model.objects.create_user(
        email=f"{locale}-{expected_label.split()[0]}@example.com",
        password="strong-password",
    )
    Profile.objects.create(user=user, locale=locale)

    sender(user, "123456")

    message = mail.outbox[0]
    assert message.subject == expected_subject
    assert f"{expected_label}: 123456" in message.body
    assert "https://app.safernotes.com" in message.body
    assert "https://safernotes.com" in message.body
    assert set(_html_links(message)) == {
        "https://app.safernotes.com",
        "https://safernotes.com",
    }
    assert "localhost" not in message.body
    assert "localhost" not in message.alternatives[0][0]


@override_settings(
    SECRET_KEY="unsafe-dev-secret-change-me",
    DATABASES={"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": ":memory:"}},
    EMAIL_BACKEND="django.core.mail.backends.console.EmailBackend",
    BILLING_PROVIDER="creem",
    BILLING_API_KEY="",
    BILLING_API_BASE_URL="https://test-api.creem.io/v1",
    BILLING_WEBHOOK_SECRET="",
    BILLING_PRODUCT_IDS={},
    CORS_ALLOWED_ORIGINS=["http://localhost:3000"],
)
def test_production_configuration_check_flags_unsafe_launch_settings():
    issue_ids = {issue.id for issue in production_configuration_check(None)}

    assert "safernotes.E001" in issue_ids
    assert "safernotes.E002" in issue_ids
    assert "safernotes.E003" in issue_ids
    assert "safernotes.E004" in issue_ids
    assert "safernotes.E006" in issue_ids
    assert "safernotes.W001" in issue_ids


@override_settings(
    SECRET_KEY="production-secret",
    DATABASES={"default": {"ENGINE": "django.db.backends.postgresql", "NAME": "safernotes"}},
    EMAIL_BACKEND="django.core.mail.backends.smtp.EmailBackend",
    EMAIL_HOST="",
    EMAIL_PORT=587,
    EMAIL_HOST_USER="",
    EMAIL_HOST_PASSWORD="",
    EMAIL_USE_TLS=False,
    EMAIL_USE_SSL=False,
    BILLING_PROVIDER="manual",
    CORS_ALLOWED_ORIGINS=["https://app.example.com"],
)
def test_production_configuration_check_flags_incomplete_smtp_settings():
    issue_ids = {issue.id for issue in production_configuration_check(None)}

    assert "safernotes.E005" in issue_ids


@override_settings(
    SECRET_KEY="production-secret",
    DATABASES={"default": {"ENGINE": "django.db.backends.postgresql", "NAME": "safernotes"}},
    EMAIL_BACKEND="django.core.mail.backends.smtp.EmailBackend",
    EMAIL_HOST="smtp.example.com",
    EMAIL_PORT=587,
    EMAIL_HOST_USER="noreply@example.com",
    EMAIL_HOST_PASSWORD="smtp-secret",
    EMAIL_USE_TLS=True,
    EMAIL_USE_SSL=False,
    BILLING_PROVIDER="creem",
    BILLING_API_KEY="creem_live_test",
    BILLING_API_BASE_URL="https://api.creem.io/v1",
    BILLING_WEBHOOK_SECRET="webhook-secret",
    BILLING_PRODUCT_IDS={"essential": "prod_essential", "pro": "prod_pro"},
    CORS_ALLOWED_ORIGINS=["https://app.example.com"],
)
def test_production_configuration_check_accepts_safe_launch_settings():
    assert production_configuration_check(None) == []


@override_settings(
    SECRET_KEY="production-secret",
    DATABASES={"default": {"ENGINE": "django.db.backends.postgresql", "NAME": "safernotes"}},
    EMAIL_BACKEND="django.core.mail.backends.smtp.EmailBackend",
    EMAIL_HOST="smtp.example.com",
    EMAIL_PORT=587,
    EMAIL_HOST_USER="noreply@example.com",
    EMAIL_HOST_PASSWORD="smtp-secret",
    EMAIL_USE_TLS=True,
    EMAIL_USE_SSL=False,
    BILLING_PROVIDER="creem",
    BILLING_API_KEY="creem_test_key",
    BILLING_API_BASE_URL="https://api.creem.io/v1",
    BILLING_WEBHOOK_SECRET="webhook-secret",
    BILLING_PRODUCT_IDS={"essential": "prod_essential", "pro": "prod_pro"},
    CORS_ALLOWED_ORIGINS=["https://app.example.com"],
)
def test_production_configuration_check_rejects_test_key_with_live_api():
    issue_ids = {issue.id for issue in production_configuration_check(None)}

    assert "safernotes.E007" in issue_ids


@override_settings(
    SECRET_KEY="production-secret",
    DATABASES={"default": {"ENGINE": "django.db.backends.postgresql", "NAME": "safernotes"}},
    EMAIL_BACKEND="django.core.mail.backends.smtp.EmailBackend",
    EMAIL_HOST="smtp.example.com",
    EMAIL_PORT=587,
    EMAIL_HOST_USER="noreply@example.com",
    EMAIL_HOST_PASSWORD="smtp-secret",
    EMAIL_USE_TLS=True,
    EMAIL_USE_SSL=False,
    BILLING_PROVIDER="creem",
    BILLING_API_KEY="creem_live_key",
    BILLING_API_BASE_URL="https://test-api.creem.io/v1",
    BILLING_WEBHOOK_SECRET="webhook-secret",
    BILLING_PRODUCT_IDS={"essential": "prod_essential", "pro": "prod_pro"},
    CORS_ALLOWED_ORIGINS=["https://app.example.com"],
)
def test_production_configuration_check_rejects_live_key_with_test_api():
    issue_ids = {issue.id for issue in production_configuration_check(None)}

    assert "safernotes.E007" in issue_ids

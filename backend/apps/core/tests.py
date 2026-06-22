from __future__ import annotations

from django.test import override_settings
from rest_framework.test import APIRequestFactory

from apps.core.abuse import increment_metadata_limit
from apps.core.checks import production_configuration_check
from apps.core.security import redact_value
from apps.core.views import HealthLiveView, HealthReadyView


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


def test_health_ready_checks_database(db):
    request = APIRequestFactory().get("/api/v1/health/ready")
    response = HealthReadyView.as_view()(request)

    assert response.status_code == 200
    assert response.data == {"status": "ready"}


@override_settings(
    SECRET_KEY="unsafe-dev-secret-change-me",
    DATABASES={"default": {"ENGINE": "django.db.backends.sqlite3", "NAME": ":memory:"}},
    EMAIL_BACKEND="django.core.mail.backends.console.EmailBackend",
    BILLING_PROVIDER="paddle",
    BILLING_API_KEY="",
    BILLING_WEBHOOK_SECRET="",
    BILLING_PRICE_IDS={},
    CORS_ALLOWED_ORIGINS=["http://localhost:3000"],
)
def test_production_configuration_check_flags_unsafe_launch_settings():
    issue_ids = {issue.id for issue in production_configuration_check(None)}

    assert "zknotes.E001" in issue_ids
    assert "zknotes.E002" in issue_ids
    assert "zknotes.E003" in issue_ids
    assert "zknotes.E004" in issue_ids
    assert "zknotes.W001" in issue_ids


@override_settings(
    SECRET_KEY="production-secret",
    DATABASES={"default": {"ENGINE": "django.db.backends.postgresql", "NAME": "zknotes"}},
    EMAIL_BACKEND="django.core.mail.backends.smtp.EmailBackend",
    BILLING_PROVIDER="paddle",
    BILLING_API_KEY="pdl_sdbx_apikey_test",
    BILLING_WEBHOOK_SECRET="webhook-secret",
    BILLING_PRICE_IDS={"essential": "pri_essential", "pro": "pri_pro"},
    CORS_ALLOWED_ORIGINS=["https://app.example.com"],
)
def test_production_configuration_check_accepts_safe_launch_settings():
    assert production_configuration_check(None) == []

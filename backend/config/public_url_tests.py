from __future__ import annotations

import importlib
import logging

import pytest

from config.logging import RedactTransferToken
from config.public_url import public_origin


@pytest.mark.parametrize(
    "url",
    [
        "https://notes.example.com",
        "https://notes.example.com:8443",
        "http://localhost:8080",
        "http://127.0.0.1:8080",
        "http://[::1]:8080",
    ],
)
def test_public_origin(url):
    assert public_origin(url + "/") == url


@pytest.mark.parametrize(
    "url",
    [
        "",
        "notes.example.com",
        "ftp://host",
        "http://public.example",
        "https://user:pwd@host",
        "https://host/app",
        "https://host?query",
        "https://host#anchor",
        "https://host:0",
        "https://host:invalid",
        "https://host/$VAR",
    ],
)
def test_invalid_public_origin(url):
    with pytest.raises(ValueError):
        public_origin(url)


def test_single_origin_derives_all_selfhost_settings(monkeypatch):
    monkeypatch.setenv("PUBLIC_URL", "https://notes.example.com:8443/")
    from config.settings import selfhost

    selfhost = importlib.reload(selfhost)
    assert "notes.example.com" in selfhost.ALLOWED_HOSTS
    assert selfhost.CORS_ALLOWED_ORIGINS == ["https://notes.example.com:8443"]
    assert selfhost.CSRF_TRUSTED_ORIGINS == selfhost.CORS_ALLOWED_ORIGINS
    assert selfhost.APP_BASE_URL == selfhost.WEBSITE_BASE_URL == "https://notes.example.com:8443"
    assert selfhost.SESSION_COOKIE_SECURE and selfhost.CSRF_COOKIE_SECURE
    assert selfhost.ATTACHMENT_PROXY_ENABLED


def test_access_log_hides_signed_transfer_token():
    record = logging.LogRecord(
        "uvicorn.access",
        logging.INFO,
        "",
        1,
        '%s "%s %s HTTP/1.1" %s',
        ("client", "GET", "/api/v1/attachments/id/content/?token=secret-link", 200),
        None,
    )
    assert RedactTransferToken().filter(record)
    assert "secret-link" not in record.getMessage()
    assert "[redacted]" in record.getMessage()

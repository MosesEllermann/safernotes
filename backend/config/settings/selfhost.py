"""Safe defaults for the Docker-based community deployment."""

from __future__ import annotations

import os
from copy import deepcopy
from urllib.parse import urlsplit

from django.core.exceptions import ImproperlyConfigured

from config.public_url import public_origin
from config.settings import base as base_settings
from config.settings.base import *  # noqa: F403

DEBUG = False

try:
    PUBLIC_URL = public_origin(os.environ.get("PUBLIC_URL", "http://localhost:8080"))
except ValueError as error:
    raise ImproperlyConfigured(str(error)) from error

public_hostname = urlsplit(PUBLIC_URL).hostname
if ":" in public_hostname:
    public_hostname = f"[{public_hostname}]"
ALLOWED_HOSTS = [public_hostname, "localhost", "127.0.0.1", "api"]
CORS_ALLOWED_ORIGINS = [PUBLIC_URL]
CSRF_TRUSTED_ORIGINS = [PUBLIC_URL]
APP_BASE_URL = PUBLIC_URL
WEBSITE_BASE_URL = PUBLIC_URL
SESSION_COOKIE_SECURE = PUBLIC_URL.startswith("https://")
CSRF_COOKIE_SECURE = SESSION_COOKIE_SECURE

LOGGING = deepcopy(base_settings.LOGGING)
LOGGING["filters"] = {"transfer_token": {"()": "config.logging.RedactTransferToken"}}
LOGGING["handlers"]["access"] = {
    "class": "logging.StreamHandler",
    "filters": ["transfer_token"],
}
for logger_name in ("gunicorn.access", "uvicorn.access", "django.server"):
    LOGGING["loggers"][logger_name] = {
        "handlers": ["access"],
        "level": "INFO",
        "propagate": False,
    }

MIDDLEWARE = [
    base_settings.MIDDLEWARE[0],
    "whitenoise.middleware.WhiteNoiseMiddleware",
    *base_settings.MIDDLEWARE[1:],
]

STORAGES = {
    "default": {
        "BACKEND": "django.core.files.storage.FileSystemStorage",
    },
    "staticfiles": {
        "BACKEND": "whitenoise.storage.CompressedManifestStaticFilesStorage",
    },
}

# TLS is normally terminated by an operator-provided reverse proxy. The
# all-in-one local deployment remains usable over plain HTTP on localhost.
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
USE_X_FORWARDED_HOST = True

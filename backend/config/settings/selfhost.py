"""Safe defaults for the Docker-based community deployment."""

from __future__ import annotations

from config.settings import base as base_settings
from config.settings.base import *  # noqa: F403

DEBUG = False

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

"""Shared Django settings for the zero-knowledge notes backend."""

from __future__ import annotations

import json
from pathlib import Path

import environ

BASE_DIR = Path(__file__).resolve().parents[2]
ROOT_DIR = BASE_DIR.parent

env = environ.Env(
    DEBUG=(bool, False),
    SECRET_KEY=(str, "unsafe-dev-secret-change-me"),
    ALLOWED_HOSTS=(list, ["localhost", "127.0.0.1"]),
    DATABASE_URL=(str, f"sqlite:///{BASE_DIR / 'db.sqlite3'}"),
    REDIS_URL=(str, "redis://localhost:6379/0"),
    CORS_ALLOWED_ORIGINS=(list, ["http://localhost:3000", "http://localhost:5173"]),
    ATTACHMENT_BUCKET=(str, ""),
    ATTACHMENT_ENDPOINT_URL=(str, ""),
    ATTACHMENT_REGION=(str, "auto"),
    ATTACHMENT_UPLOAD_URL_TTL_SECONDS=(int, 900),
    ATTACHMENT_DOWNLOAD_URL_TTL_SECONDS=(int, 900),
    BILLING_PROVIDER=(str, "manual"),
    BILLING_API_KEY=(str, ""),
    BILLING_API_BASE_URL=(str, "https://sandbox-api.paddle.com"),
    BILLING_PRICE_IDS=(str, "{}"),
    BILLING_STORE_ID=(str, ""),
    BILLING_VARIANT_IDS=(str, "{}"),
    BILLING_CHECKOUT_URLS=(str, "{}"),
    BILLING_PORTAL_URL=(str, ""),
    BILLING_SUCCESS_URL=(str, ""),
    BILLING_WEBHOOK_SECRET=(str, ""),
    EMAIL_BACKEND=(str, "django.core.mail.backends.console.EmailBackend"),
    EMAIL_HOST=(str, ""),
    EMAIL_PORT=(int, 25),
    EMAIL_HOST_USER=(str, ""),
    EMAIL_HOST_PASSWORD=(str, ""),
    EMAIL_USE_TLS=(bool, False),
    EMAIL_USE_SSL=(bool, False),
    DEFAULT_FROM_EMAIL=(str, "Safernotes <noreply@localhost>"),
    APP_BASE_URL=(str, "http://localhost:3000"),
)

if (ROOT_DIR / ".env").exists():
    environ.Env.read_env(ROOT_DIR / ".env")

SECRET_KEY = env("SECRET_KEY")
DEBUG = env("DEBUG")
ALLOWED_HOSTS = env("ALLOWED_HOSTS")
EMAIL_BACKEND = env("EMAIL_BACKEND")
EMAIL_HOST = env("EMAIL_HOST")
EMAIL_PORT = env("EMAIL_PORT")
EMAIL_HOST_USER = env("EMAIL_HOST_USER")
EMAIL_HOST_PASSWORD = env("EMAIL_HOST_PASSWORD")
EMAIL_USE_TLS = env("EMAIL_USE_TLS")
EMAIL_USE_SSL = env("EMAIL_USE_SSL")
DEFAULT_FROM_EMAIL = env("DEFAULT_FROM_EMAIL")
APP_BASE_URL = env("APP_BASE_URL")

INSTALLED_APPS = [
    "django.contrib.auth",
    "django.contrib.contenttypes",
    "django.contrib.sessions",
    "django.contrib.messages",
    "django.contrib.staticfiles",
    "corsheaders",
    "rest_framework",
    "channels",
    "apps.core",
    "apps.users",
    "apps.authentication",
    "apps.devices",
    "apps.tenants",
    "apps.notes",
    "apps.attachments",
    "apps.collaboration",
    "apps.subscriptions",
    "apps.billing",
    "apps.audit",
    "apps.notifications",
    "apps.search",
]

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "apps.core.middleware.SecurityHeadersMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
]

ROOT_URLCONF = "config.urls"
ASGI_APPLICATION = "config.asgi.application"
WSGI_APPLICATION = "config.wsgi.application"

DATABASES = {"default": env.db("DATABASE_URL")}

AUTH_USER_MODEL = "users.User"

DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"
LANGUAGE_CODE = "en-us"
TIME_ZONE = "UTC"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"

REST_FRAMEWORK = {
    "DEFAULT_RENDERER_CLASSES": [
        "rest_framework.renderers.JSONRenderer",
    ],
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "apps.authentication.authentication.BearerTokenAuthentication",
        "rest_framework.authentication.SessionAuthentication",
    ],
    "DEFAULT_PERMISSION_CLASSES": [
        "rest_framework.permissions.IsAuthenticated",
    ],
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.ScopedRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "login": "10/minute",
        "register": "5/hour",
        "refresh": "30/minute",
        "recovery": "5/hour",
        "email_verification": "5/hour",
    },
    "DEFAULT_PAGINATION_CLASS": "apps.core.pagination.CreatedAtCursorPagination",
    "PAGE_SIZE": 100,
}

CHANNEL_LAYERS = {
    "default": {
        "BACKEND": "channels_redis.core.RedisChannelLayer",
        "CONFIG": {"hosts": [env("REDIS_URL")]},
    }
}

CORS_ALLOWED_ORIGINS = env("CORS_ALLOWED_ORIGINS")
CSRF_TRUSTED_ORIGINS = CORS_ALLOWED_ORIGINS

SESSION_COOKIE_HTTPONLY = True
SESSION_COOKIE_SAMESITE = "Lax"
CSRF_COOKIE_SAMESITE = "Lax"
X_FRAME_OPTIONS = "DENY"
SECURE_REFERRER_POLICY = "strict-origin-when-cross-origin"

CONTENT_SECURITY_POLICY = {
    "default-src": ("'self'",),
    "object-src": ("'none'",),
    "base-uri": ("'self'",),
    "frame-ancestors": ("'none'",),
}

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "json": {
            "format": "%(asctime)s %(levelname)s %(name)s %(message)s %(metadata)s",
        }
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "json",
        }
    },
    "loggers": {
        "safernotes.security": {
            "handlers": ["console"],
            "level": "INFO",
            "propagate": False,
        }
    },
}

ATTACHMENT_STORAGE = {
    "bucket": env("ATTACHMENT_BUCKET"),
    "endpoint_url": env("ATTACHMENT_ENDPOINT_URL"),
    "region_name": env("ATTACHMENT_REGION"),
    "upload_url_ttl_seconds": env("ATTACHMENT_UPLOAD_URL_TTL_SECONDS"),
    "download_url_ttl_seconds": env("ATTACHMENT_DOWNLOAD_URL_TTL_SECONDS"),
}

BILLING_PROVIDER = env("BILLING_PROVIDER")
BILLING_API_KEY = env("BILLING_API_KEY")
BILLING_API_BASE_URL = env("BILLING_API_BASE_URL")
BILLING_PRICE_IDS = json.loads(env("BILLING_PRICE_IDS") or "{}")
BILLING_STORE_ID = env("BILLING_STORE_ID")
BILLING_VARIANT_IDS = json.loads(env("BILLING_VARIANT_IDS") or "{}")
BILLING_CHECKOUT_URLS = json.loads(env("BILLING_CHECKOUT_URLS") or "{}")
BILLING_PORTAL_URL = env("BILLING_PORTAL_URL")
BILLING_SUCCESS_URL = env("BILLING_SUCCESS_URL")
BILLING_WEBHOOK_SECRET = env("BILLING_WEBHOOK_SECRET")

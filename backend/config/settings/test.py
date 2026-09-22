"""Test settings."""

from __future__ import annotations

from django.core.management.utils import get_random_secret_key

from config.settings.base import *  # noqa: F403

SECRET_KEY = get_random_secret_key()
PASSWORD_HASHERS = ["django.contrib.auth.hashers.MD5PasswordHasher"]
CHANNEL_LAYERS = {"default": {"BACKEND": "channels.layers.InMemoryChannelLayer"}}

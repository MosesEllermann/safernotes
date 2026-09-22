"""Local development settings."""

from __future__ import annotations

from django.core.management.utils import get_random_secret_key

from config.settings import base as base_settings
from config.settings.base import *  # noqa: F403

DEBUG = True
SECRET_KEY = base_settings.SECRET_KEY or get_random_secret_key()

from __future__ import annotations

SUPPORTED_LOCALES = {"de", "en"}


def normalize_locale(locale: str | None) -> str:
    if not locale:
        return "en"
    language = locale.split("-", 1)[0].split("_", 1)[0].lower()
    return language if language in SUPPORTED_LOCALES else "en"

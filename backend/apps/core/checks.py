from __future__ import annotations

from django.conf import settings
from django.core.checks import Error, Warning, register


@register(deploy=True)
def production_configuration_check(app_configs, **kwargs):
    issues = []

    if settings.SECRET_KEY == "unsafe-dev-secret-change-me":  # nosec B105
        issues.append(
            Error(
                "Production SECRET_KEY must not use the development default.",
                id="safernotes.E001",
            )
        )

    database_engine = settings.DATABASES["default"]["ENGINE"]
    if database_engine.endswith("sqlite3"):
        issues.append(
            Error(
                "Production must use Postgres, not SQLite.",
                id="safernotes.E002",
            )
        )

    if settings.EMAIL_BACKEND.endswith("console.EmailBackend"):
        issues.append(
            Error(
                "Production must use a real transactional email backend.",
                id="safernotes.E003",
            )
        )

    if settings.BILLING_PROVIDER == "paddle":
        missing = []
        if not settings.BILLING_API_KEY:
            missing.append("BILLING_API_KEY")
        if not settings.BILLING_WEBHOOK_SECRET:
            missing.append("BILLING_WEBHOOK_SECRET")
        for plan in ("essential", "pro"):
            if plan not in settings.BILLING_PRICE_IDS:
                missing.append(f"BILLING_PRICE_IDS.{plan}")
        if missing:
            issues.append(
                Error(
                    "Paddle billing is enabled but required settings are missing: "
                    + ", ".join(missing),
                    id="safernotes.E004",
                )
            )

    if any(origin.startswith("http://localhost") for origin in settings.CORS_ALLOWED_ORIGINS):
        issues.append(
            Warning(
                "Production CORS_ALLOWED_ORIGINS should not include localhost origins.",
                id="safernotes.W001",
            )
        )

    return issues

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

    if settings.EMAIL_BACKEND.endswith("smtp.EmailBackend"):
        missing_email_settings = []
        for setting_name in (
            "EMAIL_HOST",
            "EMAIL_PORT",
            "EMAIL_HOST_USER",
            "EMAIL_HOST_PASSWORD",
        ):
            if not getattr(settings, setting_name, None):
                missing_email_settings.append(setting_name)
        if not settings.EMAIL_USE_TLS and not settings.EMAIL_USE_SSL:
            missing_email_settings.append("EMAIL_USE_TLS or EMAIL_USE_SSL")
        if missing_email_settings:
            issues.append(
                Error(
                    "SMTP email backend is enabled but required settings are missing: "
                    + ", ".join(missing_email_settings),
                    id="safernotes.E005",
                )
            )

    if settings.BILLING_PROVIDER == "creem":
        missing = []
        if not settings.BILLING_API_KEY:
            missing.append("BILLING_API_KEY")
        if not settings.BILLING_WEBHOOK_SECRET:
            missing.append("BILLING_WEBHOOK_SECRET")
        for plan in ("essential", "pro"):
            if plan not in settings.BILLING_PRODUCT_IDS:
                missing.append(f"BILLING_PRODUCT_IDS.{plan}")
        if missing:
            issues.append(
                Error(
                    "Creem billing is enabled but required settings are missing: "
                    + ", ".join(missing),
                    id="safernotes.E004",
                )
            )
        if settings.BILLING_API_BASE_URL != "https://api.creem.io/v1":
            issues.append(
                Error(
                    "Production Creem billing must use https://api.creem.io/v1.",
                    id="safernotes.E006",
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

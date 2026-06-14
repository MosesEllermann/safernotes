from __future__ import annotations

from django.test import override_settings

from apps.core.abuse import increment_metadata_limit
from apps.core.security import redact_value


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


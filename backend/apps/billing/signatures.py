from __future__ import annotations

import hmac
from hashlib import sha256

from django.conf import settings


def expected_signature(raw_body: bytes) -> str:
    secret = settings.BILLING_WEBHOOK_SECRET
    if not secret:
        return ""
    return hmac.new(secret.encode("utf-8"), raw_body, sha256).hexdigest()


def verify_webhook_signature(raw_body: bytes, signature: str | None) -> bool:
    expected = expected_signature(raw_body)
    if not expected:
        return False
    return hmac.compare_digest(expected, signature or "")


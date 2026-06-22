from __future__ import annotations

import hmac
from hashlib import sha256

from django.conf import settings


def expected_signature(raw_body: bytes) -> str:
    secret = settings.BILLING_WEBHOOK_SECRET
    if not secret:
        return ""
    return hmac.new(secret.encode("utf-8"), raw_body, sha256).hexdigest()


def expected_paddle_signature(raw_body: bytes, timestamp: str) -> str:
    secret = settings.BILLING_WEBHOOK_SECRET
    if not secret or not timestamp:
        return ""
    signed_payload = timestamp.encode("utf-8") + b":" + raw_body
    return hmac.new(secret.encode("utf-8"), signed_payload, sha256).hexdigest()


def verify_paddle_signature(raw_body: bytes, signature: str | None) -> bool:
    if not signature:
        return False
    parts = {}
    for part in signature.split(";"):
        key, separator, value = part.partition("=")
        if separator:
            parts[key] = value
    expected = expected_paddle_signature(raw_body, parts.get("ts", ""))
    if not expected:
        return False
    return hmac.compare_digest(expected, parts.get("h1", ""))


def verify_webhook_signature(raw_body: bytes, signature: str | None) -> bool:
    if signature and "ts=" in signature and "h1=" in signature:
        return verify_paddle_signature(raw_body, signature)
    expected = expected_signature(raw_body)
    if not expected:
        return False
    return hmac.compare_digest(expected, signature or "")

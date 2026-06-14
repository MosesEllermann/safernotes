from __future__ import annotations

import logging

SENSITIVE_KEYS = {
    "access_token",
    "refresh_token",
    "password",
    "encrypted_payload",
    "encrypted_note_key",
    "encrypted_delta",
    "encrypted_metadata",
    "encrypted_master_key",
    "encrypted_private_encryption_key",
    "encrypted_private_signing_key",
    "recovery_wrapper",
    "ciphertext",
}


def redact_value(value):
    if isinstance(value, dict):
        return {key: ("[REDACTED]" if key in SENSITIVE_KEYS else redact_value(item)) for key, item in value.items()}
    if isinstance(value, list):
        return [redact_value(item) for item in value]
    return value


class RedactingLogger:
    def __init__(self, logger_name: str):
        self.logger = logging.getLogger(logger_name)

    def info(self, message: str, **metadata):
        self.logger.info(message, extra={"metadata": redact_value(metadata)})

    def warning(self, message: str, **metadata):
        self.logger.warning(message, extra={"metadata": redact_value(metadata)})


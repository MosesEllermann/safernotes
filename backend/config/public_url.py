"""Validate the single public origin used by self-hosted installations."""

from urllib.parse import urlsplit


def public_origin(value: str) -> str:
    value = value.strip().rstrip("/")
    try:
        parts = urlsplit(value)
        port = parts.port
    except ValueError as error:
        raise ValueError("PUBLIC_URL must be a valid HTTP(S) origin.") from error
    if (
        parts.scheme not in {"http", "https"}
        or not parts.hostname
        or parts.username is not None
        or parts.password is not None
        or parts.path
        or parts.query
        or parts.fragment
        or any(character.isspace() for character in value)
        or any(character in value for character in "\\$#\"'")
        or port == 0
    ):
        raise ValueError("PUBLIC_URL must be an HTTP(S) origin without credentials, path or query.")
    if parts.scheme == "http" and parts.hostname not in {"localhost", "127.0.0.1", "::1"}:
        raise ValueError("Use HTTPS for a server accessed from another device.")
    return value

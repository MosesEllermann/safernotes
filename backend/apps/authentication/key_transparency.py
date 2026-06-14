from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class KeyTransparencyLeaf:
    user_id: str
    key_version: int
    public_encryption_key_fingerprint: str
    public_signing_key_fingerprint: str


def build_key_transparency_leaf(key_material) -> KeyTransparencyLeaf:
    """Build the future append-only transparency log leaf without exposing private keys."""

    return KeyTransparencyLeaf(
        user_id=str(key_material.user_id),
        key_version=key_material.key_version,
        public_encryption_key_fingerprint=key_material.public_encryption_key_fingerprint,
        public_signing_key_fingerprint=key_material.public_signing_key_fingerprint,
    )

from __future__ import annotations

from rest_framework import serializers

FORBIDDEN_PLAINTEXT_FIELDS = {
    "title",
    "content",
    "body",
    "text",
    "checklist",
    "label_name",
    "filename",
    "note_title",
    "note_content",
}


class EncryptedEnvelopeField(serializers.JSONField):
    """Validates the versioned encrypted envelope used by client-side crypto."""

    required_keys = {"version", "algorithm", "nonce", "ciphertext"}

    def to_internal_value(self, data):
        value = super().to_internal_value(data)
        if not isinstance(value, dict):
            raise serializers.ValidationError("Encrypted payload must be a JSON object.")
        missing = self.required_keys - set(value)
        if missing:
            raise serializers.ValidationError(f"Encrypted payload missing keys: {sorted(missing)}")
        if not isinstance(value.get("ciphertext"), str) or not value["ciphertext"]:
            raise serializers.ValidationError("Encrypted payload ciphertext is required.")
        return value


class BinaryTextField(serializers.Field):
    """Serializes byte fields as text-encoded values without exposing raw binary rendering quirks."""

    def to_representation(self, value):
        if value is None:
            return None
        return bytes(value).decode("utf-8")

    def to_internal_value(self, data):
        if not isinstance(data, str):
            raise serializers.ValidationError("Expected text-encoded binary data.")
        return data.encode("utf-8")


class RejectPlaintextMixin:
    """Rejects fields that would indicate accidental plaintext note ingestion."""

    def reject_plaintext_fields(self, data):
        incoming = set(data or {})
        forbidden = incoming & FORBIDDEN_PLAINTEXT_FIELDS
        if forbidden:
            raise serializers.ValidationError(
                {
                    "encrypted_payload": (
                        "Plaintext note data is forbidden. Encrypt locally and submit only "
                        f"versioned encrypted envelopes. Rejected fields: {sorted(forbidden)}"
                    )
                }
            )

    def to_internal_value(self, data):
        self.reject_plaintext_fields(data)
        return super().to_internal_value(data)

    def validate(self, attrs):
        return super().validate(attrs)

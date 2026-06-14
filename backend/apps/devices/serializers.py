from __future__ import annotations

from rest_framework import serializers

from apps.core.serializers import BinaryTextField, EncryptedEnvelopeField, RejectPlaintextMixin
from apps.devices.models import Device


class DeviceSerializer(RejectPlaintextMixin, serializers.ModelSerializer):
    name_ciphertext = EncryptedEnvelopeField()
    public_signing_key = BinaryTextField()

    class Meta:
        model = Device
        fields = [
            "id",
            "name_ciphertext",
            "public_signing_key",
            "last_seen_at",
            "revoked_at",
            "trusted_at",
            "created_at",
        ]
        read_only_fields = ["id", "last_seen_at", "revoked_at", "trusted_at", "created_at"]

    def create(self, validated_data):
        validated_data["user"] = self.context["request"].user
        return super().create(validated_data)

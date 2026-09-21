from __future__ import annotations

from rest_framework import serializers

from apps.core.serializers import EncryptedEnvelopeField, RejectPlaintextMixin
from apps.tenants.models import Membership, Organization


class OrganizationSerializer(RejectPlaintextMixin, serializers.ModelSerializer):
    name_ciphertext = EncryptedEnvelopeField()

    class Meta:
        model = Organization
        fields = ["id", "name_ciphertext", "owner_user", "created_at", "updated_at"]
        read_only_fields = ["id", "owner_user", "created_at", "updated_at"]

    def create(self, validated_data):
        validated_data["owner_user"] = self.context["request"].user
        return super().create(validated_data)


class MembershipSerializer(serializers.ModelSerializer):
    class Meta:
        model = Membership
        fields = ["id", "tenant", "user", "role", "status", "created_at", "updated_at"]
        read_only_fields = ["id", "created_at", "updated_at"]

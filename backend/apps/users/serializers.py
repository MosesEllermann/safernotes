from __future__ import annotations

from rest_framework import serializers

from apps.authentication.key_transparency import build_key_transparency_leaf
from apps.authentication.serializers import KeyMaterialSerializer
from apps.users.models import User


class UserSerializer(serializers.ModelSerializer):
    key_material = KeyMaterialSerializer(read_only=True)

    class Meta:
        model = User
        fields = ["id", "email", "status", "default_tenant", "key_material"]
        read_only_fields = ["id", "email", "status", "default_tenant", "key_material"]


class PublicKeysSerializer(serializers.ModelSerializer):
    public_encryption_key = serializers.SerializerMethodField()
    public_signing_key = serializers.SerializerMethodField()
    key_version = serializers.IntegerField(source="key_material.key_version")
    public_encryption_key_fingerprint = serializers.CharField(
        source="key_material.public_encryption_key_fingerprint"
    )
    public_signing_key_fingerprint = serializers.CharField(source="key_material.public_signing_key_fingerprint")
    key_transparency_leaf = serializers.SerializerMethodField()

    class Meta:
        model = User
        fields = [
            "id",
            "public_encryption_key",
            "public_signing_key",
            "public_encryption_key_fingerprint",
            "public_signing_key_fingerprint",
            "key_version",
            "key_transparency_leaf",
        ]

    def get_public_encryption_key(self, obj):
        return bytes(obj.key_material.public_encryption_key).decode("utf-8")

    def get_public_signing_key(self, obj):
        return bytes(obj.key_material.public_signing_key).decode("utf-8")

    def get_key_transparency_leaf(self, obj):
        return build_key_transparency_leaf(obj.key_material).__dict__

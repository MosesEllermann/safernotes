from __future__ import annotations

from django.contrib.auth import authenticate
from rest_framework import serializers

from apps.authentication.models import KeyMaterial, Session
from apps.authentication.tokens import hash_token
from apps.core.locales import normalize_locale
from apps.core.serializers import BinaryTextField, EncryptedEnvelopeField
from apps.devices.models import Device
from apps.tenants.models import Membership, Organization
from apps.users.models import Profile, User


class RegistrationSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True, min_length=8)
    kdf_algorithm = serializers.CharField(default="argon2id")
    kdf_params = serializers.JSONField()
    password_salt = serializers.CharField()
    public_encryption_key = serializers.CharField()
    public_signing_key = serializers.CharField()
    public_encryption_key_fingerprint = serializers.CharField(
        max_length=128, required=False, allow_blank=True
    )
    public_signing_key_fingerprint = serializers.CharField(
        max_length=128, required=False, allow_blank=True
    )
    encrypted_master_key = EncryptedEnvelopeField()
    encrypted_private_encryption_key = EncryptedEnvelopeField()
    encrypted_private_signing_key = EncryptedEnvelopeField()
    recovery_wrapper = EncryptedEnvelopeField()
    device_name_ciphertext = EncryptedEnvelopeField(required=False)
    device_public_signing_key = serializers.CharField(required=False)
    default_tenant_name_ciphertext = EncryptedEnvelopeField()
    locale = serializers.CharField(required=False, default="en")

    def validate_email(self, value):
        if User.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError("An account with this email already exists.")
        return value

    def create(self, validated_data):
        password = validated_data.pop("password")
        email = validated_data.pop("email")
        locale = normalize_locale(validated_data.pop("locale", "en"))
        device_name_ciphertext = validated_data.pop("device_name_ciphertext", None)
        device_public_signing_key = validated_data.pop("device_public_signing_key", None)
        default_tenant_name_ciphertext = validated_data.pop("default_tenant_name_ciphertext")
        binary_fields = ["password_salt", "public_encryption_key", "public_signing_key"]
        key_data = {field: validated_data.pop(field).encode("utf-8") for field in binary_fields}
        user = User.objects.create_user(email=email, password=password)
        Profile.objects.create(user=user, locale=locale)
        KeyMaterial.objects.create(user=user, **validated_data, **key_data)
        tenant = Organization.objects.create(
            name_ciphertext=default_tenant_name_ciphertext,
            owner_user=user,
        )
        Membership.objects.create(tenant=tenant, user=user, role="owner")
        user.default_tenant = tenant
        user.save(update_fields=["default_tenant", "updated_at"])
        self.default_tenant = tenant
        self.device = None
        if device_name_ciphertext and device_public_signing_key:
            self.device = Device.objects.create(
                user=user,
                name_ciphertext=device_name_ciphertext,
                public_signing_key=device_public_signing_key.encode("utf-8"),
            )
        return user


class LoginSerializer(serializers.Serializer):
    email = serializers.EmailField()
    password = serializers.CharField(write_only=True)
    device_id = serializers.UUIDField(required=False)

    def validate(self, attrs):
        user = authenticate(username=attrs["email"], password=attrs["password"])
        if user is None:
            raise serializers.ValidationError("Invalid credentials.")
        attrs["user"] = user
        device_id = attrs.get("device_id")
        attrs["device"] = None
        if device_id:
            attrs["device"] = Device.objects.filter(
                user=user, id=device_id, revoked_at__isnull=True
            ).first()
            if attrs["device"] is None:
                raise serializers.ValidationError("Unknown or revoked device.")
        return attrs


class RefreshSerializer(serializers.Serializer):
    refresh_token = serializers.CharField()

    def validate(self, attrs):
        token_hash = hash_token(attrs["refresh_token"])
        session = Session.objects.filter(
            refresh_token_hash=token_hash, revoked_at__isnull=True
        ).first()
        if session is None:
            reused_session = Session.objects.filter(
                previous_refresh_token_hash=token_hash, revoked_at__isnull=True
            ).first()
            if reused_session:
                from django.utils import timezone

                reused_session.refresh_reused_at = timezone.now()
                reused_session.revoked_at = reused_session.refresh_reused_at
                reused_session.save(update_fields=["refresh_reused_at", "revoked_at", "updated_at"])
            raise serializers.ValidationError("Invalid refresh token.")
        attrs["session"] = session
        return attrs


class KeyMaterialSerializer(serializers.ModelSerializer):
    password_salt = BinaryTextField()
    public_encryption_key = BinaryTextField()
    public_signing_key = BinaryTextField()

    class Meta:
        model = KeyMaterial
        fields = [
            "kdf_algorithm",
            "kdf_params",
            "password_salt",
            "public_encryption_key",
            "public_signing_key",
            "public_encryption_key_fingerprint",
            "public_signing_key_fingerprint",
            "encrypted_master_key",
            "encrypted_private_encryption_key",
            "encrypted_private_signing_key",
            "recovery_wrapper",
            "key_version",
        ]


class SessionSerializer(serializers.ModelSerializer):
    device_id = serializers.UUIDField(source="device.id", read_only=True)

    class Meta:
        model = Session
        fields = [
            "id",
            "device_id",
            "ip_hash",
            "user_agent_hash",
            "refreshed_at",
            "expires_at",
            "revoked_at",
            "refresh_reused_at",
            "created_at",
            "updated_at",
        ]
        read_only_fields = fields


class RecoveryStartSerializer(serializers.Serializer):
    email = serializers.EmailField()

    def validate(self, attrs):
        user = User.objects.filter(email__iexact=attrs["email"]).first()
        attrs["user"] = user
        return attrs


class RecoveryCompleteSerializer(serializers.Serializer):
    email = serializers.EmailField()
    code = serializers.CharField(min_length=6, max_length=12)
    password = serializers.CharField(write_only=True, min_length=8)
    kdf_algorithm = serializers.CharField(default="argon2id")
    kdf_params = serializers.JSONField()
    password_salt = serializers.CharField()
    encrypted_master_key = EncryptedEnvelopeField()


class RecoveryKeyUpdateSerializer(serializers.Serializer):
    recovery_wrapper = EncryptedEnvelopeField()

    def to_internal_value(self, data):
        if "recovery_key" in data:
            raise serializers.ValidationError(
                {"recovery_key": "Plaintext recovery keys are forbidden."}
            )
        return super().to_internal_value(data)


class EmailVerificationConfirmSerializer(serializers.Serializer):
    code = serializers.CharField(min_length=6, max_length=12)


class PasswordChangeSerializer(serializers.Serializer):
    current_password = serializers.CharField(write_only=True)
    new_password = serializers.CharField(write_only=True, min_length=8)
    kdf_algorithm = serializers.CharField(default="argon2id")
    kdf_params = serializers.JSONField()
    password_salt = serializers.CharField()
    encrypted_master_key = EncryptedEnvelopeField()

    def validate_current_password(self, value):
        user = self.context["request"].user
        if not user.check_password(value):
            raise serializers.ValidationError("Current password is incorrect.")
        return value

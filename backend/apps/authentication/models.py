from __future__ import annotations

from django.db import models

from apps.core.models import EncryptedJSONField, TimeStampedUUIDModel


class KeyMaterial(TimeStampedUUIDModel):
    user = models.OneToOneField("users.User", on_delete=models.CASCADE, related_name="key_material")
    kdf_algorithm = models.CharField(max_length=32, default="argon2id")
    kdf_params = models.JSONField()
    password_salt = models.BinaryField()
    public_encryption_key = models.BinaryField()
    public_signing_key = models.BinaryField()
    public_encryption_key_fingerprint = models.CharField(max_length=128, blank=True)
    public_signing_key_fingerprint = models.CharField(max_length=128, blank=True)
    encrypted_master_key = EncryptedJSONField()
    encrypted_private_encryption_key = EncryptedJSONField()
    encrypted_private_signing_key = EncryptedJSONField()
    recovery_wrapper = EncryptedJSONField(null=True, blank=True)
    key_version = models.PositiveIntegerField(default=1)


class Session(TimeStampedUUIDModel):
    user = models.ForeignKey("users.User", on_delete=models.CASCADE, related_name="sessions")
    device = models.ForeignKey(
        "devices.Device", null=True, blank=True, on_delete=models.SET_NULL, related_name="sessions"
    )
    access_token_hash = models.CharField(max_length=255, unique=True)
    refresh_token_hash = models.CharField(max_length=255)
    previous_refresh_token_hash = models.CharField(max_length=255, blank=True)
    ip_hash = models.CharField(max_length=128, blank=True)
    user_agent_hash = models.CharField(max_length=128, blank=True)
    refreshed_at = models.DateTimeField(null=True, blank=True)
    expires_at = models.DateTimeField()
    revoked_at = models.DateTimeField(null=True, blank=True)
    refresh_reused_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=["user", "revoked_at"]),
            models.Index(fields=["device", "revoked_at"]),
            models.Index(fields=["refresh_token_hash"]),
        ]

    @property
    def is_active(self) -> bool:
        return self.revoked_at is None


class RecoveryCode(TimeStampedUUIDModel):
    user = models.ForeignKey("users.User", on_delete=models.CASCADE, related_name="recovery_codes")
    code_hash = models.CharField(max_length=64)
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(null=True, blank=True)
    attempts = models.PositiveSmallIntegerField(default=0)

    class Meta:
        indexes = [
            models.Index(fields=["user", "expires_at", "used_at"]),
        ]

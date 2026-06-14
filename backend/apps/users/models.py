from __future__ import annotations

from django.contrib.auth.models import AbstractUser, BaseUserManager
from django.db import models

from apps.core.models import EncryptedJSONField, TimeStampedUUIDModel


class UserManager(BaseUserManager):
    use_in_migrations = True

    def create_user(self, email: str, password: str | None = None, **extra_fields):
        if not email:
            raise ValueError("Email is required.")
        email = self.normalize_email(email)
        user = self.model(email=email, username=email, **extra_fields)
        user.set_password(password)
        user.save(using=self._db)
        return user

    def create_superuser(self, email: str, password: str | None = None, **extra_fields):
        extra_fields.setdefault("is_staff", True)
        extra_fields.setdefault("is_superuser", True)
        extra_fields.setdefault("is_active", True)
        return self.create_user(email, password, **extra_fields)


class User(AbstractUser):
    username = models.CharField(max_length=254, unique=True)
    email = models.EmailField(unique=True)
    email_verified_at = models.DateTimeField(null=True, blank=True)
    status = models.CharField(max_length=32, default="active")
    default_tenant = models.ForeignKey(
        "tenants.Organization",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="default_users",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    USERNAME_FIELD = "email"
    REQUIRED_FIELDS: list[str] = []

    objects = UserManager()


class Profile(TimeStampedUUIDModel):
    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name="profile")
    display_name_ciphertext = EncryptedJSONField(null=True, blank=True)
    avatar_attachment = models.ForeignKey(
        "attachments.Attachment",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="profile_avatars",
    )
    locale = models.CharField(max_length=32, default="en")
    timezone = models.CharField(max_length=64, default="UTC")


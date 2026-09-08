from __future__ import annotations

from django.db import models

from apps.core.models import EncryptedJSONField, TimeStampedUUIDModel
from apps.notes.sync_models import SyncCheckpoint, SyncOperationReceipt


class NoteState(models.TextChoices):
    ACTIVE = "active", "Active"
    ARCHIVED = "archived", "Archived"
    TRASHED = "trashed", "Trashed"
    DELETED = "deleted", "Deleted"


class CollaboratorRole(models.TextChoices):
    OWNER = "owner", "Owner"
    EDITOR = "editor", "Editor"
    VIEWER = "viewer", "Viewer"


class ShareInvitationStatus(models.TextChoices):
    PENDING = "pending", "Pending"
    ACCEPTED = "accepted", "Accepted"
    DECLINED = "declined", "Declined"
    REVOKED = "revoked", "Revoked"


class Note(TimeStampedUUIDModel):
    tenant = models.ForeignKey(
        "tenants.Organization", on_delete=models.CASCADE, related_name="notes"
    )
    owner_user = models.ForeignKey(
        "users.User", on_delete=models.PROTECT, related_name="owned_notes"
    )
    state = models.CharField(max_length=16, choices=NoteState.choices, default=NoteState.ACTIVE)
    pinned = models.BooleanField(default=False)
    version = models.PositiveBigIntegerField(default=1)
    schema_version = models.PositiveIntegerField(default=1)
    encrypted_payload = EncryptedJSONField()
    payload_hash = models.BinaryField()
    storage_bytes = models.PositiveBigIntegerField(default=0, editable=False)
    client_updated_at = models.DateTimeField()
    deleted_at = models.DateTimeField(null=True, blank=True)

    def save(self, *args, **kwargs):
        from apps.core.storage import encrypted_note_storage_size

        self.storage_bytes = encrypted_note_storage_size(
            self.encrypted_payload,
            self.payload_hash,
        )
        update_fields = kwargs.get("update_fields")
        if update_fields is not None and (
            self._state.adding
            or "encrypted_payload" in update_fields
            or "payload_hash" in update_fields
        ):
            kwargs["update_fields"] = {*update_fields, "storage_bytes"}
        return super().save(*args, **kwargs)

    class Meta:
        indexes = [
            models.Index(fields=["tenant", "updated_at"]),
            models.Index(fields=["tenant", "state", "updated_at"]),
        ]


class NoteKeyGrant(TimeStampedUUIDModel):
    note = models.ForeignKey(Note, on_delete=models.CASCADE, related_name="key_grants")
    recipient_user = models.ForeignKey(
        "users.User", on_delete=models.CASCADE, related_name="received_note_grants"
    )
    sender_user = models.ForeignKey(
        "users.User", on_delete=models.PROTECT, related_name="sent_note_grants"
    )
    role = models.CharField(max_length=16, choices=CollaboratorRole.choices)
    encrypted_note_key = EncryptedJSONField()
    grant_signature = models.BinaryField()
    source_invitation = models.ForeignKey(
        "notes.ShareInvitation",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="created_grants",
    )
    revoked_at = models.DateTimeField(null=True, blank=True)
    revoked_reason = models.CharField(max_length=128, blank=True)

    class Meta:
        indexes = [models.Index(fields=["note", "recipient_user"])]


class ShareInvitation(TimeStampedUUIDModel):
    note = models.ForeignKey(Note, on_delete=models.CASCADE, related_name="share_invitations")
    sender_user = models.ForeignKey(
        "users.User", on_delete=models.PROTECT, related_name="sent_share_invitations"
    )
    recipient_user = models.ForeignKey(
        "users.User", on_delete=models.CASCADE, related_name="received_share_invitations"
    )
    role = models.CharField(max_length=16, choices=CollaboratorRole.choices)
    encrypted_note_key = EncryptedJSONField()
    invitation_signature = models.BinaryField()
    status = models.CharField(
        max_length=16,
        choices=ShareInvitationStatus.choices,
        default=ShareInvitationStatus.PENDING,
    )
    accepted_at = models.DateTimeField(null=True, blank=True)
    declined_at = models.DateTimeField(null=True, blank=True)
    revoked_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=["recipient_user", "status", "created_at"]),
            models.Index(fields=["note", "status"]),
        ]


class NoteConflict(TimeStampedUUIDModel):
    note = models.ForeignKey(Note, on_delete=models.CASCADE, related_name="conflicts")
    actor_user = models.ForeignKey(
        "users.User", on_delete=models.PROTECT, related_name="note_conflicts"
    )
    base_version = models.PositiveBigIntegerField()
    server_version = models.PositiveBigIntegerField()
    encrypted_payload = EncryptedJSONField()
    payload_hash = models.BinaryField()
    client_updated_at = models.DateTimeField()
    resolved_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        indexes = [
            models.Index(fields=["note", "resolved_at", "created_at"]),
            models.Index(fields=["actor_user", "created_at"]),
        ]


class Label(TimeStampedUUIDModel):
    tenant = models.ForeignKey(
        "tenants.Organization", on_delete=models.CASCADE, related_name="labels"
    )
    owner_user = models.ForeignKey("users.User", on_delete=models.CASCADE, related_name="labels")
    encrypted_payload = EncryptedJSONField()


class NoteLabel(TimeStampedUUIDModel):
    note = models.ForeignKey(Note, on_delete=models.CASCADE, related_name="label_links")
    label = models.ForeignKey(Label, on_delete=models.CASCADE, related_name="note_links")

    class Meta:
        constraints = [models.UniqueConstraint(fields=["note", "label"], name="unique_note_label")]


__all__ = [
    "CollaboratorRole",
    "Label",
    "Note",
    "NoteConflict",
    "NoteKeyGrant",
    "NoteLabel",
    "NoteState",
    "ShareInvitation",
    "ShareInvitationStatus",
    "SyncCheckpoint",
    "SyncOperationReceipt",
]

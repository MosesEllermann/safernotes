from __future__ import annotations

from uuid import UUID

from rest_framework import serializers

from apps.core.serializers import BinaryTextField, EncryptedEnvelopeField, RejectPlaintextMixin
from apps.notes.exceptions import VersionConflict
from apps.notes.models import (
    Label,
    Note,
    NoteConflict,
    NoteKeyGrant,
    NoteState,
    ShareInvitation,
)
from apps.notes.permissions import can_share_note
from apps.users.models import User


class NoteSerializer(RejectPlaintextMixin, serializers.ModelSerializer):
    encrypted_payload = EncryptedEnvelopeField()
    payload_hash = BinaryTextField()
    expected_version = serializers.IntegerField(write_only=True, required=False, min_value=1)

    class Meta:
        model = Note
        fields = [
            "id",
            "tenant",
            "owner_user",
            "state",
            "pinned",
            "version",
            "schema_version",
            "encrypted_payload",
            "payload_hash",
            "expected_version",
            "client_updated_at",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "owner_user", "created_at", "updated_at"]

    def create(self, validated_data):
        validated_data.pop("expected_version", None)
        validated_data["owner_user"] = self.context["request"].user
        return super().create(validated_data)

    def update(self, instance, validated_data):
        expected_version = validated_data.pop("expected_version", None)
        if expected_version is not None and expected_version != instance.version:
            NoteConflict.objects.create(
                note=instance,
                actor_user=self.context["request"].user,
                base_version=expected_version,
                server_version=instance.version,
                encrypted_payload=validated_data.get("encrypted_payload", instance.encrypted_payload),
                payload_hash=validated_data.get("payload_hash", b""),
                client_updated_at=validated_data.get("client_updated_at", instance.client_updated_at),
            )
            raise VersionConflict(
                {
                    "detail": "Server has a newer encrypted note version.",
                    "server_version": instance.version,
                    "conflict_saved": True,
                }
            )
        validated_data["version"] = instance.version + 1
        return super().update(instance, validated_data)


class NoteStateSerializer(serializers.Serializer):
    state = serializers.ChoiceField(choices=NoteState.choices)


class NoteKeyGrantSerializer(RejectPlaintextMixin, serializers.ModelSerializer):
    encrypted_note_key = EncryptedEnvelopeField()
    grant_signature = BinaryTextField()

    class Meta:
        model = NoteKeyGrant
        fields = [
            "id",
            "note",
            "recipient_user",
            "sender_user",
            "role",
            "encrypted_note_key",
            "grant_signature",
            "source_invitation",
            "revoked_at",
            "revoked_reason",
            "created_at",
        ]
        read_only_fields = ["id", "sender_user", "source_invitation", "revoked_at", "revoked_reason", "created_at"]

    def create(self, validated_data):
        request = self.context["request"]
        note = validated_data["note"]
        if not can_share_note(request.user, note):
            raise serializers.ValidationError("Only note owners can create or change note key grants.")
        validated_data["sender_user"] = self.context["request"].user
        return super().create(validated_data)


class UserIdentifierField(serializers.PrimaryKeyRelatedField):
    default_error_messages = {
        "does_not_exist": "No user found for this ID or email.",
        "incorrect_type": "Expected a user ID or email address.",
    }

    def to_internal_value(self, data):
        if not isinstance(data, str):
            self.fail("incorrect_type")
        value = data.strip()
        try:
            UUID(value)
        except ValueError:
            try:
                return self.get_queryset().get(email__iexact=value)
            except User.DoesNotExist:
                self.fail("does_not_exist")
        return super().to_internal_value(value)


class ShareInvitationSerializer(RejectPlaintextMixin, serializers.ModelSerializer):
    recipient_user = UserIdentifierField(queryset=User.objects.all())
    encrypted_note_key = EncryptedEnvelopeField()
    invitation_signature = BinaryTextField()
    encrypted_notification_payload = EncryptedEnvelopeField(write_only=True, required=False)

    class Meta:
        model = ShareInvitation
        fields = [
            "id",
            "note",
            "sender_user",
            "recipient_user",
            "role",
            "encrypted_note_key",
            "invitation_signature",
            "encrypted_notification_payload",
            "status",
            "accepted_at",
            "declined_at",
            "revoked_at",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "id",
            "sender_user",
            "status",
            "accepted_at",
            "declined_at",
            "revoked_at",
            "created_at",
            "updated_at",
        ]

    def validate(self, attrs):
        attrs = super().validate(attrs)
        request = self.context["request"]
        if not can_share_note(request.user, attrs["note"]):
            raise serializers.ValidationError("Only note owners can create share invitations.")
        if attrs["role"] == "owner":
            raise serializers.ValidationError("Use ownership transfer for owner role.")
        return attrs

    def create(self, validated_data):
        self.encrypted_notification_payload = validated_data.pop("encrypted_notification_payload", None)
        validated_data["sender_user"] = self.context["request"].user
        return super().create(validated_data)


class ShareInvitationDecisionSerializer(serializers.Serializer):
    decision = serializers.ChoiceField(choices=["accept", "decline"])


class OwnershipTransferSerializer(RejectPlaintextMixin, serializers.Serializer):
    new_owner_user = serializers.PrimaryKeyRelatedField(read_only=False, queryset=User.objects.all())
    encrypted_note_key = EncryptedEnvelopeField()
    transfer_signature = BinaryTextField()
    encrypted_notification_payload = EncryptedEnvelopeField(required=False)


class GrantRevocationSerializer(serializers.Serializer):
    reason = serializers.CharField(max_length=128, required=False, allow_blank=True)


class NoteConflictSerializer(serializers.ModelSerializer):
    payload_hash = BinaryTextField()

    class Meta:
        model = NoteConflict
        fields = [
            "id",
            "note",
            "base_version",
            "server_version",
            "encrypted_payload",
            "payload_hash",
            "client_updated_at",
            "resolved_at",
            "created_at",
        ]
        read_only_fields = fields


class ConflictResolutionSerializer(serializers.Serializer):
    resolved = serializers.BooleanField(default=True)


class LabelSerializer(RejectPlaintextMixin, serializers.ModelSerializer):
    encrypted_payload = EncryptedEnvelopeField()

    class Meta:
        model = Label
        fields = ["id", "tenant", "owner_user", "encrypted_payload", "created_at", "updated_at"]
        read_only_fields = ["id", "owner_user", "created_at", "updated_at"]

    def create(self, validated_data):
        validated_data["owner_user"] = self.context["request"].user
        return super().create(validated_data)

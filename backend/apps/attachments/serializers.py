from __future__ import annotations

import uuid

from django.utils import timezone
from rest_framework import serializers

from apps.attachments.models import Attachment, AttachmentUploadState, size_bucket_for
from apps.core.serializers import BinaryTextField, EncryptedEnvelopeField, RejectPlaintextMixin


class AttachmentSerializer(RejectPlaintextMixin, serializers.ModelSerializer):
    encrypted_metadata = EncryptedEnvelopeField()
    ciphertext_sha256 = BinaryTextField()

    class Meta:
        model = Attachment
        fields = [
            "id",
            "tenant",
            "note",
            "object_key",
            "ciphertext_size",
            "ciphertext_sha256",
            "encrypted_metadata",
            "upload_state",
            "upload_expires_at",
            "completed_at",
            "deleted_at",
            "size_bucket",
            "created_at",
            "updated_at",
        ]
        read_only_fields = [
            "id",
            "object_key",
            "upload_state",
            "upload_expires_at",
            "completed_at",
            "deleted_at",
            "size_bucket",
            "created_at",
            "updated_at",
        ]

    def create(self, validated_data):
        validated_data["object_key"] = (
            f"attachments/{validated_data['tenant'].id}/{validated_data['note'].id}/{uuid.uuid4()}"
        )
        validated_data["size_bucket"] = size_bucket_for(validated_data["ciphertext_size"])
        return super().create(validated_data)


class AttachmentInitiateSerializer(AttachmentSerializer):
    pass


class AttachmentCompleteSerializer(serializers.Serializer):
    ciphertext_sha256 = BinaryTextField()

    def validate(self, attrs):
        attachment = self.context["attachment"]
        if attachment.upload_state not in {AttachmentUploadState.INITIATED, AttachmentUploadState.UPLOADED}:
            raise serializers.ValidationError("Attachment upload is not in a completable state.")
        if attachment.ciphertext_sha256 != attrs["ciphertext_sha256"]:
            raise serializers.ValidationError("Ciphertext checksum mismatch.")
        if attachment.upload_expires_at and attachment.upload_expires_at < timezone.now():
            raise serializers.ValidationError("Attachment upload target has expired.")
        return attrs

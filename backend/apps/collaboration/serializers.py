from __future__ import annotations

from django.utils import timezone
from rest_framework import serializers

from apps.collaboration.models import CollaborationPresence, SyncEvent, SyncEventAck
from apps.core.serializers import BinaryTextField, EncryptedEnvelopeField, RejectPlaintextMixin
from apps.notes.permissions import can_read_note, can_write_note


class SyncEventSerializer(RejectPlaintextMixin, serializers.ModelSerializer):
    encrypted_delta = EncryptedEnvelopeField()
    event_signature = BinaryTextField()

    class Meta:
        model = SyncEvent
        fields = [
            "id",
            "tenant",
            "note",
            "actor_user",
            "note_version",
            "encrypted_delta",
            "event_signature",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ["id", "actor_user", "created_at", "updated_at"]

    def validate(self, attrs):
        attrs = super().validate(attrs)
        request = self.context["request"]
        if not can_write_note(request.user, attrs["note"]):
            raise serializers.ValidationError("Viewer role cannot append encrypted collaboration events.")
        if attrs["tenant"] != attrs["note"].tenant:
            raise serializers.ValidationError("Collaboration event tenant must match note tenant.")
        return attrs

    def create(self, validated_data):
        validated_data["actor_user"] = self.context["request"].user
        return super().create(validated_data)


class SyncEventAckSerializer(serializers.ModelSerializer):
    class Meta:
        model = SyncEventAck
        fields = ["id", "event", "user", "device", "received_at", "created_at"]
        read_only_fields = ["id", "user", "device", "received_at", "created_at"]

    def validate(self, attrs):
        attrs = super().validate(attrs)
        request = self.context["request"]
        if not can_read_note(request.user, attrs["event"].note):
            raise serializers.ValidationError("Cannot acknowledge events for inaccessible notes.")
        return attrs

    def create(self, validated_data):
        request = self.context["request"]
        session = getattr(request, "auth", None)
        validated_data["user"] = request.user
        validated_data["device"] = getattr(session, "device", None)
        validated_data["received_at"] = timezone.now()
        ack, _ = SyncEventAck.objects.update_or_create(
            event=validated_data["event"],
            user=validated_data["user"],
            device=validated_data["device"],
            defaults={"received_at": validated_data["received_at"]},
        )
        return ack


class CollaborationPresenceSerializer(serializers.ModelSerializer):
    class Meta:
        model = CollaborationPresence
        fields = ["id", "note", "user", "device", "status", "updated_at"]
        read_only_fields = fields

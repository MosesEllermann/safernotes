from __future__ import annotations

from rest_framework import serializers

from apps.core.serializers import EncryptedEnvelopeField, RejectPlaintextMixin
from apps.notifications.models import Notification
from apps.users.models import User


class NotificationSerializer(RejectPlaintextMixin, serializers.ModelSerializer):
    encrypted_payload = EncryptedEnvelopeField()

    class Meta:
        model = Notification
        fields = ["id", "type", "encrypted_payload", "read_at", "created_at", "updated_at"]
        read_only_fields = ["id", "created_at", "updated_at"]


class EncryptedNotificationFanoutItemSerializer(RejectPlaintextMixin, serializers.Serializer):
    user = serializers.PrimaryKeyRelatedField(read_only=False, queryset=User.objects.all())
    encrypted_payload = EncryptedEnvelopeField()


class EncryptedNotificationFanoutSerializer(serializers.Serializer):
    type = serializers.CharField(max_length=64)
    recipients = EncryptedNotificationFanoutItemSerializer(many=True)

    def validate_recipients(self, value):
        if not value:
            raise serializers.ValidationError("At least one encrypted recipient payload is required.")
        if len(value) > 50:
            raise serializers.ValidationError("Fanout is limited to 50 encrypted recipient payloads.")
        return value

    def create(self, validated_data):
        notification_type = validated_data["type"]
        notifications = [
            Notification(
                user=item["user"],
                type=notification_type,
                encrypted_payload=item["encrypted_payload"],
            )
            for item in validated_data["recipients"]
        ]
        return Notification.objects.bulk_create(notifications)

from __future__ import annotations

from rest_framework import serializers

from apps.billing.models import BillingEvent


class BillingEventSerializer(serializers.ModelSerializer):
    class Meta:
        model = BillingEvent
        fields = [
            "id",
            "provider",
            "provider_event_id",
            "event_type",
            "signature_valid",
            "processing_status",
            "processed_at",
            "created_at",
        ]
        read_only_fields = fields

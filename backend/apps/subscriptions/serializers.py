from __future__ import annotations

from rest_framework import serializers

from apps.subscriptions.models import Subscription
from apps.subscriptions.plans import policy_for_plan


class SubscriptionSerializer(serializers.ModelSerializer):
    policy = serializers.SerializerMethodField()

    class Meta:
        model = Subscription
        fields = [
            "id",
            "tenant",
            "plan",
            "status",
            "billing_provider",
            "current_period_end",
            "policy",
            "created_at",
            "updated_at",
        ]
        read_only_fields = fields

    def get_policy(self, obj):
        return policy_for_plan(obj.plan).as_dict()

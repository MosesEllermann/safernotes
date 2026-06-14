from __future__ import annotations

from rest_framework import permissions, response, views

from apps.audit.events import record_audit_event
from apps.billing.models import BillingEvent
from apps.billing.processor import process_billing_event
from apps.billing.signatures import verify_webhook_signature


class BillingWebhookView(views.APIView):
    permission_classes = [permissions.AllowAny]

    def post(self, request):
        signature_valid = verify_webhook_signature(request.body, request.headers.get("X-Billing-Signature"))
        if not signature_valid:
            return response.Response({"detail": "Invalid billing webhook signature."}, status=401)
        provider_event_id = request.data.get("id")
        if not provider_event_id:
            return response.Response({"detail": "Billing webhook event id is required."}, status=400)
        event, created = BillingEvent.objects.get_or_create(
            provider=request.headers.get("X-Billing-Provider", "unknown"),
            provider_event_id=provider_event_id,
            defaults={
                "event_type": request.data.get("type", "unknown"),
                "payload": request.data,
                "signature_valid": signature_valid,
            },
        )
        if created:
            process_billing_event(event)
            record_audit_event(
                event_type="billing.webhook_received",
                target_type="billing_event",
                target_id=event.id,
                metadata={
                    "provider": event.provider,
                    "event_type": event.event_type,
                    "processing_status": event.processing_status,
                },
            )
        return response.Response(
            {
                "id": str(event.id),
                "received": True,
                "created": created,
                "processing_status": event.processing_status,
            },
            status=202,
        )

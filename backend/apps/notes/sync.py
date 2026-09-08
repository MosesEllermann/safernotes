from __future__ import annotations

from django.db import transaction
from django.utils import dateparse, timezone
from rest_framework import serializers, views
from rest_framework.response import Response

from apps.attachments.quota import can_store_note_bytes, locked_usage_for_tenant
from apps.core.abuse import increment_metadata_limit
from apps.notes.models import Note
from apps.notes.permissions import can_write_note
from apps.notes.serializers import NoteSerializer, NoteStateSerializer
from apps.notes.sync_models import SyncCheckpoint, SyncOperationReceipt


class SyncOperationSerializer(serializers.Serializer):
    idempotency_key = serializers.CharField(max_length=128)
    type = serializers.ChoiceField(choices=["upsert_note", "change_state"])
    note_id = serializers.UUIDField(required=False)
    payload = serializers.DictField()


class SyncBatchSerializer(serializers.Serializer):
    device_id = serializers.UUIDField(required=False)
    operations = SyncOperationSerializer(many=True)
    update_checkpoint = serializers.BooleanField(default=True)


def request_device(request, device_id=None):
    if device_id:
        return request.user.devices.filter(id=device_id, revoked_at__isnull=True).first()
    session = getattr(request, "auth", None)
    return getattr(session, "device", None)


def visible_notes_queryset(user):
    return (
        Note.objects.filter(key_grants__recipient_user=user, key_grants__revoked_at__isnull=True)
        | Note.objects.filter(owner_user=user)
    ).distinct()


class SyncChangesView(views.APIView):
    def get(self, request):
        cursor = request.query_params.get("cursor")
        updated_after = dateparse.parse_datetime(cursor) if cursor else None
        device = request_device(request, request.query_params.get("device_id"))
        if updated_after is None and device is not None:
            checkpoint = SyncCheckpoint.objects.filter(user=request.user, device=device).first()
            updated_after = checkpoint.cursor if checkpoint else None
        queryset = visible_notes_queryset(request.user).order_by("updated_at")
        if updated_after:
            queryset = queryset.filter(updated_at__gt=updated_after)
        notes = list(queryset[:100])
        next_cursor = notes[-1].updated_at.isoformat() if notes else timezone.now().isoformat()
        if device is not None:
            SyncCheckpoint.objects.update_or_create(
                user=request.user,
                device=device,
                defaults={"cursor": dateparse.parse_datetime(next_cursor) or timezone.now()},
            )
        return Response(
            {
                "next_cursor": next_cursor,
                "checkpoint_device_id": str(device.id) if device else None,
                "notes": NoteSerializer(notes, many=True, context={"request": request}).data,
            }
        )


class SyncBatchView(views.APIView):
    @transaction.atomic
    def post(self, request):
        allowed, count = increment_metadata_limit("sync_batch", str(request.user.id))
        if not allowed:
            raise serializers.ValidationError(
                {"detail": "Sync batch rate limit exceeded.", "count": count}
            )
        serializer = SyncBatchSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        device = request_device(request, serializer.validated_data.get("device_id"))
        results = []
        for index, operation in enumerate(serializer.validated_data["operations"]):
            idempotency_key = operation["idempotency_key"]
            existing = SyncOperationReceipt.objects.filter(
                user=request.user,
                idempotency_key=idempotency_key,
            ).first()
            if existing:
                replay_result = dict(existing.result)
                replay_result.update({"index": index, "replayed": True})
                results.append(replay_result)
                continue

            operation_type = operation["type"]
            payload = operation["payload"]
            note_id = operation.get("note_id") or payload.get("id")
            result = {"index": index, "status": "ignored"}

            if operation_type == "upsert_note":
                if note_id:
                    note = Note.objects.filter(id=note_id).first()
                    if note:
                        if not can_write_note(request.user, note):
                            result = {"index": index, "status": "forbidden"}
                            results.append(result)
                            SyncOperationReceipt.objects.create(
                                user=request.user,
                                device=device,
                                idempotency_key=idempotency_key,
                                operation_type=operation_type,
                                result=result,
                            )
                            continue
                        note_serializer = NoteSerializer(
                            note,
                            data=payload,
                            partial=True,
                            context={"request": request},
                        )
                    else:
                        note_serializer = NoteSerializer(data=payload, context={"request": request})
                else:
                    note_serializer = NoteSerializer(data=payload, context={"request": request})

                note_serializer.is_valid(raise_exception=True)
                note = note_serializer.save()
                result = {
                    "index": index,
                    "status": "ok",
                    "note_id": str(note.id),
                    "version": note.version,
                }
                results.append(result)
                SyncOperationReceipt.objects.create(
                    user=request.user,
                    device=device,
                    idempotency_key=idempotency_key,
                    operation_type=operation_type,
                    result=result,
                )
                continue

            if operation_type == "change_state":
                state_serializer = NoteStateSerializer(data=payload)
                state_serializer.is_valid(raise_exception=True)
                note = Note.objects.filter(id=note_id).first()
                if note is None:
                    result = {"index": index, "status": "not_found"}
                    results.append(result)
                    SyncOperationReceipt.objects.create(
                        user=request.user,
                        device=device,
                        idempotency_key=idempotency_key,
                        operation_type=operation_type,
                        result=result,
                    )
                    continue
                if not can_write_note(request.user, note):
                    result = {"index": index, "status": "forbidden"}
                    results.append(result)
                    SyncOperationReceipt.objects.create(
                        user=request.user,
                        device=device,
                        idempotency_key=idempotency_key,
                        operation_type=operation_type,
                        result=result,
                    )
                    continue
                next_state = state_serializer.validated_data["state"]
                previous_bytes = 0 if note.state == "deleted" else note.storage_bytes
                next_bytes = 0 if next_state == "deleted" else note.storage_bytes
                usage = locked_usage_for_tenant(note.tenant)
                if not can_store_note_bytes(
                    note.tenant,
                    previous_bytes=previous_bytes,
                    next_bytes=next_bytes,
                    attachment_usage=usage,
                ):
                    raise serializers.ValidationError("Workspace storage quota exceeded.")
                note.state = next_state
                note.deleted_at = timezone.now() if next_state == "deleted" else None
                note.save(update_fields=["state", "deleted_at", "updated_at"])
                result = {
                    "index": index,
                    "status": "ok",
                    "note_id": str(note.id),
                    "version": note.version,
                }
                results.append(result)
                SyncOperationReceipt.objects.create(
                    user=request.user,
                    device=device,
                    idempotency_key=idempotency_key,
                    operation_type=operation_type,
                    result=result,
                )

        if serializer.validated_data["update_checkpoint"] and device is not None:
            SyncCheckpoint.objects.update_or_create(
                user=request.user,
                device=device,
                defaults={"cursor": timezone.now()},
            )

        return Response(
            {"checkpoint_device_id": str(device.id) if device else None, "results": results}
        )

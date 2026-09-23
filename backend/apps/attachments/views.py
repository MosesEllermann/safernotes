from __future__ import annotations

from datetime import timedelta

from django.conf import settings
from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from rest_framework import decorators, exceptions, mixins, permissions, response, viewsets

from apps.attachments.models import Attachment, AttachmentUploadState
from apps.attachments.quota import (
    can_reserve_attachment_bytes,
    release_attachment_bytes,
    reserve_attachment_bytes,
)
from apps.attachments.serializers import (
    AttachmentCompleteSerializer,
    AttachmentInitiateSerializer,
    AttachmentSerializer,
)
from apps.attachments.storage import presigned_download_target, presigned_upload_target
from apps.attachments.transfer import (
    TransferAuthentication,
    store_ciphertext,
    stream_ciphertext,
    transfer_target,
)
from apps.audit.events import record_audit_event
from apps.core.abuse import increment_metadata_limit
from apps.notes.permissions import can_write_note


class AttachmentViewSet(
    mixins.CreateModelMixin,
    mixins.ListModelMixin,
    mixins.RetrieveModelMixin,
    mixins.DestroyModelMixin,
    viewsets.GenericViewSet,
):
    serializer_class = AttachmentSerializer

    def get_queryset(self):
        return (
            Attachment.objects.filter(
                Q(note__owner_user=self.request.user)
                | Q(
                    note__key_grants__recipient_user=self.request.user,
                    note__key_grants__revoked_at__isnull=True,
                )
            )
            .exclude(upload_state=AttachmentUploadState.DELETED)
            .distinct()
        )

    def perform_create(self, serializer):
        note = serializer.validated_data["note"]
        if not can_write_note(self.request.user, note):
            raise exceptions.PermissionDenied("Viewer role cannot upload encrypted attachments.")
        if serializer.validated_data["tenant"] != note.tenant:
            raise exceptions.ValidationError("Attachment tenant must match note tenant.")
        if not can_reserve_attachment_bytes(
            note.tenant, serializer.validated_data["ciphertext_size"]
        ):
            raise exceptions.ValidationError("Attachment quota exceeded.")
        serializer.save(
            upload_expires_at=timezone.now()
            + timedelta(seconds=settings.ATTACHMENT_STORAGE["upload_url_ttl_seconds"])
        )
        record_audit_event(
            event_type="attachment.upload_initiated",
            actor_user=self.request.user,
            tenant=note.tenant,
            target_type="attachment",
            target_id=serializer.instance.id,
            metadata={"ciphertext_size": serializer.instance.ciphertext_size},
        )

    def perform_destroy(self, instance):
        if not can_write_note(self.request.user, instance.note):
            raise exceptions.PermissionDenied("Viewer role cannot delete encrypted attachments.")
        with transaction.atomic():
            if instance.upload_state == AttachmentUploadState.COMPLETE:
                release_attachment_bytes(instance.tenant, instance.ciphertext_size)
            instance.upload_state = AttachmentUploadState.DELETED
            instance.deleted_at = timezone.now()
            instance.save(update_fields=["upload_state", "deleted_at", "updated_at"])
        record_audit_event(
            event_type="attachment.deleted",
            actor_user=self.request.user,
            tenant=instance.tenant,
            target_type="attachment",
            target_id=instance.id,
        )

    def create(self, request, *args, **kwargs):
        allowed, count = increment_metadata_limit("attachment_initiate", str(request.user.id))
        if not allowed:
            raise exceptions.ValidationError(
                {"detail": "Attachment initiation rate limit exceeded.", "count": count}
            )
        serializer = AttachmentInitiateSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        self.perform_create(serializer)
        attachment = serializer.instance
        target = (
            transfer_target(attachment, request.user, "PUT")
            if settings.ATTACHMENT_PROXY_ENABLED
            else presigned_upload_target(attachment.object_key, attachment.ciphertext_size)
        )
        data = AttachmentSerializer(attachment, context={"request": request}).data
        data["upload"] = target.__dict__
        return response.Response(data, status=201, headers={"Cache-Control": "no-store"})

    @decorators.action(detail=True, methods=["put"])
    @transaction.atomic
    def complete(self, request, pk=None):
        attachment = self.get_object()
        attachment = Attachment.objects.select_for_update().get(pk=attachment.pk)
        if not can_write_note(request.user, attachment.note):
            raise exceptions.PermissionDenied(
                "Viewer role cannot complete encrypted attachment uploads."
            )
        if (
            settings.ATTACHMENT_PROXY_ENABLED
            and attachment.upload_state != AttachmentUploadState.UPLOADED
        ):
            raise exceptions.ValidationError("Upload the encrypted content before completing it.")
        serializer = AttachmentCompleteSerializer(
            data=request.data, context={"attachment": attachment}
        )
        serializer.is_valid(raise_exception=True)
        if attachment.upload_state != AttachmentUploadState.COMPLETE:
            usage = reserve_attachment_bytes(attachment.tenant, attachment.ciphertext_size)
            if usage is None:
                raise exceptions.ValidationError("Attachment quota exceeded.")
        attachment.upload_state = AttachmentUploadState.COMPLETE
        attachment.completed_at = timezone.now()
        attachment.save(update_fields=["upload_state", "completed_at", "updated_at"])
        record_audit_event(
            event_type="attachment.upload_completed",
            actor_user=request.user,
            tenant=attachment.tenant,
            target_type="attachment",
            target_id=attachment.id,
            metadata={"ciphertext_size": attachment.ciphertext_size},
        )
        return response.Response(
            AttachmentSerializer(attachment, context={"request": request}).data
        )

    @decorators.action(detail=True, methods=["get"])
    def download(self, request, pk=None):
        attachment = self.get_object()
        if attachment.upload_state != AttachmentUploadState.COMPLETE:
            raise exceptions.ValidationError("Attachment is not available for download.")
        target = (
            transfer_target(attachment, request.user, "GET")
            if settings.ATTACHMENT_PROXY_ENABLED
            else presigned_download_target(attachment.object_key)
        )
        return response.Response(
            {"encrypted": True, "download": target.__dict__}, headers={"Cache-Control": "no-store"}
        )

    @decorators.action(
        detail=True,
        methods=["get", "put"],
        authentication_classes=[TransferAuthentication],
        permission_classes=[permissions.IsAuthenticated],
    )
    def content(self, request, pk=None):
        attachment = self.get_object()
        if request.method == "GET":
            if attachment.upload_state != AttachmentUploadState.COMPLETE:
                raise exceptions.ValidationError("Attachment is not available for download.")
            return stream_ciphertext(attachment)
        with transaction.atomic():
            attachment = Attachment.objects.select_for_update().get(pk=attachment.pk)
            if not can_write_note(request.user, attachment.note):
                raise exceptions.PermissionDenied(
                    "Viewer role cannot upload encrypted attachments."
                )
            if attachment.upload_state not in {
                AttachmentUploadState.INITIATED,
                AttachmentUploadState.UPLOADED,
            }:
                raise exceptions.ValidationError("Attachment is not available for upload.")
            if not attachment.upload_expires_at or attachment.upload_expires_at < timezone.now():
                raise exceptions.ValidationError("Attachment upload target has expired.")
            store_ciphertext(request, attachment)
            attachment.upload_state = AttachmentUploadState.UPLOADED
            attachment.save(update_fields=["upload_state", "updated_at"])
        return response.Response(status=204)

    @decorators.action(detail=True, methods=["post"])
    def abort(self, request, pk=None):
        attachment = self.get_object()
        if not can_write_note(request.user, attachment.note):
            raise exceptions.PermissionDenied(
                "Viewer role cannot abort encrypted attachment uploads."
            )
        if attachment.upload_state == AttachmentUploadState.COMPLETE:
            raise exceptions.ValidationError("Completed attachments must be deleted, not aborted.")
        attachment.upload_state = AttachmentUploadState.ABORTED
        attachment.save(update_fields=["upload_state", "updated_at"])
        return response.Response(
            AttachmentSerializer(attachment, context={"request": request}).data
        )

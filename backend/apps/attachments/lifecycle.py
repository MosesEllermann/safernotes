from __future__ import annotations

from django.utils import timezone

from apps.attachments.models import Attachment, AttachmentUploadState


def abort_expired_uploads() -> int:
    now = timezone.now()
    return Attachment.objects.filter(
        upload_state=AttachmentUploadState.INITIATED,
        upload_expires_at__lt=now,
    ).update(upload_state=AttachmentUploadState.ABORTED, updated_at=now)


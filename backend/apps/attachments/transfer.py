"""Short-lived, permission-checked transfers through the application's origin."""

from __future__ import annotations

import asyncio
import base64
import hashlib
import hmac
import os
from dataclasses import dataclass
from tempfile import SpooledTemporaryFile
from urllib.parse import urlencode

from django.conf import settings
from django.contrib.auth import get_user_model
from django.core import signing
from django.http import StreamingHttpResponse
from django.urls import reverse
from rest_framework import authentication, exceptions

from apps.attachments.storage import open_ciphertext, write_ciphertext

TRANSFER_SALT = "safernotes.attachment.transfer.v1"


@dataclass(frozen=True)
class TransferTarget:
    object_key: str
    url: str
    fields: dict
    method: str
    expires_in: int


class StorageUnavailable(exceptions.APIException):
    status_code = 503
    default_detail = "Attachment storage is unavailable. Please retry later."


class TransferAuthentication(authentication.BaseAuthentication):
    def authenticate(self, request):
        method = request.method
        ttl = settings.ATTACHMENT_STORAGE[
            "upload_url_ttl_seconds" if method == "PUT" else "download_url_ttl_seconds"
        ]
        try:
            payload = signing.loads(
                request.query_params.get("token", ""), salt=TRANSFER_SALT, max_age=ttl
            )
            if (
                payload["method"] != method
                or payload["attachment"] != request.parser_context["kwargs"]["pk"]
            ):
                raise exceptions.AuthenticationFailed("Invalid attachment link.")
            user = get_user_model().objects.get(pk=payload["user"], is_active=True)
        except (signing.BadSignature, KeyError, ValueError, get_user_model().DoesNotExist) as error:
            raise exceptions.AuthenticationFailed("Invalid or expired attachment link.") from error
        return user, None


def transfer_target(attachment, user, method: str) -> TransferTarget:
    ttl = settings.ATTACHMENT_STORAGE[
        "upload_url_ttl_seconds" if method == "PUT" else "download_url_ttl_seconds"
    ]
    token = signing.dumps(
        {"attachment": str(attachment.pk), "user": str(user.pk), "method": method},
        salt=TRANSFER_SALT,
    )
    path = reverse("attachments-content", kwargs={"pk": attachment.pk})
    url = settings.APP_BASE_URL.rstrip("/") + path + "?" + urlencode({"token": token})
    return TransferTarget(attachment.object_key, url, {}, method, ttl)


def store_ciphertext(request, attachment):
    try:
        _store_ciphertext(request, attachment)
    except OSError as error:
        raise StorageUnavailable() from error


def _store_ciphertext(request, attachment):
    size = attachment.ciphertext_size
    if size < 1 or size > settings.ATTACHMENT_MAX_BYTES:
        raise exceptions.ValidationError("Attachment exceeds the supported size limit.")
    digest = hashlib.sha256()
    total = 0
    if request.stream is None:
        raise exceptions.ValidationError("Ciphertext size mismatch.")
    # Spooling bounds memory usage, and verifies the whole body before storing it.
    with SpooledTemporaryFile(max_size=1024 * 1024) as buffer:
        while True:
            chunk = request.stream.read(min(64 * 1024, size - total + 1))
            if not chunk:
                break
            total += len(chunk)
            if total > size:
                raise exceptions.ValidationError("Ciphertext size mismatch.")
            buffer.write(chunk)
            digest.update(chunk)
        if total != size:
            raise exceptions.ValidationError("Ciphertext size mismatch.")
        expected = bytes(attachment.ciphertext_sha256)
        if not any(
            hmac.compare_digest(expected, value)
            for value in (digest.hexdigest().encode("ascii"), base64.b64encode(digest.digest()))
        ):
            raise exceptions.ValidationError("Ciphertext checksum mismatch.")
        buffer.seek(0)
        write_ciphertext(attachment.object_key, buffer)


def stream_ciphertext(attachment):
    try:
        body = open_ciphertext(attachment.object_key)
    except OSError as error:
        raise StorageUnavailable() from error
    if os.fstat(body.fileno()).st_size != attachment.ciphertext_size:
        body.close()
        raise StorageUnavailable()

    async def chunks():
        try:
            while chunk := await asyncio.to_thread(body.read, 64 * 1024):
                yield chunk
        finally:
            body.close()

    result = StreamingHttpResponse(chunks(), content_type="application/octet-stream")
    result["Content-Length"] = attachment.ciphertext_size
    result["Content-Disposition"] = 'attachment; filename="encrypted-attachment.bin"'
    result["Cache-Control"] = "no-store"
    result["X-Content-Type-Options"] = "nosniff"
    # Close even when the client disconnects before consuming the generator.
    result._resource_closers.append(body.close)
    return result

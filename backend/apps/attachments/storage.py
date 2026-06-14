from __future__ import annotations

from dataclasses import dataclass

from django.conf import settings


@dataclass(frozen=True)
class PresignedObjectTarget:
    object_key: str
    url: str | None
    fields: dict
    method: str
    expires_in: int


def configured_bucket() -> str:
    return settings.ATTACHMENT_STORAGE.get("bucket", "")


def s3_client():
    if not configured_bucket():
        return None
    import boto3

    return boto3.client(
        "s3",
        endpoint_url=settings.ATTACHMENT_STORAGE.get("endpoint_url") or None,
        region_name=settings.ATTACHMENT_STORAGE.get("region_name") or None,
    )


def presigned_upload_target(object_key: str, ciphertext_size: int) -> PresignedObjectTarget:
    expires_in = settings.ATTACHMENT_STORAGE["upload_url_ttl_seconds"]
    client = s3_client()
    if client is None:
        return PresignedObjectTarget(object_key=object_key, url=None, fields={}, method="PUT", expires_in=expires_in)
    url = client.generate_presigned_url(
        ClientMethod="put_object",
        Params={
            "Bucket": configured_bucket(),
            "Key": object_key,
            "ContentLength": ciphertext_size,
        },
        ExpiresIn=expires_in,
    )
    return PresignedObjectTarget(object_key=object_key, url=url, fields={}, method="PUT", expires_in=expires_in)


def presigned_download_target(object_key: str) -> PresignedObjectTarget:
    expires_in = settings.ATTACHMENT_STORAGE["download_url_ttl_seconds"]
    client = s3_client()
    if client is None:
        return PresignedObjectTarget(object_key=object_key, url=None, fields={}, method="GET", expires_in=expires_in)
    url = client.generate_presigned_url(
        ClientMethod="get_object",
        Params={"Bucket": configured_bucket(), "Key": object_key},
        ExpiresIn=expires_in,
    )
    return PresignedObjectTarget(object_key=object_key, url=url, fields={}, method="GET", expires_in=expires_in)


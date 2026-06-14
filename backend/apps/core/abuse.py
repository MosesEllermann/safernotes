from __future__ import annotations

from dataclasses import dataclass

from django.core.cache import cache


@dataclass(frozen=True)
class AbuseLimit:
    key: str
    limit: int
    window_seconds: int


ABUSE_LIMITS = {
    "sync_batch": AbuseLimit("sync_batch", limit=120, window_seconds=60),
    "attachment_initiate": AbuseLimit("attachment_initiate", limit=30, window_seconds=60),
    "share_invite": AbuseLimit("share_invite", limit=60, window_seconds=3600),
}


def increment_metadata_limit(limit_name: str, actor_key: str) -> tuple[bool, int]:
    limit = ABUSE_LIMITS[limit_name]
    cache_key = f"abuse:{limit.key}:{actor_key}"
    count = cache.get(cache_key, 0) + 1
    cache.set(cache_key, count, timeout=limit.window_seconds)
    return count <= limit.limit, count


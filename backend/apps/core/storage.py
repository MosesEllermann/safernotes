from __future__ import annotations

import json


def encrypted_json_size(value: object) -> int:
    if value is None:
        return 0
    serialized = json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    )
    return len(serialized.encode("utf-8"))


def encrypted_note_storage_size(encrypted_payload: object, payload_hash: object) -> int:
    hash_size = len(payload_hash) if payload_hash is not None else 0
    return encrypted_json_size(encrypted_payload) + hash_size
